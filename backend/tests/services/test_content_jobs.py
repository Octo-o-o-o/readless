"""Tests for the database-backed content job service."""

from datetime import UTC, datetime
from uuid import uuid4

import pytest
from sqlalchemy import inspect, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import load_only


@pytest.mark.asyncio
async def test_recover_orphaned_jobs_requeues_running_rows(db_session):
    """Worker restart recovery should requeue previously running jobs."""
    from app.models.content import Content
    from app.models.content_job import ContentJob
    from app.services.content_jobs import ContentJobService

    content = Content(
        id=str(uuid4()),
        title="Pending",
        source_type="text",
        full_text="Recover me",
        user_id=str(uuid4()),
        status="processing",
        l0_summary=None,
    )
    job = ContentJob(
        id=str(uuid4()),
        content_id=content.id,
        source_type="text",
        body="Recover me",
        user_id=content.user_id,
        status="running",
        started_at=datetime.now(UTC),
    )
    db_session.add_all([content, job])
    await db_session.commit()

    session_factory = async_sessionmaker(
        db_session.bind,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    service = ContentJobService(session_factory=session_factory)

    recovered = await service.recover_orphaned_jobs()

    assert recovered == 1

    async with session_factory() as session:
        requeued = await session.get(ContentJob, job.id)
        assert requeued is not None
        assert requeued.status == "queued"
        assert requeued.started_at is None
        assert requeued.finished_at is None


@pytest.mark.asyncio
async def test_process_next_job_marks_job_succeeded(db_session):
    """Worker consumption should advance queued jobs to success."""
    from app.models.content import Content
    from app.models.content_job import ContentJob
    from app.services.content_jobs import ContentJobService

    content = Content(
        id=str(uuid4()),
        title="Pending",
        source_type="text",
        full_text="Hello world",
        user_id=str(uuid4()),
        status="pending",
        l0_summary=None,
    )
    job = ContentJob(
        id=str(uuid4()),
        content_id=content.id,
        source_type="text",
        body="Hello world",
        user_id=content.user_id,
        status="queued",
    )
    db_session.add_all([content, job])
    await db_session.commit()

    class StubPipeline:
        async def process_pending_content(
            self,
            *,
            content_id: str,
            source_type: str,
            body: str,
            user_id: str,
            db: AsyncSession,
        ):
            content = await db.get(Content, content_id)
            assert content is not None
            assert source_type == "text"
            assert body == "Hello world"
            assert user_id == content.user_id
            content.status = "ready"
            content.l0_summary = "Done"
            content.processing_finished_at = datetime.now(UTC)
            return content

    session_factory = async_sessionmaker(
        db_session.bind,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    service = ContentJobService(
        session_factory=session_factory,
        pipeline_factory=StubPipeline,
    )

    processed = await service.process_next_job()

    assert processed is True

    async with session_factory() as session:
        stored_content = await session.get(Content, content.id)
        stored_job = await session.get(ContentJob, job.id)

        assert stored_content is not None
        assert stored_content.status == "ready"
        assert stored_content.l0_summary == "Done"

        assert stored_job is not None
        assert stored_job.status == "succeeded"
        assert stored_job.attempts == 1
        assert stored_job.started_at is not None
        assert stored_job.finished_at is not None


@pytest.mark.asyncio
async def test_ensure_content_job_loads_deferred_full_text_only_when_needed(
    db_session,
):
    """Deferred rows should still recover text imports without full-row loads."""
    from app.models.content import Content
    from app.services.content_jobs import ContentJobService

    content = Content(
        id=str(uuid4()),
        title="Deferred pending",
        source_type="text",
        full_text="Deferred body",
        user_id=str(uuid4()),
        status="pending",
        l0_summary=None,
    )
    db_session.add(content)
    await db_session.commit()

    session_factory = async_sessionmaker(
        db_session.bind,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    service = ContentJobService(session_factory=session_factory)

    async with session_factory() as session:
        result = await session.execute(
            select(Content)
            .options(
                load_only(
                    Content.id,
                    Content.source_type,
                    Content.source_url,
                    Content.status,
                    Content.created_at,
                    Content.user_id,
                )
            )
            .where(Content.id == content.id)
        )
        deferred_content = result.scalar_one()

        assert "full_text" in inspect(deferred_content).unloaded

        job, created = await service.ensure_content_job(
            deferred_content,
            db=session,
        )
        await session.commit()

        assert created is True
        assert job is not None
        assert job.body == "Deferred body"
