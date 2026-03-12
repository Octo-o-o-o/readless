"""Tests for content router endpoints.

These tests verify the content API returns tags from content_tags table via JOIN.
"""

import asyncio
from datetime import UTC, datetime, timedelta
from unittest.mock import patch
from uuid import uuid4

import pytest

TEST_USER_ID = str(uuid4())


@pytest.mark.asyncio
async def test_get_content_returns_tags_from_join(db_session):
    """Test that GET /api/v1/content/{id} returns tags from content_tags table."""
    from app.models.content import Content
    from app.models.content_tag import ContentTag
    from app.models.user_tag import UserTag
    from app.routers.content import _get_content_tags

    # Create content
    content_id = str(uuid4())
    content = Content(
        id=content_id,
        title="Test Article",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Test summary",
    )
    db_session.add(content)

    # Create tags
    tag1 = UserTag(user_id=TEST_USER_ID, tag_name="技术")
    tag2 = UserTag(user_id=TEST_USER_ID, tag_name="学习")
    db_session.add_all([tag1, tag2])
    await db_session.flush()

    # Create content-tag relationships
    ct1 = ContentTag(content_id=content_id, tag_id=tag1.id, user_id=TEST_USER_ID)
    ct2 = ContentTag(content_id=content_id, tag_id=tag2.id, user_id=TEST_USER_ID)
    db_session.add_all([ct1, ct2])
    await db_session.commit()

    # Get tags using helper function
    tags = await _get_content_tags(content_id, db_session)

    assert len(tags) == 2
    assert "技术" in tags
    assert "学习" in tags


@pytest.mark.asyncio
async def test_get_content_tags_excludes_soft_deleted(db_session):
    """Test that _get_content_tags excludes soft-deleted tags."""
    from datetime import datetime

    from app.models.content import Content
    from app.models.content_tag import ContentTag
    from app.models.user_tag import UserTag
    from app.routers.content import _get_content_tags

    # Create content
    content_id = str(uuid4())
    content = Content(
        id=content_id,
        title="Test Article",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Test summary",
    )
    db_session.add(content)

    # Create active tag
    tag1 = UserTag(user_id=TEST_USER_ID, tag_name="active")
    # Create soft-deleted tag
    tag2 = UserTag(
        user_id=TEST_USER_ID,
        tag_name="deleted",
        deleted_at=datetime.now(UTC)
    )
    db_session.add_all([tag1, tag2])
    await db_session.flush()

    # Create content-tag relationships for both
    ct1 = ContentTag(content_id=content_id, tag_id=tag1.id, user_id=TEST_USER_ID)
    ct2 = ContentTag(content_id=content_id, tag_id=tag2.id, user_id=TEST_USER_ID)
    db_session.add_all([ct1, ct2])
    await db_session.commit()

    # Get tags - should only return active tag
    tags = await _get_content_tags(content_id, db_session)

    assert len(tags) == 1
    assert "active" in tags
    assert "deleted" not in tags


@pytest.mark.asyncio
async def test_get_content_tags_returns_empty_list_when_no_tags(db_session):
    """Test that _get_content_tags returns empty list when content has no tags."""
    from app.models.content import Content
    from app.routers.content import _get_content_tags

    # Create content without tags
    content_id = str(uuid4())
    content = Content(
        id=content_id,
        title="Test Article",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Test summary",
    )
    db_session.add(content)
    await db_session.commit()

    # Get tags - should return empty list
    tags = await _get_content_tags(content_id, db_session)

    assert tags == []


