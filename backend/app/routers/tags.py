"""REST API routes for tag management."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.models.content import Content
from app.models.content_tag import ContentTag
from app.models.user_tag import UserTag
from app.schemas.content import ContentResponse
from app.schemas.tag import (
    ContentTagsUpdateRequest,
    TagCreateRequest,
    UserTagResponse,
)

router = APIRouter(prefix="/api/v1/tags", tags=["tags"])


# ------------------------------------------------------------------ #
#  GET /api/v1/tags - List user's tags with content count
# ------------------------------------------------------------------ #


@router.get("/", response_model=list[UserTagResponse])
async def list_user_tags(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> list[UserTagResponse]:
    """List all tags for the current user with content count.

    Returns tags sorted by creation date (newest first), excluding soft-deleted tags.
    Each tag includes the count of associated content items.
    """
    # Query user tags with content count using LEFT JOIN
    # Exclude soft-deleted tags
    query = (
        select(
            UserTag.id,
            UserTag.tag_name,
            UserTag.created_at,
            func.count(ContentTag.content_id).label("content_count"),
        )
        .outerjoin(ContentTag, UserTag.id == ContentTag.tag_id)
        .where(UserTag.user_id == user_id)
        .where(UserTag.deleted_at.is_(None))
        .group_by(UserTag.id, UserTag.tag_name, UserTag.created_at)
        .order_by(desc(UserTag.created_at))
    )

    result = await db.execute(query)
    rows = result.all()

    return [
        UserTagResponse(
            id=row.id,
            tag_name=row.tag_name,
            content_count=row.content_count,
            created_at=row.created_at,
        )
        for row in rows
    ]


# ------------------------------------------------------------------ #
#  POST /api/v1/tags - Create new tag
# ------------------------------------------------------------------ #


@router.post("/", response_model=UserTagResponse, status_code=201)
async def create_tag(
    req: TagCreateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> UserTagResponse:
    """Create a new tag for the current user.

    Returns 400 if tag with the same name already exists (including soft-deleted).
    """
    # Check if tag already exists (including soft-deleted)
    existing_query = select(UserTag).where(
        UserTag.user_id == user_id,
        UserTag.tag_name == req.tag_name,
    )
    result = await db.execute(existing_query)
    existing_tag = result.scalar_one_or_none()

    if existing_tag:
        if existing_tag.deleted_at is None:
            raise HTTPException(
                status_code=400,
                detail=f"Tag '{req.tag_name}' already exists",
            )
        else:
            raise HTTPException(
                status_code=400,
                detail=f"Tag '{req.tag_name}' was previously deleted. Please use a different name.",
            )

    # Create new tag
    new_tag = UserTag(
        user_id=user_id,
        tag_name=req.tag_name,
    )
    db.add(new_tag)
    await db.commit()
    await db.refresh(new_tag)

    return UserTagResponse(
        id=new_tag.id,
        tag_name=new_tag.tag_name,
        content_count=0,
        created_at=new_tag.created_at,
    )


# ------------------------------------------------------------------ #
#  DELETE /api/v1/tags/{tag_id} - Soft delete tag
# ------------------------------------------------------------------ #


@router.delete("/{tag_id}", status_code=204)
async def delete_tag(
    tag_id: int,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> None:
    """Soft delete a tag.

    Sets deleted_at timestamp. Associated ContentTag relationships are CASCADE deleted
    automatically by the database due to the FK constraint.

    Returns 404 if tag doesn't exist or doesn't belong to user.
    """
    # Find tag
    query = select(UserTag).where(
        UserTag.id == tag_id,
        UserTag.user_id == user_id,
        UserTag.deleted_at.is_(None),
    )
    result = await db.execute(query)
    tag = result.scalar_one_or_none()

    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")

    # Soft delete the tag
    tag.deleted_at = datetime.now(timezone.utc)
    await db.commit()

    # Note: ContentTag relationships will be CASCADE deleted automatically
    # when the UserTag is hard-deleted in the future (if implemented)
    # For now, soft-deleting the tag effectively hides it from all queries


# ------------------------------------------------------------------ #
#  GET /api/v1/tags/content/{content_id}/tags - Get content's tags
# ------------------------------------------------------------------ #


@router.get("/content/{content_id}/tags", response_model=list[UserTagResponse])
async def get_content_tags(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> list[UserTagResponse]:
    """Get all tags for a specific content item.

    Returns 404 if content doesn't exist or doesn't belong to user.
    Only returns non-deleted tags.
    """
    # Verify content exists and belongs to user
    content_query = select(Content).where(
        Content.id == content_id,
        Content.user_id == user_id,
    )
    result = await db.execute(content_query)
    content = result.scalar_one_or_none()

    if not content:
        raise HTTPException(status_code=404, detail="Content not found")

    # Get tags for this content
    query = (
        select(UserTag)
        .join(ContentTag, UserTag.id == ContentTag.tag_id)
        .where(ContentTag.content_id == content_id)
        .where(UserTag.deleted_at.is_(None))
        .order_by(desc(UserTag.created_at))
    )

    result = await db.execute(query)
    tags = result.scalars().all()

    return [
        UserTagResponse(
            id=tag.id,
            tag_name=tag.tag_name,
            content_count=0,  # Not needed for this endpoint
            created_at=tag.created_at,
        )
        for tag in tags
    ]


# ------------------------------------------------------------------ #
#  PUT /api/v1/tags/content/{content_id}/tags - Update content tags
# ------------------------------------------------------------------ #


@router.put("/content/{content_id}/tags", response_model=list[UserTagResponse])
async def update_content_tags(
    content_id: str,
    req: ContentTagsUpdateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> list[UserTagResponse]:
    """Update tags for a content item.

    Replaces all existing tags with the provided list.
    Auto-creates tags that don't exist yet.

    Returns 404 if content doesn't exist or doesn't belong to user.
    """
    # Verify content exists and belongs to user
    content_query = select(Content).where(
        Content.id == content_id,
        Content.user_id == user_id,
    )
    result = await db.execute(content_query)
    content = result.scalar_one_or_none()

    if not content:
        raise HTTPException(status_code=404, detail="Content not found")

    # Get or create all tags
    tag_ids = []
    for tag_name in req.tag_names:
        # Check if tag exists (excluding soft-deleted)
        tag_query = select(UserTag).where(
            UserTag.user_id == user_id,
            UserTag.tag_name == tag_name,
            UserTag.deleted_at.is_(None),
        )
        result = await db.execute(tag_query)
        tag = result.scalar_one_or_none()

        if not tag:
            # Auto-create the tag
            tag = UserTag(
                user_id=user_id,
                tag_name=tag_name,
            )
            db.add(tag)
            await db.flush()  # Get the ID without committing

        tag_ids.append(tag.id)

    # Delete existing content-tag relationships
    delete_query = delete(ContentTag).where(ContentTag.content_id == content_id)
    await db.execute(delete_query)

    # Create new content-tag relationships
    for tag_id in tag_ids:
        content_tag = ContentTag(
            content_id=content_id,
            tag_id=tag_id,
            user_id=user_id,
        )
        db.add(content_tag)

    await db.commit()

    # Return updated tags
    return await get_content_tags(content_id, db, user_id)


# ------------------------------------------------------------------ #
#  GET /api/v1/tags/{tag_id}/contents - Filter content by tag
# ------------------------------------------------------------------ #


@router.get("/{tag_id}/contents", response_model=list[ContentResponse])
async def get_contents_by_tag(
    tag_id: int,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
) -> list[ContentResponse]:
    """Get all content items with a specific tag.

    Returns 404 if tag doesn't exist or doesn't belong to user.
    Returns content sorted by creation date (newest first).
    """
    # Verify tag exists and belongs to user
    tag_query = select(UserTag).where(
        UserTag.id == tag_id,
        UserTag.user_id == user_id,
        UserTag.deleted_at.is_(None),
    )
    result = await db.execute(tag_query)
    tag = result.scalar_one_or_none()

    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")

    # Get all content with this tag
    query = (
        select(Content)
        .join(ContentTag, Content.id == ContentTag.content_id)
        .where(ContentTag.tag_id == tag_id)
        .where(Content.user_id == user_id)
        .order_by(desc(Content.created_at))
    )

    result = await db.execute(query)
    contents = result.scalars().all()

    if not contents:
        return []

    # Batch-fetch tags for all matched contents (avoids N+1 queries)
    content_ids = [content.id for content in contents]
    tag_query = (
        select(ContentTag.content_id, UserTag.tag_name)
        .join(UserTag, ContentTag.tag_id == UserTag.id)
        .where(
            ContentTag.content_id.in_(content_ids),
            UserTag.deleted_at.is_(None),
        )
    )
    tag_result = await db.execute(tag_query)
    tags_by_content: dict[str, list[str]] = {}
    for content_id, tag_name in tag_result.all():
        tags_by_content.setdefault(content_id, []).append(tag_name)

    return [
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
            tags=tags_by_content.get(content.id, []),
            status=content.status,
            created_at=content.created_at,
            updated_at=content.updated_at,
            full_text=content.full_text,
        )
        for content in contents
    ]
