"""REST API routes for podcast generation and retrieval."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.models.content import Content
from app.models.podcast import Podcast
from app.services.podcast import PodcastService

router = APIRouter(prefix="/api/v1/podcast", tags=["podcast"])

# Lazy-initialized singleton (same pattern as content and search routers)
_service: PodcastService | None = None


def _get_service() -> PodcastService:
    global _service
    if _service is None:
        _service = PodcastService()
    return _service


@router.post("/{content_id}/generate")
async def generate_podcast(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Generate a podcast from an existing content item."""
    content = await db.get(Content, content_id)
    if not content or content.user_id != user_id:
        raise HTTPException(404, "Content not found")

    # Check for existing ready podcast
    existing = await db.execute(
        select(Podcast).where(
            Podcast.content_id == content_id, Podcast.status == "ready"
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(409, "Podcast already exists")

    service = _get_service()
    podcast = await service.generate(content, db)
    return {"id": podcast.id, "status": podcast.status}


@router.get("/{content_id}")
async def get_podcast(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Get the latest podcast for a content item."""
    content = await db.get(Content, content_id)
    if not content or content.user_id != user_id:
        raise HTTPException(404, "Content not found")
    result = await db.execute(
        select(Podcast)
        .where(Podcast.content_id == content_id)
        .order_by(Podcast.created_at.desc())
    )
    podcast = result.scalar_one_or_none()
    if not podcast:
        raise HTTPException(404, "Podcast not found")
    return {
        "id": podcast.id,
        "status": podcast.status,
        "audio_url": podcast.audio_url,
        "chapters": podcast.chapters,
    }
