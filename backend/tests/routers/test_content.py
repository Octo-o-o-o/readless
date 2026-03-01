"""Tests for content router endpoints.

These tests verify the content API returns tags from content_tags table via JOIN.
"""

import pytest
from uuid import uuid4


@pytest.mark.asyncio
async def test_get_content_returns_tags_from_join(db_session):
    """Test that GET /api/v1/content/{id} returns tags from content_tags table."""
    from app.models.content import Content
    from app.models.user_tag import UserTag
    from app.models.content_tag import ContentTag
    from app.routers.content import _get_content_tags

    # Create content
    content_id = str(uuid4())
    content = Content(
        id=content_id,
        title="Test Article",
        source_type="text",
        user_id="test_user",
        status="ready",
        l0_summary="Test summary",
    )
    db_session.add(content)

    # Create tags
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习")
    db_session.add_all([tag1, tag2])
    await db_session.flush()

    # Create content-tag relationships
    ct1 = ContentTag(content_id=content_id, tag_id=tag1.id, user_id="test_user")
    ct2 = ContentTag(content_id=content_id, tag_id=tag2.id, user_id="test_user")
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
    from app.models.content import Content
    from app.models.user_tag import UserTag
    from app.models.content_tag import ContentTag
    from app.routers.content import _get_content_tags
    from datetime import datetime, timezone

    # Create content
    content_id = str(uuid4())
    content = Content(
        id=content_id,
        title="Test Article",
        source_type="text",
        user_id="test_user",
        status="ready",
        l0_summary="Test summary",
    )
    db_session.add(content)

    # Create active tag
    tag1 = UserTag(user_id="test_user", tag_name="active")
    # Create soft-deleted tag
    tag2 = UserTag(
        user_id="test_user",
        tag_name="deleted",
        deleted_at=datetime.now(timezone.utc)
    )
    db_session.add_all([tag1, tag2])
    await db_session.flush()

    # Create content-tag relationships for both
    ct1 = ContentTag(content_id=content_id, tag_id=tag1.id, user_id="test_user")
    ct2 = ContentTag(content_id=content_id, tag_id=tag2.id, user_id="test_user")
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
        user_id="test_user",
        status="ready",
        l0_summary="Test summary",
    )
    db_session.add(content)
    await db_session.commit()

    # Get tags - should return empty list
    tags = await _get_content_tags(content_id, db_session)

    assert tags == []
