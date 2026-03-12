"""REST API routes for content CRUD, expand, and follow-up Q&A."""

import asyncio
import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.config import settings
from app.database import get_db
from app.models.content import Content
from app.models.paragraph import Paragraph
from app.schemas.content import (
    ContentCreateRequest,
    ContentResponse,
    ExpandRequest,
    FollowUpRequest,
    TextResponse,
)
from app.schemas.summary import ContentSummary, OutlinePoint
from app.services.content_jobs import ContentJobService, get_content_job_service
from app.services.content_response import (
    ContentResponseBuilder,
    get_content_response_builder,
)
from app.services.extractor import ExtractedContent, ExtractedParagraph
from app.services.pipeline import ProcessingPipeline
from app.services.summarizer import SummarizationService
from app.services.translator import _get_service as get_translator

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/content", tags=["content"])

_pipeline: ProcessingPipeline | None = None
_summarizer: SummarizationService | None = None
_content_jobs: ContentJobService | None = None
_content_response_builder: ContentResponseBuilder | None = None
_processing_tasks: dict[str, asyncio.Task[None]] = (
    get_content_job_service().processing_tasks
)


def _get_pipeline() -> ProcessingPipeline:
    global _pipeline
    if _pipeline is None:
        _pipeline = ProcessingPipeline()
    return _pipeline


def _get_summarizer() -> SummarizationService:
    global _summarizer
    if _summarizer is None:
        _summarizer = SummarizationService()
    return _summarizer


def _get_content_jobs() -> ContentJobService:
    global _content_jobs
    if _content_jobs is None:
        _content_jobs = get_content_job_service()
    return _content_jobs


def _get_response_builder() -> ContentResponseBuilder:
    global _content_response_builder
    if _content_response_builder is None:
        _content_response_builder = get_content_response_builder()
    return _content_response_builder


def _schedule_content_processing(
    *,
    content_id: str,
    source_type: str,
    body: str,
    user_id: str,
) -> None:
    _get_content_jobs().schedule_processing(
        content_id=content_id,
        source_type=source_type,
        body=body,
        user_id=user_id,
        processor=_process_content_in_background,
    )


async def _process_content_in_background(
    *,
    content_id: str,
    source_type: str,
    body: str,
    user_id: str,
) -> None:
    await _get_content_jobs().process_content_in_background(
        content_id=content_id,
        source_type=source_type,
        body=body,
        user_id=user_id,
    )


async def _get_content_tags(
    content_id: str,
    db: AsyncSession,
) -> list[str]:
    """Compatibility helper for tests and route-local callers."""
    return await _get_response_builder().get_content_tags(content_id, db)


