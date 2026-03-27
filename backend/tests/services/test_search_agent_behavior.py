"""Behavioral tests for search agent helpers and fallbacks."""

from __future__ import annotations

from collections import deque
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest

from app.services.search_agent import SearchAgent


class FakeResult:
    def __init__(self, rows):
        self._rows = rows

    def fetchall(self):
        return self._rows


class FakeDB:
    def __init__(self, *responses):
        self._responses = deque(responses)
        self.calls: list[tuple[str, dict]] = []

    async def execute(self, statement, params):
        self.calls.append((str(statement), params))
        return FakeResult(self._responses.popleft())


def _candidate(idx: int, title: str = "Title") -> SimpleNamespace:
    return SimpleNamespace(
        id=f"content-{idx}",
        title=f"{title} {idx}",
        l0_summary=f"Summary {idx}",
        l1_outline=[{"point": f"Point {idx}"}],
        source_url=f"https://example.com/{idx}",
    )


def test_basic_intent_splits_cjk_queries_into_terms():
    agent = SearchAgent()

    intent = agent._basic_intent("深度学习 transformer 2026")

    assert intent["search_terms"] == ["深度学习", "transformer", "2026"]
    assert intent["time_filter"] is None


@pytest.mark.asyncio
async def test_parse_intent_falls_back_to_basic_intent_on_invalid_json():
    agent = SearchAgent()
    agent._chat_completion = AsyncMock(return_value="not-json")

    intent = await agent._parse_intent("recent AI papers")

    assert intent == {"search_terms": ["recent", "AI", "papers"], "time_filter": None}


@pytest.mark.asyncio
async def test_search_index_uses_cjk_ilike_fallback_when_fts_misses():
    agent = SearchAgent()
    db = FakeDB([], [_candidate(1, title="中文")])

    rows = await agent._search_index(
        {"search_terms": ["深度学习"], "time_filter": None},
        "user-1",
        db,
    )

    assert len(rows) == 1
    assert "ILIKE" in db.calls[1][0]
    assert db.calls[1][1]["term_0"] == "%深度学习%"


@pytest.mark.asyncio
async def test_search_index_uses_tag_fallback_when_fts_and_ilike_miss():
    agent = SearchAgent()
    db = FakeDB([], [_candidate(2, title="Tag match")])

    rows = await agent._search_index(
        {"search_terms": ["ai", "agents"], "time_filter": None},
        "user-1",
        db,
    )

    assert len(rows) == 1
    assert "content_tags" in db.calls[1][0]
    assert db.calls[1][1]["terms"] == ["ai", "agents"]


@pytest.mark.asyncio
async def test_rank_candidates_falls_back_when_ai_returns_bad_indices():
    agent = SearchAgent()
    agent._chat_completion = AsyncMock(return_value="[99, \"oops\"]")
    candidates = [_candidate(1), _candidate(2), _candidate(3), _candidate(4)]

    ranked = await agent._rank_candidates("query", candidates)

    assert ranked == candidates


@pytest.mark.asyncio
async def test_generate_answer_returns_fallback_when_ai_is_unavailable():
    agent = SearchAgent()
    agent._chat_completion = AsyncMock(return_value=None)

    result = await agent._generate_answer("query", [_candidate(1), _candidate(2)])

    assert "closest matches" in result["answer"].lower()
    assert len(result["sources"]) == 2


@pytest.mark.asyncio
async def test_generate_answer_uses_model_output_and_serializes_sources():
    agent = SearchAgent()
    agent._chat_completion = AsyncMock(return_value="Synthesized answer")

    result = await agent._generate_answer("query", [_candidate(1), _candidate(2)])

    assert result["answer"] == "Synthesized answer"
    assert result["sources"][0]["id"] == "content-1"
    assert result["sources"][0]["title"] == "Title 1"


@pytest.mark.asyncio
async def test_chat_completion_returns_none_without_api_key():
    agent = SearchAgent()

    with patch("app.services.search_agent.settings.openai_api_key", ""):
        result = await agent._chat_completion(
            messages=[{"role": "user", "content": "hi"}],
            max_tokens=10,
        )

    assert result is None
