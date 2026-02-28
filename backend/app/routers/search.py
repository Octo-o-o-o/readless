"""REST API routes for agentic search."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

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


# TODO: Replace with Clerk auth middleware
def get_current_user_id() -> str:
    return "dev-user"


class SearchRequest(BaseModel):
    query: str


@router.post("/")
async def search(
    req: SearchRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    """Search the user's saved content using the AI search agent."""
    agent = _get_agent()
    return await agent.search(req.query, user_id, db)
