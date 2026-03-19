"""REST API routes for agentic search."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.services.search_agent import SearchAgent

router = APIRouter(prefix="/api/v1/search", tags=["search"])

# Lazy-initialized singleton (same pattern as content router)
_agent: SearchAgent | None = None


def _get_agent() -> SearchAgent:
    global _agent
    if _agent is None:
        _agent = SearchAgent()
    return _agent


class SearchRequest(BaseModel):
    query: str


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
    agent = _get_agent()
    return await agent.retrieve(req.query, user_id, db)


@router.post("/")
async def search(
    req: SearchRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Search the user's saved content using the AI search agent."""
    agent = _get_agent()
    return await agent.search(req.query, user_id, db)
