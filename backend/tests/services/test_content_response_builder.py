"""Tests for content response assembly helpers."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from app.models.content import Content
from app.models.content_tag import ContentTag
from app.models.user_tag import UserTag
from app.services.content_response import ContentResponseBuilder

TEST_USER_ID = str(uuid4())


@pytest.mark.asyncio
async def test_get_content_tags_returns_empty_list_when_query_fails():
    builder = ContentResponseBuilder()

    class FailingDB:
        async def execute(self, _stmt):
            raise RuntimeError("database unavailable")

    assert await builder.get_content_tags("content-1", FailingDB()) == []


def test_build_detail_with_tags_stabilizes_legacy_outline_ids():
    builder = ContentResponseBuilder()
    content = Content(
        id=str(uuid4()),
        title="Legacy outline",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Summary",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
        l1_outline=[
            {"point": "First", "anchors": ["¶1"]},
            {"point": "Second", "anchors": ["¶2", "¶3"]},
        ],
        full_text="Full text",
    )

    response = builder.build_detail_with_tags(content, ["reading"])

    assert response.tags == ["reading"]
    assert response.full_text == "Full text"
    assert len(response.l1_outline) == 2
    assert all(point["id"] for point in response.l1_outline)


@pytest.mark.asyncio
async def test_build_list_items_batches_tags_for_multiple_contents(db_session):
    builder = ContentResponseBuilder()

    first = Content(
        id=str(uuid4()),
        title="First",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="First summary",
    )
    second = Content(
        id=str(uuid4()),
        title="Second",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Second summary",
    )
    tag = UserTag(user_id=TEST_USER_ID, tag_name="ai")
    db_session.add_all([first, second, tag])
    await db_session.flush()
    db_session.add(ContentTag(content_id=first.id, tag_id=tag.id, user_id=TEST_USER_ID))
    await db_session.commit()

    responses = await builder.build_list_items([first, second], db_session)

    assert len(responses) == 2
    assert responses[0].tags == ["ai"]
    assert responses[1].tags == []


@pytest.mark.asyncio
async def test_build_list_items_returns_empty_list_for_empty_input(db_session):
    builder = ContentResponseBuilder()

    assert await builder.build_list_items([], db_session) == []
