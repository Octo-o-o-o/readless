"""Dedicated content import worker process."""

from __future__ import annotations

import asyncio
import logging
import signal

from app.config import settings
from app.services.content_jobs import ContentJobService, get_content_job_service

logger = logging.getLogger(__name__)


class ContentWorker:
    """Polls the database queue and processes content jobs."""

    def __init__(
        self,
        *,
        job_service: ContentJobService | None = None,
        concurrency: int | None = None,
        poll_interval_seconds: float | None = None,
    ) -> None:
        self.job_service = job_service or get_content_job_service()
        self.concurrency = max(
            1,
            concurrency or settings.content_processing_concurrency,
        )
        self.poll_interval_seconds = max(
            0.1,
            poll_interval_seconds or settings.content_job_poll_interval_seconds,
        )
        self._stop_event = asyncio.Event()

    async def run(self) -> None:
        recovered = await self.job_service.recover_orphaned_jobs()
        if recovered:
            logger.warning("Recovered %d orphaned content jobs", recovered)

        workers = [
            asyncio.create_task(self._run_slot(index + 1))
            for index in range(self.concurrency)
        ]

        try:
            await self._stop_event.wait()
        finally:
            for worker in workers:
                worker.cancel()
            await asyncio.gather(*workers, return_exceptions=True)

    def stop(self) -> None:
        self._stop_event.set()

    async def _run_slot(self, slot: int) -> None:
        while not self._stop_event.is_set():
            processed = await self.job_service.process_next_job()
            if processed:
                continue

            logger.debug("Worker slot %d idle", slot)
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=self.poll_interval_seconds,
                )
            except TimeoutError:
                continue


async def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    )

    worker = ContentWorker()
    loop = asyncio.get_running_loop()
    for signum in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(signum, worker.stop)
        except NotImplementedError:  # pragma: no cover - platform-specific
            pass

    logger.info(
        "Starting content worker with concurrency=%d poll_interval=%.1fs",
        worker.concurrency,
        worker.poll_interval_seconds,
    )
    await worker.run()
    logger.info("Content worker stopped")


if __name__ == "__main__":
    asyncio.run(main())