@pytest.mark.asyncio
async def test_list_contents_reschedules_recoverable_async_jobs(db_session):
    """List route should replay recoverable text/url jobs after a restart."""
    from app.models.content import Content
    from app.routers import content as content_router

    text_content = Content(
        id=str(uuid4()),
        title="Pending text",
        source_type="text",
        full_text="Recover this text import",
        user_id=TEST_USER_ID,
        status="pending",
        l0_summary=None,
    )
    url_content = Content(
        id=str(uuid4()),
        title="Processing URL",
        source_type="url",
        source_url="https://example.com/article",
        user_id=TEST_USER_ID,
        status="processing",
        l0_summary=None,
    )
    image_content = Content(
        id=str(uuid4()),
        title="Pending image",
        source_type="image",
        user_id=TEST_USER_ID,
        status="pending",
        l0_summary=None,
    )
    db_session.add_all([text_content, url_content, image_content])
    await db_session.commit()

    with patch.object(content_router, "_schedule_content_processing") as schedule:
        responses = await content_router.list_contents(
            limit=50,
            offset=0,
            skip=None,
            user_id=TEST_USER_ID,
            db=db_session,
        )

    assert len(responses) == 3
    scheduled = {
        call.kwargs["content_id"]: call.kwargs
        for call in schedule.call_args_list
    }
    assert scheduled[text_content.id]["body"] == "Recover this text import"
    assert scheduled[url_content.id]["body"] == "https://example.com/article"
    assert image_content.id not in scheduled


@pytest.mark.asyncio
async def test_get_content_reschedules_recoverable_pending_item(db_session):
    """Single-item fetch should replay a recoverable pending job."""
    from app.models.content import Content
    from app.routers import content as content_router

    content = Content(
        id=str(uuid4()),
        title="Pending text",
        source_type="text",
        full_text="Resume me",
        user_id=TEST_USER_ID,
        status="pending",
        l0_summary=None,
    )
    db_session.add(content)
    await db_session.commit()

    with patch.object(content_router, "_schedule_content_processing") as schedule:
        response = await content_router.get_content(
            content_id=content.id,
            db=db_session,
            user_id=TEST_USER_ID,
        )

    assert response.id == content.id
    schedule.assert_called_once_with(
        content_id=content.id,
        source_type="text",
        body="Resume me",
        user_id=TEST_USER_ID,
    )


@pytest.mark.asyncio
async def test_list_contents_marks_stale_unrecoverable_items_as_failed(db_session):
    """Stale unrecoverable jobs should stop hanging in processing forever."""
    from app.models.content import Content
    from app.routers import content as content_router

    content = Content(
        id=str(uuid4()),
        title="Stale image",
        source_type="image",
        user_id=TEST_USER_ID,
        status="processing",
        l0_summary=None,
        processing_started_at=datetime.now(UTC) - timedelta(hours=2),
    )
    db_session.add(content)
    await db_session.commit()

    with patch.object(
        content_router.settings,
        "content_processing_timeout_seconds",
        60,
    ):
        responses = await content_router.list_contents(
            limit=50,
            offset=0,
            skip=None,
            user_id=TEST_USER_ID,
            db=db_session,
        )

    assert len(responses) == 1
    assert responses[0].status == "failed"
    assert responses[0].l0_summary == "Import failed. Please try again."
    assert content.processing_error is not None
    assert "timed out" in content.processing_error.lower()


@pytest.mark.asyncio
async def test_list_contents_does_not_fail_when_task_is_active(db_session):
    """Active in-memory tasks should not be marked failed by timeout checks."""
    from app.models.content import Content
    from app.routers import content as content_router

    content = Content(
        id=str(uuid4()),
        title="Active processing",
        source_type="image",
        user_id=TEST_USER_ID,
        status="processing",
        l0_summary=None,
        processing_started_at=datetime.now(UTC) - timedelta(hours=2),
    )
    db_session.add(content)
    await db_session.commit()

    active_task: asyncio.Task[None] = asyncio.create_task(asyncio.sleep(0.5))
    content_router._processing_tasks[content.id] = active_task
    try:
        with patch.object(
            content_router.settings,
            "content_processing_timeout_seconds",
            60,
        ):
            responses = await content_router.list_contents(
                limit=50,
                offset=0,
                skip=None,
                user_id=TEST_USER_ID,
                db=db_session,
            )
    finally:
        active_task.cancel()
        await asyncio.gather(active_task, return_exceptions=True)
        content_router._processing_tasks.pop(content.id, None)

    assert len(responses) == 1
    assert responses[0].status == "processing"
    assert content.processing_error is None
