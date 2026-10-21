"""REST API routes for tag management."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.schemas.content import ContentListItemResponse
from app.schemas.tag import (
    ContentTagsUpdateRequest,
    TagCreateRequest,
    UserTagResponse,
)
from app.services.tag_service import TagService

router = APIRouter(prefix="/api/v1/tags", tags=["tags"])


def _get_tag_service(db: AsyncSession) -> TagService:
    return TagService(db)


@router.get("/", response_model=list[UserTagResponse])
async def list_user_tags(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> list[UserTagResponse]:
    """List all tags for the current user with content count."""
    return await _get_tag_service(db).list_user_tags(user_id=user_id)


@router.post("/", response_model=UserTagResponse, status_code=201)
async def create_tag(
    req: TagCreateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> UserTagResponse:
    """Create a new tag for the current user."""
    try:
        return await _get_tag_service(db).create_tag(
            user_id=user_id,
            tag_name=req.tag_name,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.delete("/{tag_id}", status_code=204)
async def delete_tag(
    tag_id: int,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> None:
    """Soft delete a tag."""
    try:
        await _get_tag_service(db).delete_tag(user_id=user_id, tag_id=tag_id)
    except ValueError as exc:
        if str(exc) == "Tag not found":
            raise HTTPException(status_code=404, detail=str(exc))
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/content/{content_id}/tags", response_model=list[UserTagResponse])
async def get_content_tags(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> list[UserTagResponse]:
    """Get all tags for a specific content item."""
    try:
        return await _get_tag_service(db).get_content_tags(
            user_id=user_id,
            content_id=content_id,
        )
    except ValueError as exc:
        if str(exc) == "Content not found":
            raise HTTPException(status_code=404, detail=str(exc))
        raise HTTPException(status_code=400, detail=str(exc))


@router.put("/content/{content_id}/tags", response_model=list[UserTagResponse])
async def update_content_tags(
    content_id: str,
    req: ContentTagsUpdateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> list[UserTagResponse]:
    """Replace all tags for a content item with the provided list."""
    try:
        return await _get_tag_service(db).update_content_tags(
            user_id=user_id,
            content_id=content_id,
            tag_names=req.tag_names,
        )
    except ValueError as exc:
        if str(exc) == "Content not found":
            raise HTTPException(status_code=404, detail=str(exc))
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/{tag_id}/contents", response_model=list[ContentListItemResponse])
async def get_contents_by_tag(
    tag_id: int,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> list[ContentListItemResponse]:
    """Get all content items with a specific tag."""
    try:
        return await _get_tag_service(db).get_contents_by_tag(
            user_id=user_id,
            tag_id=tag_id,
        )
    except ValueError as exc:
        if str(exc) == "Tag not found":
            raise HTTPException(status_code=404, detail=str(exc))
        raise HTTPException(status_code=400, detail=str(exc))
