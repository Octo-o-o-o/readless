"""Tests for the dedicated content worker."""

from __future__ import annotations

import asyncio
from collections import deque
from types import SimpleNamespace
from unittest.mock import patch

import pytest


class StubJobService:
    def __init__(self, responses: list[bool] | None = None):
        self.calls: list[str] = []
        self.responses = deque(responses or [False])
        self.process_started = asyncio.Event()

    async def recover_orphaned_jobs(self) -> int:
        self.calls.append("recover")
        return 1

    async def clear_finished_job_bodies(self) -> int:
        self.calls.append("clear")
        return 2

    async def purge_finished_jobs(self) -> int:
        self.calls.append("purge")
        return 3

    async def process_next_job(self) -> bool:
        self.calls.append("process")
        self.process_started.set()
        if len(self.responses) == 1:
            return self.responses[0]
        return self.responses.popleft()


@pytest.mark.asyncio
async def test_worker_run_executes_startup_maintenance_and_stops_cleanly():
    from app.worker import ContentWorker

    job_service = StubJobService()
    worker = ContentWorker(
        job_service=job_service,
        concurrency=1,
        poll_interval_seconds=0.01,
    )

    run_task = asyncio.create_task(worker.run())
    await asyncio.wait_for(job_service.process_started.wait(), timeout=1)
    worker.stop()
    await asyncio.wait_for(run_task, timeout=1)

    assert job_service.calls[:4] == ["recover", "clear", "purge", "process"]


@pytest.mark.asyncio
async def test_main_registers_signal_handlers_and_runs_worker():
    import app.worker as worker_mod

    signal_handlers: list[object] = []
    fake_worker = SimpleNamespace(
        concurrency=2,
        poll_interval_seconds=0.5,
        stop=lambda: None,
    )

    async def fake_run():
        fake_worker.ran = True

    fake_worker.ran = False
    fake_worker.run = fake_run

    fake_loop = SimpleNamespace(
        add_signal_handler=lambda signum, handler: signal_handlers.append(signum)
    )

    with patch.object(worker_mod.logging, "basicConfig"), patch.object(
        worker_mod.asyncio,
        "get_running_loop",
        return_value=fake_loop,
    ), patch.object(worker_mod, "ContentWorker", return_value=fake_worker):
        await worker_mod.main()

    assert fake_worker.ran is True
    assert len(signal_handlers) == 2
