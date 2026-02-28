"""REST API routes for content CRUD, expand, and follow-up Q&A."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
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
from app.schemas.summary import OutlinePoint
from app.services.extractor import ExtractedContent, ExtractedParagraph
from app.services.pipeline import ProcessingPipeline
from app.services.summarizer import SummarizationService

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
    return _to_response(content)


@router.get("/", response_model=list[ContentResponse])
async def list_contents(
    skip: int = 0,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """List content items for the current user, newest first."""
    result = await db.execute(
        select(Content)
        .where(Content.user_id == user_id)
        .order_by(desc(Content.created_at))
        .offset(skip)
        .limit(limit)
    )
    return [_to_response(c) for c in result.scalars()]


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
    return _to_response(content)


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


def _to_response(c: Content) -> ContentResponse:
    """Convert a Content ORM instance to a ContentResponse."""
    return ContentResponse(
        id=c.id,
        title=c.title,
        source_url=c.source_url,
        source_type=c.source_type,
        source_app_name=c.source_app_name,
        l0_summary=c.l0_summary,
        l1_outline=c.l1_outline,
        tags=c.tags,
        status=c.status,
        created_at=c.created_at,
    )
