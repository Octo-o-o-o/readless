"""Content response assembly helpers shared across routers."""

from __future__ import annotations

import logging

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.content_tag import ContentTag
from app.models.user_tag import UserTag
from app.schemas.content import ContentListItemResponse, ContentResponse
from app.schemas.summary import stabilize_outline_points

logger = logging.getLogger(__name__)


class ContentResponseBuilder:
    """Build API response DTOs for content entities."""

    def _base_payload(
        self,
        content: Content,
        tags: list[str],
    ) -> dict:
        return {
            "id": content.id,
            "title": content.title,
            "source_url": content.source_url,
            "source_type": content.source_type,
            "source_app_name": content.source_app_name,
            "source_app_bundle_id": content.source_app_bundle_id,
            "source_language": content.source_language,
            "l0_summary": content.l0_summary,
            "tags": tags,
            "status": content.status,
            "created_at": content.created_at,
            "updated_at": content.updated_at,
            "podcast_url": None,
        }

    async def get_content_tags(
        self,
        content_id: str,
        db: AsyncSession,
    ) -> list[str]:
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
        except Exception as exc:
            logger.warning("Failed to fetch tags for content %s: %s", content_id, exc)
            return []

    async def get_tags_by_content_ids(
        self,
        content_ids: list[str],
        db: AsyncSession,
    ) -> dict[str, list[str]]:
        if not content_ids:
            return {}

        stmt = (
            select(ContentTag.content_id, UserTag.tag_name)
            .join(UserTag, ContentTag.tag_id == UserTag.id)
            .where(
                ContentTag.content_id.in_(content_ids),
                UserTag.deleted_at.is_(None),
            )
        )
        result = await db.execute(stmt)

        tags_by_content: dict[str, list[str]] = {}
        for content_id, tag_name in result.all():
            tags_by_content.setdefault(content_id, []).append(tag_name)
        return tags_by_content

    def build_list_item_with_tags(
        self,
        content: Content,
        tags: list[str],
    ) -> ContentListItemResponse:
        return ContentListItemResponse(
            **self._base_payload(content, tags),
        )

    def build_detail_with_tags(
        self,
        content: Content,
        tags: list[str],
    ) -> ContentResponse:
        outline = None
        if content.l1_outline:
            outline = [
                point.model_dump()
                for point in stabilize_outline_points(
                    content.l1_outline,
                    content_id=content.id,
                )
            ]
        return ContentResponse(
            **self._base_payload(content, tags),
            l1_outline=outline,
            full_text=content.full_text,
        )

    async def build_detail(
        self,
        content: Content,
        db: AsyncSession,
    ) -> ContentResponse:
        tags = await self.get_content_tags(content.id, db)
        return self.build_detail_with_tags(content, tags)

    async def build_list_items(
        self,
        contents: list[Content],
        db: AsyncSession,
    ) -> list[ContentListItemResponse]:
        if not contents:
            return []

        content_ids = [content.id for content in contents]
        tags_by_content = await self.get_tags_by_content_ids(content_ids, db)
        return [
            self.build_list_item_with_tags(
                content,
                tags_by_content.get(content.id, []),
            )
            for content in contents
        ]


_content_response_builder: ContentResponseBuilder | None = None


def get_content_response_builder() -> ContentResponseBuilder:
    global _content_response_builder
    if _content_response_builder is None:
        _content_response_builder = ContentResponseBuilder()
    return _content_response_builder
