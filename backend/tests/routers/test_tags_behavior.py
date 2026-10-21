"""Behavior tests for tag router endpoints."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.models.content import Content
from app.models.content_tag import ContentTag
from app.models.user_tag import UserTag
from app.schemas.tag import ContentTagsUpdateRequest, TagCreateRequest

TEST_USER_ID = str(uuid4())


@pytest.mark.asyncio
async def test_list_user_tags_returns_active_tags_with_counts(db_session):
    from app.routers.tags import list_user_tags

    content = Content(
        id=str(uuid4()),
        title="Tagged content",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Summary",
    )
    active = UserTag(user_id=TEST_USER_ID, tag_name="active")
    deleted = UserTag(
        user_id=TEST_USER_ID,
        tag_name="deleted",
        deleted_at=datetime.now(UTC),
    )
    db_session.add_all([content, active, deleted])
    await db_session.flush()
    db_session.add_all(
        [
            ContentTag(content_id=content.id, tag_id=active.id, user_id=TEST_USER_ID),
            ContentTag(content_id=content.id, tag_id=deleted.id, user_id=TEST_USER_ID),
        ]
    )
    await db_session.commit()

    response = await list_user_tags(db=db_session, user_id=TEST_USER_ID)

    assert [tag.tag_name for tag in response] == ["active"]
    assert response[0].content_count == 1


@pytest.mark.asyncio
async def test_create_tag_maps_duplicate_error_to_400(db_session):
    from app.routers.tags import create_tag

    db_session.add(UserTag(user_id=TEST_USER_ID, tag_name="duplicate"))
    await db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        await create_tag(
            req=TagCreateRequest(tag_name="duplicate"),
            db=db_session,
            user_id=TEST_USER_ID,
        )

    assert exc_info.value.status_code == 400
    assert "already exists" in exc_info.value.detail


@pytest.mark.asyncio
async def test_delete_tag_maps_missing_error_to_404(db_session):
    from app.routers.tags import delete_tag

    with pytest.raises(HTTPException) as exc_info:
        await delete_tag(tag_id=999, db=db_session, user_id=TEST_USER_ID)

    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "Tag not found"


@pytest.mark.asyncio
async def test_get_content_tags_maps_missing_content_to_404(db_session):
    from app.routers.tags import get_content_tags

    with pytest.raises(HTTPException) as exc_info:
        await get_content_tags(
            content_id="missing-content",
            db=db_session,
            user_id=TEST_USER_ID,
        )

    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "Content not found"


@pytest.mark.asyncio
async def test_update_content_tags_replaces_links_and_auto_creates_tags(db_session):
    from app.routers.tags import update_content_tags

    content = Content(
        id=str(uuid4()),
        title="Replace tags",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Summary",
    )
    existing = UserTag(user_id=TEST_USER_ID, tag_name="existing")
    stale = UserTag(user_id=TEST_USER_ID, tag_name="stale")
    db_session.add_all([content, existing, stale])
    await db_session.flush()
    db_session.add(
        ContentTag(
            content_id=content.id,
            tag_id=stale.id,
            user_id=TEST_USER_ID,
        )
    )
    await db_session.commit()

    response = await update_content_tags(
        content_id=content.id,
        req=ContentTagsUpdateRequest(tag_names=["existing", "new-tag", "existing"]),
        db=db_session,
        user_id=TEST_USER_ID,
    )

    assert {tag.tag_name for tag in response} == {"existing", "new-tag"}
    stored_links = (
        await db_session.execute(
            select(ContentTag).where(ContentTag.content_id == content.id)
        )
    ).scalars().all()
    assert len(stored_links) == 2

    stored_tags = (await db_session.execute(select(UserTag))).scalars().all()
    assert {tag.tag_name for tag in stored_tags} >= {"existing", "new-tag", "stale"}


@pytest.mark.asyncio
async def test_get_contents_by_tag_returns_content_list_items(db_session):
    from app.routers.tags import get_contents_by_tag

    tag = UserTag(user_id=TEST_USER_ID, tag_name="reading")
    content = Content(
        id=str(uuid4()),
        title="Tagged article",
        source_type="url",
        source_url="https://example.com/article",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Summary",
    )
    db_session.add_all([tag, content])
    await db_session.flush()
    db_session.add(
        ContentTag(
            content_id=content.id,
            tag_id=tag.id,
            user_id=TEST_USER_ID,
        )
    )
    await db_session.commit()

    response = await get_contents_by_tag(
        tag_id=tag.id,
        db=db_session,
        user_id=TEST_USER_ID,
    )

    assert len(response) == 1
    assert response[0].id == content.id
    assert response[0].title == "Tagged article"
    assert response[0].tags == ["reading"]
