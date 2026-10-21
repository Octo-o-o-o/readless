"""Tests for content router endpoints.

These tests verify the content API returns tags from content_tags table via JOIN.
"""

from datetime import UTC, datetime, timedelta
from unittest.mock import patch
from uuid import uuid4

import pytest
from sqlalchemy import select

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
    from app.models.content_job import ContentJob
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

    responses = await content_router.list_contents(
        limit=50,
        offset=0,
        skip=None,
        user_id=TEST_USER_ID,
        db=db_session,
    )
    await db_session.commit()

    assert len(responses) == 3
    assert all(not hasattr(response, "full_text") for response in responses)
    jobs = (await db_session.execute(select(ContentJob))).scalars().all()
    queued_by_content = {job.content_id: job for job in jobs}
    assert queued_by_content[text_content.id].body == "Recover this text import"
    assert queued_by_content[url_content.id].body == "https://example.com/article"
    assert image_content.id not in queued_by_content


@pytest.mark.asyncio
async def test_get_content_reschedules_recoverable_pending_item(db_session):
    """Single-item fetch should replay a recoverable pending job."""
    from app.models.content import Content
    from app.models.content_job import ContentJob
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

    response = await content_router.get_content(
        content_id=content.id,
        db=db_session,
        user_id=TEST_USER_ID,
    )
    await db_session.commit()

    assert response.id == content.id
    assert response.full_text == "Resume me"
    job = (
        await db_session.execute(
            select(ContentJob).where(ContentJob.content_id == content.id)
        )
    ).scalar_one()
    assert job.source_type == "text"
    assert job.body == "Resume me"


@pytest.mark.asyncio
async def test_list_content_statuses_returns_lightweight_snapshots(db_session):
    """Status polling route should avoid returning heavyweight content payloads."""
    from app.models.content import Content
    from app.routers import content as content_router

    pending = Content(
        id=str(uuid4()),
        title="Pending text",
        source_type="text",
        full_text="Large text that should stay out of status polling",
        user_id=TEST_USER_ID,
        status="processing",
        l0_summary="Working on it",
    )
    ready = Content(
        id=str(uuid4()),
        title="Ready text",
        source_type="text",
        full_text="Ready full text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Done",
    )
    db_session.add_all([pending, ready])
    await db_session.commit()

    responses = await content_router.list_content_statuses(
        ids=[ready.id, pending.id],
        user_id=TEST_USER_ID,
        db=db_session,
    )

    assert [response.id for response in responses] == [ready.id, pending.id]
    assert responses[0].status == "ready"
    assert responses[0].l0_summary == "Done"
    assert not hasattr(responses[0], "full_text")


@pytest.mark.asyncio
async def test_get_content_assigns_stable_outline_ids_for_legacy_rows(db_session):
    """Legacy outlines without IDs should still return deterministic IDs."""
    from app.models.content import Content
    from app.routers import content as content_router

    content = Content(
        id=str(uuid4()),
        title="Legacy outline",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Ready",
        l1_outline=[
            {"point": "First point", "anchors": ["¶1"]},
            {"point": "Second point", "anchors": ["¶2", "¶3"]},
        ],
    )
    db_session.add(content)
    await db_session.commit()

    first = await content_router.get_content(
        content_id=content.id,
        db=db_session,
        user_id=TEST_USER_ID,
    )
    second = await content_router.get_content(
        content_id=content.id,
        db=db_session,
        user_id=TEST_USER_ID,
    )

    first_ids = [item["id"] for item in first.l1_outline]
    second_ids = [item["id"] for item in second.l1_outline]

    assert first_ids == second_ids
    assert all(first_ids)


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
    """Recent queued jobs should not be marked failed by timeout checks."""
    from app.models.content import Content
    from app.models.content_job import ContentJob
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
    job = ContentJob(
        id=str(uuid4()),
        content_id=content.id,
        source_type="image",
        body="base64image",
        user_id=TEST_USER_ID,
        status="queued",
        scheduled_at=datetime.now(UTC),
    )
    db_session.add(job)
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
    assert responses[0].status == "processing"
    assert content.processing_error is None
