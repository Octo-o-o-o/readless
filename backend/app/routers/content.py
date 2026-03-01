"""REST API routes for content CRUD, expand, and follow-up Q&A."""

import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.models.content import Content
from app.models.content_tag import ContentTag
from app.models.paragraph import Paragraph
from app.models.user_tag import UserTag
from app.schemas.content import (
    ContentCreateRequest,
    ContentResponse,
    ExpandRequest,
    FollowUpRequest,
    TextResponse,
)
from app.schemas.summary import OutlinePoint
from app.schemas.summary import ContentSummary
from app.services.extractor import ExtractedContent, ExtractedParagraph
from app.services.pipeline import ProcessingPipeline
from app.services.summarizer import SummarizationService
from app.services.translator import _get_service as get_translator

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/content", tags=["content"])

_pipeline: ProcessingPipeline | None = None
_summarizer: SummarizationService | None = None


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


async def _get_content_tags(
    content_id: str,
    db: AsyncSession,
) -> list[str]:
    """Helper to fetch tags for a content item via JOIN.

    Only returns active tags (excludes soft-deleted tags).
    """
    try:
        stmt = (
            select(UserTag.tag_name)
            .join(ContentTag, UserTag.id == ContentTag.tag_id)
            .where(
                ContentTag.content_id == content_id,
                UserTag.deleted_at.is_(None),
            )
        )
        result = await db.execute(stmt)
        return [row[0] for row in result.all()]
    except Exception as e:
        # Log error but don't fail the entire response
        logger.warning(f"Failed to fetch tags for content {content_id}: {e}")
        return []


@router.post("/", response_model=ContentResponse)
async def create_content(
    req: ContentCreateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Ingest content: extract, summarize, and store."""
    content = await _get_pipeline().process(
        source_type=req.source_type,
        body=req.body,
        user_id=user_id,
        source_app_name=req.source_app_name,
        source_app_bundle_id=req.source_app_bundle_id,
        channel=req.channel,
        db=db,
    )
    return await _to_response(content, db)


@router.get("/", response_model=list[ContentResponse])
async def list_contents(
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[ContentResponse]:
    """List all contents for the current user with pagination."""
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

    # Batch-fetch ALL tags for all contents in ONE query
    content_ids = [c.id for c in contents]
    stmt = (
        select(ContentTag.content_id, UserTag.tag_name)
        .join(UserTag, ContentTag.tag_id == UserTag.id)
        .where(
            ContentTag.content_id.in_(content_ids),
            UserTag.deleted_at.is_(None),
        )
    )
    tag_result = await db.execute(stmt)

    # Group tags by content_id
    tags_by_content: dict[str, list[str]] = {}
    for content_id, tag_name in tag_result.all():
        tags_by_content.setdefault(content_id, []).append(tag_name)

    # Build responses with pre-fetched tags
    responses = []
    for content in contents:
        tags = tags_by_content.get(content.id, [])
        responses.append(
            ContentResponse(
                id=content.id,
                title=content.title,
                source_url=content.source_url,
                source_type=content.source_type,
                source_app_name=content.source_app_name,
                source_app_bundle_id=content.source_app_bundle_id,
                source_language=content.source_language,
                l0_summary=content.l0_summary,
                l1_outline=content.l1_outline,
                tags=tags,
                status=content.status,
                created_at=content.created_at,
                updated_at=content.updated_at,
                podcast_url=None,
                full_text=content.full_text,  # Include for local search
            )
        )

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


@router.post("/{content_id}/expand", response_model=TextResponse)
async def expand_point(
    content_id: str,
    req: ExpandRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Expand an outline point into a detailed explanation."""
    content = await db.get(Content, content_id)
    if not content or content.user_id != user_id:
        raise HTTPException(404)
    paras_result = await db.execute(
        select(Paragraph)
        .where(Paragraph.content_id == content_id)
        .order_by(Paragraph.position)
    )
    paras = list(paras_result.scalars())
    extracted = ExtractedContent(
        title=content.title,
        full_text=content.full_text or "",
        paragraphs=[
            ExtractedParagraph(
                anchor_id=p.anchor_id, text=p.text, position=p.position
            )
            for p in paras
        ],
    )
    outline = content.l1_outline or []
    if req.point_index >= len(outline):
        raise HTTPException(400, "Invalid point index")
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
    content = await db.get(Content, content_id)
    if not content or content.user_id != user_id:
        raise HTTPException(404)
    paras_result = await db.execute(
        select(Paragraph)
        .where(Paragraph.content_id == content_id)
        .order_by(Paragraph.position)
    )
    paras = list(paras_result.scalars())
    extracted = ExtractedContent(
        title=content.title,
        full_text=content.full_text or "",
        paragraphs=[
            ExtractedParagraph(
                anchor_id=p.anchor_id, text=p.text, position=p.position
            )
            for p in paras
        ],
    )
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
    """Convert a Content ORM instance to a ContentResponse.

    Fetches tags via JOIN from content_tags table.
    """
    tags = await _get_content_tags(c.id, db)

    return ContentResponse(
        id=c.id,
        title=c.title,
        source_url=c.source_url,
        source_type=c.source_type,
        source_app_name=c.source_app_name,
        source_app_bundle_id=c.source_app_bundle_id,
        source_language=c.source_language,
        l0_summary=c.l0_summary,
        l1_outline=c.l1_outline,
        tags=tags,
        status=c.status,
        created_at=c.created_at,
        updated_at=c.updated_at,
        full_text=c.full_text,  # Include full_text for local search sync
    )
