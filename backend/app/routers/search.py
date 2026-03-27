"""REST API routes for agentic search."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel, model_validator
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.config import settings
from app.database import get_db
from app.services.rate_limiter import InMemoryRateLimiter, get_rate_limiter
from app.services.search_agent import SearchAgent

router = APIRouter(prefix="/api/v1/search", tags=["search"])

# Lazy-initialized singleton (same pattern as content router)
_agent: SearchAgent | None = None
_rate_limiter: InMemoryRateLimiter | None = None


def _get_agent() -> SearchAgent:
    global _agent
    if _agent is None:
        _agent = SearchAgent()
    return _agent


def _get_router_rate_limiter() -> InMemoryRateLimiter:
    global _rate_limiter
    if _rate_limiter is None:
        _rate_limiter = get_rate_limiter()
    return _rate_limiter


class SearchRequest(BaseModel):
    query: str

    @model_validator(mode="after")
    def normalize_query(self) -> "SearchRequest":
        normalized = " ".join(self.query.split())
        if not normalized:
            raise ValueError("Query cannot be empty.")
        if len(normalized) > settings.search_max_query_chars:
            raise ValueError(
                "Query is too long. Please shorten your search and try again."
            )
        self.query = normalized
        return self


class SearchSourceResponse(BaseModel):
    id: str
    title: str
    l0_summary: str | None = None
    source_url: str | None = None


@router.post("/retrieve", response_model=list[SearchSourceResponse])
async def retrieve(
    req: SearchRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Return lightweight search candidates for interactive suggestion UIs."""
    await _get_router_rate_limiter().check(
        scope="search:retrieve",
        identifier=user_id,
        limit=settings.search_retrieve_rate_limit,
        window_seconds=settings.search_retrieve_rate_window_seconds,
        detail="Search suggestions are rate limited. Please slow down.",
    )
    agent = _get_agent()
    return await agent.retrieve(req.query, user_id, db)


@router.post("/")
async def search(
    req: SearchRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Search the user's saved content using the AI search agent."""
    await _get_router_rate_limiter().check(
        scope="search:answer",
        identifier=user_id,
        limit=settings.search_answer_rate_limit,
        window_seconds=settings.search_answer_rate_window_seconds,
        detail="AI search is rate limited. Please try again in a moment.",
    )
    agent = _get_agent()
    return await agent.search(req.query, user_id, db)
