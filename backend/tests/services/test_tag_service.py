"""Tests for TagService business rules."""

from uuid import uuid4

import pytest

from app.models.content import Content
from app.models.content_tag import ContentTag
from app.services.tag_service import TagService


@pytest.mark.asyncio
async def test_update_content_tags_deduplicates_duplicate_names(db_session):
    """Duplicate tag names should not create duplicate content-tag rows."""
    user_id = str(uuid4())
    content_id = str(uuid4())

    content = Content(
        id=content_id,
        title="Tag service test",
        source_type="text",
        user_id=user_id,
        status="ready",
        l0_summary="ready",
    )
    db_session.add(content)
    await db_session.commit()

    service = TagService(db_session)
    result = await service.update_content_tags(
        user_id=user_id,
        content_id=content_id,
        tag_names=["ai", "ai", "infra"],
    )

    assert {tag.tag_name for tag in result} == {"ai", "infra"}

    rows = (
        await db_session.execute(
            ContentTag.__table__.select().where(ContentTag.content_id == content_id)
        )
    ).all()
    assert len(rows) == 2
