"""Behavior tests for podcast router endpoints."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import text

from app.models.content import Content
from app.models.podcast import Podcast

TEST_USER_ID = str(uuid4())


async def _ensure_podcast_table(db_session) -> None:
    await db_session.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS podcasts (
                id VARCHAR(36) PRIMARY KEY,
                content_id VARCHAR(36) NOT NULL,
                audio_url TEXT,
                script TEXT,
                chapters TEXT,
                status VARCHAR(20) NOT NULL DEFAULT 'generating',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (content_id) REFERENCES contents (id) ON DELETE CASCADE
            )
            """
        )
    )
    await db_session.commit()


@pytest.mark.asyncio
async def test_generate_podcast_rejects_missing_or_foreign_content(db_session):
    from app.routers.podcast import generate_podcast

    await _ensure_podcast_table(db_session)

    with pytest.raises(HTTPException) as exc_info:
        await generate_podcast(
            content_id="missing",
            db=db_session,
            user_id=TEST_USER_ID,
        )

    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "Content not found"


@pytest.mark.asyncio
async def test_generate_podcast_rejects_duplicate_ready_podcast(db_session):
    from app.routers.podcast import generate_podcast

    await _ensure_podcast_table(db_session)

    content = Content(
        id=str(uuid4()),
        title="Podcast source",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Summary",
    )
    podcast = Podcast(
        id=str(uuid4()),
        content_id=content.id,
        status="ready",
        audio_url="https://cdn.example.com/audio.mp3",
    )
    db_session.add_all([content, podcast])
    await db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        await generate_podcast(
            content_id=content.id,
            db=db_session,
            user_id=TEST_USER_ID,
        )

    assert exc_info.value.status_code == 409
    assert exc_info.value.detail == "Podcast already exists"


@pytest.mark.asyncio
async def test_generate_podcast_calls_service_and_returns_summary_payload(db_session):
    from app.routers.podcast import generate_podcast

    await _ensure_podcast_table(db_session)

    content = Content(
        id=str(uuid4()),
        title="Podcast source",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Summary",
    )
    db_session.add(content)
    await db_session.commit()

    class FakeService:
        async def generate(self, content_arg, db_arg):
            assert content_arg.id == content.id
            assert db_arg is db_session
            return SimpleNamespace(id="pod-123", status="ready")

    with patch("app.routers.podcast._get_service", return_value=FakeService()):
        response = await generate_podcast(
            content_id=content.id,
            db=db_session,
            user_id=TEST_USER_ID,
        )

    assert response == {"id": "pod-123", "status": "ready"}


@pytest.mark.asyncio
async def test_get_podcast_returns_latest_record(db_session):
    from app.routers.podcast import get_podcast

    await _ensure_podcast_table(db_session)

    content = Content(
        id=str(uuid4()),
        title="Podcast source",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Summary",
    )
    older = Podcast(
        id="older",
        content_id=content.id,
        status="failed",
        audio_url=None,
        chapters=[],
    )
    newer = Podcast(
        id="newer",
        content_id=content.id,
        status="ready",
        audio_url="https://cdn.example.com/new.mp3",
        chapters=[{"title": "Intro", "outline_point_index": None}],
    )
    older.created_at = datetime.now(UTC) - timedelta(days=1)
    newer.created_at = datetime.now(UTC)
    db_session.add_all([content, older, newer])
    await db_session.commit()

    response = await get_podcast(
        content_id=content.id,
        db=db_session,
        user_id=TEST_USER_ID,
    )

    assert response["id"] == "newer"
    assert response["status"] == "ready"
    assert response["audio_url"] == "https://cdn.example.com/new.mp3"
    assert response["chapters"] == [{"title": "Intro", "outline_point_index": None}]


@pytest.mark.asyncio
async def test_get_podcast_returns_404_when_content_has_no_podcast(db_session):
    from app.routers.podcast import get_podcast

    await _ensure_podcast_table(db_session)

    content = Content(
        id=str(uuid4()),
        title="Podcast source",
        source_type="text",
        user_id=TEST_USER_ID,
        status="ready",
        l0_summary="Summary",
    )
    db_session.add(content)
    await db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        await get_podcast(content_id=content.id, db=db_session, user_id=TEST_USER_ID)

    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "Podcast not found"
