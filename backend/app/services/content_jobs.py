"""Content import job orchestration for single-process background execution."""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta

from app.config import settings
from app.database import get_session_factory
from app.models.content import Content
from app.services.pipeline import (
    FAILED_IMPORT_SUMMARY,
    ProcessingPipeline,
    truncate_processing_error,
)

JobProcessor = Callable[
    ...,
    Awaitable[None],
]


class ContentJobService:
    """Coordinates background content processing tasks and recovery policy."""

    def __init__(self) -> None:
        self.processing_tasks: dict[str, asyncio.Task[None]] = {}
        self._processing_semaphore: asyncio.Semaphore | None = None

    def _get_processing_semaphore(self) -> asyncio.Semaphore:
        if self._processing_semaphore is None:
            self._processing_semaphore = asyncio.Semaphore(
                settings.content_processing_concurrency
            )
        return self._processing_semaphore

    def schedule_processing(
        self,
        *,
        content_id: str,
        source_type: str,
        body: str,
        user_id: str,
        processor: JobProcessor | None = None,
    ) -> None:
        existing_task = self.processing_tasks.get(content_id)
        if existing_task is not None and not existing_task.done():
            return

        process_func = processor or self.process_content_in_background
        task = asyncio.create_task(
            process_func(
                content_id=content_id,
                source_type=source_type,
                body=body,
                user_id=user_id,
            )
        )
        self.processing_tasks[content_id] = task

        def _cleanup(done_task: asyncio.Task[None]) -> None:
            if self.processing_tasks.get(content_id) is done_task:
                self.processing_tasks.pop(content_id, None)

        task.add_done_callback(_cleanup)

    async def process_content_in_background(
        self,
        *,
        content_id: str,
        source_type: str,
        body: str,
        user_id: str,
    ) -> None:
        async with self._get_processing_semaphore():
            session_factory = get_session_factory()
            async with session_factory() as db:
                await ProcessingPipeline().process_pending_content(
                    content_id=content_id,
                    source_type=source_type,
                    body=body,
                    user_id=user_id,
                    db=db,
                )

    def schedule_content_recovery(self, content: Content) -> None:
        if content.status not in {"pending", "processing"}:
            return

        if body := self.recoverable_content_body(content):
            self.schedule_processing(
                content_id=content.id,
                source_type=content.source_type,
                body=body,
                user_id=content.user_id,
            )

    def recoverable_content_body(self, content: Content) -> str | None:
        if content.source_type == "url":
            return content.source_url

        if content.source_type == "text":
            return content.full_text

        return None

    def _get_timeout_baseline(self, content: Content) -> datetime | None:
        if content.status == "processing":
            return content.processing_started_at or content.created_at

        if content.status == "pending":
            return content.created_at

        return None

    def mark_stale_content_as_failed(self, content: Content) -> bool:
        if content.status not in {"pending", "processing"}:
            return False

        active_task = self.processing_tasks.get(content.id)
        if active_task is not None and not active_task.done():
            return False

        seconds = settings.content_processing_timeout_seconds
        if seconds <= 0:
            return False

        baseline = self._get_timeout_baseline(content)
        if baseline is None:
            return False
        if baseline.tzinfo is None:
            baseline = baseline.replace(tzinfo=UTC)

        timeout_at = datetime.now(UTC) - timedelta(seconds=seconds)
        if baseline >= timeout_at:
            return False

        content.status = "failed"
        content.l0_summary = FAILED_IMPORT_SUMMARY
        content.l1_outline = []
        content.keywords = None
        content.processing_finished_at = datetime.now(UTC)
        content.processing_error = truncate_processing_error(
            f"Processing timed out after {seconds} seconds"
        )
        return True


_content_job_service: ContentJobService | None = None


def get_content_job_service() -> ContentJobService:
    global _content_job_service
    if _content_job_service is None:
        _content_job_service = ContentJobService()
    return _content_job_service
