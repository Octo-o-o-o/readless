"""Database-backed content import queue and worker helpers."""

from __future__ import annotations

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.config import settings
from app.database import get_session_factory
from app.models.content import Content
from app.models.content_job import ContentJob
from app.services.pipeline import (
    FAILED_IMPORT_SUMMARY,
    ProcessingPipeline,
    truncate_processing_error,
)


@dataclass(slots=True)
class ClaimedContentJob:
    """Immutable snapshot of a claimed job."""

    id: str
    content_id: str
    source_type: str
    body: str
    user_id: str


class ContentJobService:
    """Coordinates database-backed content processing jobs."""

    def __init__(
        self,
        *,
        session_factory: async_sessionmaker[AsyncSession] | None = None,
        pipeline_factory: Callable[[], ProcessingPipeline] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._pipeline_factory = pipeline_factory
        self._pipeline: ProcessingPipeline | None = None

    def _get_session_factory(self) -> async_sessionmaker[AsyncSession]:
        return self._session_factory or get_session_factory()

    def _get_pipeline(self) -> ProcessingPipeline:
        if self._pipeline is None:
            if self._pipeline_factory is None:
                self._pipeline = ProcessingPipeline()
            else:
                self._pipeline = self._pipeline_factory()
        return self._pipeline

    async def enqueue_processing(
        self,
        *,
        content_id: str,
        source_type: str,
        body: str,
        user_id: str,
        db: AsyncSession,
        job: ContentJob | None = None,
    ) -> tuple[ContentJob, bool]:
        """Insert or refresh a queued job for the content item."""
        existing_job = job or await self.get_job(content_id, db)
        if existing_job is None:
            queued_job = ContentJob(
                id=str(uuid.uuid4()),
                content_id=content_id,
                source_type=source_type,
                body=body,
                user_id=user_id,
                status="queued",
                attempts=0,
                scheduled_at=datetime.now(UTC),
            )
            db.add(queued_job)
            await db.flush()
            return queued_job, True

        if (
            existing_job.status in {"queued", "running"}
            and existing_job.source_type == source_type
            and existing_job.body == body
            and existing_job.user_id == user_id
        ):
            return existing_job, False

        existing_job.source_type = source_type
        existing_job.body = body
        existing_job.user_id = user_id
        existing_job.status = "queued"
        existing_job.scheduled_at = datetime.now(UTC)
        existing_job.started_at = None
        existing_job.finished_at = None
        existing_job.last_error = None
        await db.flush()
        return existing_job, True

    async def get_job(
        self,
        content_id: str,
        db: AsyncSession,
    ) -> ContentJob | None:
        """Load the job row for a content item."""
        stmt = select(ContentJob).where(ContentJob.content_id == content_id)
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_jobs_by_content_ids(
        self,
        content_ids: list[str],
        db: AsyncSession,
    ) -> dict[str, ContentJob]:
        """Batch-load job rows for the given content items."""
        if not content_ids:
            return {}

        stmt = select(ContentJob).where(ContentJob.content_id.in_(content_ids))
        result = await db.execute(stmt)
        return {job.content_id: job for job in result.scalars().all()}

    async def ensure_content_job(
        self,
        content: Content,
        *,
        db: AsyncSession,
        job: ContentJob | None = None,
    ) -> tuple[ContentJob | None, bool]:
        """Recreate missing queue rows for recoverable legacy content."""
        if content.status not in {"pending", "processing"}:
            return job, False

        existing_job = job or await self.get_job(content.id, db)
        if existing_job is not None and existing_job.status in {"queued", "running"}:
            return existing_job, False

        body = self.recoverable_content_body(content)
        if body is None:
            return existing_job, False

        return await self.enqueue_processing(
            content_id=content.id,
            source_type=content.source_type,
            body=body,
            user_id=content.user_id,
            db=db,
            job=existing_job,
        )

    def recoverable_content_body(self, content: Content) -> str | None:
        if content.source_type == "url":
            return content.source_url

        if content.source_type == "text":
            return content.full_text

        return None

    async def recover_orphaned_jobs(self) -> int:
        """Requeue any jobs left running by a previous worker process."""
        session_factory = self._get_session_factory()
        async with session_factory() as db:
            stmt = select(ContentJob).where(ContentJob.status == "running")
            result = await db.execute(stmt)
            jobs = result.scalars().all()
            if not jobs:
                return 0

            now = datetime.now(UTC)
            for job in jobs:
                job.status = "queued"
                job.scheduled_at = now
                job.started_at = None
                job.finished_at = None
                job.last_error = truncate_processing_error(
                    "Recovered orphaned running job after worker restart"
                )

            await db.commit()
            return len(jobs)

    async def process_next_job(self) -> bool:
        """Claim and process the next queued job."""
        claimed_job = await self._claim_next_job()
        if claimed_job is None:
            return False

        try:
            await self._process_claimed_job(claimed_job)
        except Exception as exc:  # pragma: no cover - defensive safety net
            await self._fail_claimed_job(claimed_job, error=exc)
        return True

    async def _claim_next_job(self) -> ClaimedContentJob | None:
        session_factory = self._get_session_factory()
        async with session_factory() as db:
            async with db.begin():
                now = datetime.now(UTC)
                stmt = (
                    select(ContentJob)
                    .where(
                        ContentJob.status == "queued",
                        ContentJob.scheduled_at <= now,
                    )
                    .order_by(
                        ContentJob.scheduled_at.asc(),
                        ContentJob.created_at.asc(),
                    )
                    .limit(1)
                    .with_for_update(skip_locked=True)
                )
                result = await db.execute(stmt)
                job = result.scalar_one_or_none()
                if job is None:
                    return None

                job.status = "running"
                job.started_at = now
                job.finished_at = None
                job.last_error = None
                job.attempts = (job.attempts or 0) + 1
                await db.flush()
                return ClaimedContentJob(
                    id=job.id,
                    content_id=job.content_id,
                    source_type=job.source_type,
                    body=job.body,
                    user_id=job.user_id,
                )

    async def _process_claimed_job(self, job: ClaimedContentJob) -> None:
        session_factory = self._get_session_factory()
        async with session_factory() as db:
            content = await self._get_pipeline().process_pending_content(
                content_id=job.content_id,
                source_type=job.source_type,
                body=job.body,
                user_id=job.user_id,
                db=db,
            )

            queued_job = await db.get(ContentJob, job.id)
            if queued_job is None:
                await db.commit()
                return

            if content is None:
                self._mark_job_failed(
                    queued_job,
                    error="Content import target no longer exists",
                )
            elif content.status == "ready":
                self._mark_job_succeeded(queued_job)
            elif content.status == "failed":
                self._mark_job_failed(
                    queued_job,
                    error=content.processing_error,
                )
            else:
                self._mark_job_failed(
                    queued_job,
                    error="Processing did not reach a terminal state",
                )

            await db.commit()

    async def _fail_claimed_job(
        self,
        job: ClaimedContentJob,
        *,
        error: Exception | str | None,
    ) -> None:
        session_factory = self._get_session_factory()
        async with session_factory() as db:
            queued_job = await db.get(ContentJob, job.id)
            if queued_job is not None:
                self._mark_job_failed(queued_job, error=error)

            content = await db.get(Content, job.content_id)
            if content is not None and content.status in {"pending", "processing"}:
                self._mark_content_failed(content, error=error)

            await db.commit()

    def mark_stale_content_as_failed(
        self,
        content: Content,
        job: ContentJob | None = None,
    ) -> bool:
        """Fail content that has exceeded the processing timeout."""
        if content.status not in {"pending", "processing"}:
            return False

        seconds = settings.content_processing_timeout_seconds
        if seconds <= 0:
            return False

        baseline = self._get_timeout_baseline(content, job)
        if baseline is None:
            return False
        if baseline.tzinfo is None:
            baseline = baseline.replace(tzinfo=UTC)

        timeout_at = datetime.now(UTC) - timedelta(seconds=seconds)
        if baseline >= timeout_at:
            return False

        self._mark_content_failed(
            content,
            error=f"Processing timed out after {seconds} seconds",
        )
        if job is not None and job.status in {"queued", "running"}:
            self._mark_job_failed(
                job,
                error=f"Processing timed out after {seconds} seconds",
            )
        return True

    def _get_timeout_baseline(
        self,
        content: Content,
        job: ContentJob | None,
    ) -> datetime | None:
        if job is not None:
            if job.status == "running":
                return (
                    job.started_at
                    or content.processing_started_at
                    or content.created_at
                )
            if job.status == "queued":
                return job.scheduled_at or content.created_at

        if content.status == "processing":
            return content.processing_started_at or content.created_at
        if content.status == "pending":
            return content.created_at
        return None

    def _mark_job_succeeded(self, job: ContentJob) -> None:
        job.status = "succeeded"
        job.finished_at = datetime.now(UTC)
        job.last_error = None

    def _mark_job_failed(
        self,
        job: ContentJob,
        *,
        error: Exception | str | None,
    ) -> None:
        if isinstance(error, Exception):
            detail = str(error)
            prefix = type(error).__name__
            message = f"{prefix}: {detail}" if detail else prefix
        else:
            message = error

        job.status = "failed"
        job.finished_at = datetime.now(UTC)
        job.last_error = truncate_processing_error(message)

    def _mark_content_failed(
        self,
        content: Content,
        *,
        error: Exception | str | None,
    ) -> None:
        if isinstance(error, Exception):
            detail = str(error)
            prefix = type(error).__name__
            message = f"{prefix}: {detail}" if detail else prefix
        else:
            message = error

        content.status = "failed"
        content.l0_summary = FAILED_IMPORT_SUMMARY
        content.l1_outline = []
        content.keywords = None
        content.processing_finished_at = datetime.now(UTC)
        content.processing_error = truncate_processing_error(message)


_content_job_service: ContentJobService | None = None


def get_content_job_service() -> ContentJobService:
    global _content_job_service
    if _content_job_service is None:
        _content_job_service = ContentJobService()
    return _content_job_service