@router.post("/", response_model=ContentResponse)
async def create_content(
    req: ContentCreateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Create a pending content item and process it asynchronously."""
    content = await _get_pipeline().create_pending_content(
        source_type=req.source_type,
        body=req.body,
        user_id=user_id,
        source_app_name=req.source_app_name,
        source_app_bundle_id=req.source_app_bundle_id,
        channel=req.channel,
        db=db,
    )
    await db.commit()
    await db.refresh(content)
    _schedule_content_processing(
        content_id=content.id,
        source_type=req.source_type,
        body=req.body,
        user_id=user_id,
    )
    return await _to_response(content, db)


@router.get("/", response_model=list[ContentResponse])
async def list_contents(
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    skip: int | None = Query(default=None, ge=0),
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[ContentResponse]:
    """List all contents for the current user with pagination."""
    if skip is not None:
        # Backward-compatibility for older clients still sending `skip`.
        offset = skip

    # Fetch contents
    stmt = (
        select(Content)
        .where(Content.user_id == user_id)
        .order_by(Content.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    result = await db.execute(stmt)
    contents = result.scalars().all()

    if not contents:
        return []

    response_builder = _get_response_builder()
    content_ids = [content.id for content in contents]
    tags_by_content = await response_builder.get_tags_by_content_ids(content_ids, db)

    any_status_updated = False
    responses: list[ContentResponse] = []
    for content in contents:
        if _mark_stale_content_as_failed(content):
            any_status_updated = True
        _schedule_content_recovery(content)
        responses.append(
            response_builder.build_with_tags(
                content,
                tags_by_content.get(content.id, []),
            )
        )

    if any_status_updated:
        await db.commit()

    return responses


@router.get("/{content_id}", response_model=ContentResponse)
async def get_content(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Get a single content item by ID."""
    content = await db.get(Content, content_id)
    if not content or content.user_id != user_id:
        raise HTTPException(404, "Content not found")

    if _mark_stale_content_as_failed(content):
        await db.commit()
    _schedule_content_recovery(content)
    return await _to_response(content, db)


@router.get("/{content_id}/paragraphs")
async def get_paragraphs(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Get all paragraphs for a content item, ordered by position."""
    content = await db.get(Content, content_id)
    if not content or content.user_id != user_id:
        raise HTTPException(404, "Content not found")
    result = await db.execute(
        select(Paragraph)
        .where(Paragraph.content_id == content_id)
        .order_by(Paragraph.position)
    )
    return [
        {"anchor_id": p.anchor_id, "text": p.text, "position": p.position}
        for p in result.scalars()
    ]


async def _get_extracted_content(
    content_id: str,
    user_id: str,
    db: AsyncSession,
) -> tuple[Content, ExtractedContent]:
    """Load content and build ExtractedContent for summarizer operations.

    Returns the ORM Content and its ExtractedContent representation.
    Raises HTTPException 404 if content not found or not owned by user.
    """
    content = await db.get(Content, content_id)
    if not content or content.user_id != user_id:
        raise HTTPException(404, "Content not found")

    paras_result = await db.execute(
        select(Paragraph)
        .where(Paragraph.content_id == content_id)
        .order_by(Paragraph.position)
    )
    extracted = ExtractedContent(
        title=content.title,
        full_text=content.full_text or "",
        paragraphs=[
            ExtractedParagraph(
                anchor_id=p.anchor_id, text=p.text, position=p.position
            )
            for p in paras_result.scalars()
        ],
    )
    return content, extracted


@router.post("/{content_id}/expand", response_model=TextResponse)
async def expand_point(
    content_id: str,
    req: ExpandRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Expand an outline point into a detailed explanation."""
    content, extracted = await _get_extracted_content(content_id, user_id, db)
    _ensure_content_ready(content)

    outline = content.l1_outline or []
    if req.point_index >= len(outline):
        raise HTTPException(
            400,
            f"Invalid outline point. Select a valid point (0-{len(outline)-1}).",
        )

    point = OutlinePoint(**outline[req.point_index])
    detail = await _get_summarizer().expand_point(extracted, point)
    return TextResponse(text=detail)


@router.post("/{content_id}/ask", response_model=TextResponse)
async def ask_followup(
    content_id: str,
    req: FollowUpRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Answer a follow-up question based on the content."""
    content, extracted = await _get_extracted_content(content_id, user_id, db)
    _ensure_content_ready(content)
    answer = await _get_summarizer().ask_followup(extracted, req.question)
    return TextResponse(text=answer)


@router.post("/{content_id}/translate", response_model=ContentResponse)
async def translate_content(
    content_id: str,
    target_language: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """
    Translate content summaries to target language.

    Args:
        content_id: Content ID to translate
        target_language: Target language ISO code (en, zh, ja, etc.)

    Returns:
        ContentResponse with translated L0 summary and L1 outline
    """
    content = await db.get(Content, content_id)
    if not content or content.user_id != user_id:
        raise HTTPException(404, "Content not found")
    _ensure_content_ready(content)

    # Check if we have summaries to translate
    if not content.l0_summary or not content.l1_outline:
        raise HTTPException(400, "Content has no summaries to translate")

    # Fetch tags via JOIN
    tags = await _get_content_tags(content_id, db)

    # Build current summary from content
    current_summary = ContentSummary(
        l0_summary=content.l0_summary,
        l1_outline=[OutlinePoint(**item) for item in content.l1_outline],
        tags=tags,
        keywords=content.keywords or [],
    )

    # Translate summary
    translator = get_translator()
    translated_summary = await translator.translate_summary(
        summary=current_summary,
        target_lang=target_language,
        source_lang=content.source_language,
    )

    # Return translated content response (don't modify DB)
    return ContentResponse(
        id=content.id,
        title=content.title,
        source_url=content.source_url,
        source_type=content.source_type,
        source_app_name=content.source_app_name,
        source_app_bundle_id=content.source_app_bundle_id,
        source_language=content.source_language,  # Keep original language
        l0_summary=translated_summary.l0_summary,
        l1_outline=[p.model_dump() for p in translated_summary.l1_outline],
        tags=tags,
        status=content.status,
        created_at=content.created_at,
        updated_at=content.updated_at,
        full_text=content.full_text,  # Include full_text
    )


async def _to_response(c: Content, db: AsyncSession) -> ContentResponse:
    """Compatibility helper for tests and route-local callers."""
    return await _get_response_builder().build(c, db)


def _ensure_content_ready(content: Content) -> None:
    """Guard endpoints that require a completed summary."""
    if content.status == "failed":
        raise HTTPException(409, "Content processing failed")
    if content.status != "ready":
        raise HTTPException(409, "Content is still processing")


def _schedule_content_recovery(content: Content) -> None:
    """Best-effort replay for recoverable async jobs after process restarts."""
    if content.status not in {"pending", "processing"}:
        return

    if body := _recoverable_content_body(content):
        _schedule_content_processing(
            content_id=content.id,
            source_type=content.source_type,
            body=body,
            user_id=content.user_id,
        )


def _recoverable_content_body(content: Content) -> str | None:
    """Compatibility helper used by tests."""
    return _get_content_jobs().recoverable_content_body(content)


def _mark_stale_content_as_failed(content: Content) -> bool:
    """Prevent permanently stuck states when processing exceeds timeout."""
    if settings.content_processing_timeout_seconds <= 0:
        return False
    return _get_content_jobs().mark_stale_content_as_failed(content)
