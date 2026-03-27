"""Best-effort in-memory rate limiting for expensive endpoints."""

from collections import deque
from collections.abc import Callable
from dataclasses import dataclass, field
from math import ceil
from time import monotonic

from fastapi import HTTPException


@dataclass(slots=True)
class RateLimitBucket:
    """Sliding-window timestamps for one scope/identifier pair."""

    window_seconds: float
    events: deque[float] = field(default_factory=deque)


class InMemoryRateLimiter:
    """Small async-safe sliding-window limiter.

    This is intentionally process-local. It reduces accidental abuse and
    protects costly routes in development and single-instance deployments.
    """

    def __init__(
        self,
        clock: Callable[[], float] = monotonic,
        sweep_interval: int = 256,
    ):
        self._clock = clock
        self._buckets: dict[str, RateLimitBucket] = {}
        self._sweep_interval = max(1, sweep_interval)
        self._checks_since_sweep = 0

    async def check(
        self,
        *,
        scope: str,
        identifier: str,
        limit: int,
        window_seconds: float,
        detail: str,
    ) -> None:
        if limit <= 0 or window_seconds <= 0:
            return

        now = self._clock()
        key = f"{scope}:{identifier}"
        bucket = self._buckets.get(key)
        if bucket is None:
            bucket = RateLimitBucket(window_seconds=window_seconds)
            self._buckets[key] = bucket
        else:
            bucket.window_seconds = window_seconds

        self._prune_bucket(bucket, now)

        if len(bucket.events) >= limit:
            retry_after = max(
                1,
                ceil(bucket.window_seconds - (now - bucket.events[0])),
            )
            raise HTTPException(
                status_code=429,
                detail=detail,
                headers={"Retry-After": str(retry_after)},
            )

        bucket.events.append(now)
        self._checks_since_sweep += 1
        if self._checks_since_sweep >= self._sweep_interval:
            self._sweep_stale_buckets(now)
            self._checks_since_sweep = 0

    def _prune_bucket(self, bucket: RateLimitBucket, now: float) -> None:
        cutoff = now - bucket.window_seconds
        while bucket.events and bucket.events[0] <= cutoff:
            bucket.events.popleft()

    def _sweep_stale_buckets(self, now: float) -> None:
        for key in list(self._buckets.keys()):
            bucket = self._buckets.get(key)
            if bucket is None:
                continue
            self._prune_bucket(bucket, now)
            if not bucket.events:
                self._buckets.pop(key, None)


_limiter: InMemoryRateLimiter | None = None


def get_rate_limiter() -> InMemoryRateLimiter:
    global _limiter
    if _limiter is None:
        _limiter = InMemoryRateLimiter()
    return _limiter
