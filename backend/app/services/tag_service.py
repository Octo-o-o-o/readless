"""Tag business rules and data access orchestration."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import delete, desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.content_tag import ContentTag
from app.models.user_tag import UserTag
from app.schemas.content import ContentListItemResponse
from app.schemas.tag import UserTagResponse
from app.services.content_response import (
    ContentResponseBuilder,
    get_content_response_builder,
)


class TagService:
    """Encapsulates tag ownership, soft-delete, and content-tag rules."""

    def __init__(
        self,
        db: AsyncSession,
        *,
        response_builder: ContentResponseBuilder | None = None,
    ):
        self.db = db
        self.response_builder = response_builder or get_content_response_builder()

    async def list_user_tags(self, user_id: str) -> list[UserTagResponse]:
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

        result = await self.db.execute(query)
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

    async def create_tag(self, *, user_id: str, tag_name: str) -> UserTagResponse:
        existing_query = select(UserTag).where(
            UserTag.user_id == user_id,
            UserTag.tag_name == tag_name,
        )
        result = await self.db.execute(existing_query)
        existing_tag = result.scalar_one_or_none()

        if existing_tag:
            if existing_tag.deleted_at is None:
                raise ValueError(f"Tag '{tag_name}' already exists")
            raise ValueError(
                f"Tag '{tag_name}' was previously deleted."
                " Please use a different name."
            )

        new_tag = UserTag(
            user_id=user_id,
            tag_name=tag_name,
        )
        self.db.add(new_tag)
        await self.db.commit()
        await self.db.refresh(new_tag)

        return UserTagResponse(
            id=new_tag.id,
            tag_name=new_tag.tag_name,
            content_count=0,
            created_at=new_tag.created_at,
        )

    async def delete_tag(self, *, user_id: str, tag_id: int) -> None:
        tag = await self._get_active_tag(user_id=user_id, tag_id=tag_id)
        if tag is None:
            raise ValueError("Tag not found")

        tag.deleted_at = datetime.now(UTC)
        await self.db.commit()

    async def get_content_tags(
        self,
        *,
        user_id: str,
        content_id: str,
    ) -> list[UserTagResponse]:
        content = await self._get_owned_content(user_id=user_id, content_id=content_id)
        if content is None:
            raise ValueError("Content not found")

        query = (
            select(UserTag)
            .join(ContentTag, UserTag.id == ContentTag.tag_id)
            .where(ContentTag.content_id == content_id)
            .where(UserTag.deleted_at.is_(None))
            .order_by(desc(UserTag.created_at))
        )
        result = await self.db.execute(query)
        tags = result.scalars().all()

        return [
            UserTagResponse(
                id=tag.id,
                tag_name=tag.tag_name,
                content_count=0,
                created_at=tag.created_at,
            )
            for tag in tags
        ]

    async def update_content_tags(
        self,
        *,
        user_id: str,
        content_id: str,
        tag_names: list[str],
    ) -> list[UserTagResponse]:
        content = await self._get_owned_content(user_id=user_id, content_id=content_id)
        if content is None:
            raise ValueError("Content not found")

        tag_ids = await self._get_or_create_tag_ids(
            user_id=user_id,
            tag_names=tag_names,
        )

        await self.db.execute(
            delete(ContentTag).where(ContentTag.content_id == content_id)
        )
        for tag_id in tag_ids:
            self.db.add(
                ContentTag(
                    content_id=content_id,
                    tag_id=tag_id,
                    user_id=user_id,
                )
            )

        await self.db.commit()
        return await self.get_content_tags(user_id=user_id, content_id=content_id)

    async def get_contents_by_tag(
        self,
        *,
        user_id: str,
        tag_id: int,
    ) -> list[ContentListItemResponse]:
        tag = await self._get_active_tag(user_id=user_id, tag_id=tag_id)
        if tag is None:
            raise ValueError("Tag not found")

        query = (
            select(Content)
            .join(ContentTag, Content.id == ContentTag.content_id)
            .where(ContentTag.tag_id == tag_id)
            .where(Content.user_id == user_id)
            .order_by(desc(Content.created_at))
        )
        result = await self.db.execute(query)
        contents = result.scalars().all()
        if not contents:
            return []

        return await self.response_builder.build_list_items(list(contents), self.db)

    async def _get_active_tag(self, *, user_id: str, tag_id: int) -> UserTag | None:
        query = select(UserTag).where(
            UserTag.id == tag_id,
            UserTag.user_id == user_id,
            UserTag.deleted_at.is_(None),
        )
        result = await self.db.execute(query)
        return result.scalar_one_or_none()

    async def _get_owned_content(
        self,
        *,
        user_id: str,
        content_id: str,
    ) -> Content | None:
        query = select(Content).where(
            Content.id == content_id,
            Content.user_id == user_id,
        )
        result = await self.db.execute(query)
        return result.scalar_one_or_none()

    async def _get_or_create_tag_ids(
        self,
        *,
        user_id: str,
        tag_names: list[str],
    ) -> list[int]:
        tag_ids: list[int] = []
        seen_tag_names: set[str] = set()
        for tag_name in tag_names:
            if tag_name in seen_tag_names:
                continue
            seen_tag_names.add(tag_name)

            tag_query = select(UserTag).where(
                UserTag.user_id == user_id,
                UserTag.tag_name == tag_name,
                UserTag.deleted_at.is_(None),
            )
            result = await self.db.execute(tag_query)
            tag = result.scalar_one_or_none()

            if tag is None:
                tag = UserTag(user_id=user_id, tag_name=tag_name)
                self.db.add(tag)
                await self.db.flush()

            tag_ids.append(tag.id)

        return tag_ids
