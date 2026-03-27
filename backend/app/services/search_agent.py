"""Agentic search: intent parsing, PostgreSQL FTS, AI ranking, answer synthesis."""

import asyncio
import json
import re
from typing import Any

import openai
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings


def _strip_code_fences(text_val: str) -> str:
    """Remove markdown code block fences if present."""
    text_val = text_val.strip()
    text_val = re.sub(r"^```(?:json)?\s*\n?", "", text_val)
    text_val = re.sub(r"\n?```\s*$", "", text_val)
    return text_val.strip()


def _compact_text(value: str | None, limit: int) -> str:
    if not value:
        return ""
    collapsed = re.sub(r"\s+", " ", value).strip()
    if len(collapsed) <= limit:
        return collapsed
    return collapsed[: limit - 1].rstrip() + "…"


def _outline_context(outline: Any, *, max_points: int = 5) -> str:
    if not isinstance(outline, list):
        return ""

    points: list[str] = []
    for item in outline[:max_points]:
        if not isinstance(item, dict):
            continue
        point = _compact_text(
            item.get("point") or item.get("title") or item.get("text"),
            180,
        )
        if point:
            points.append(f"- {point}")
    return "\n".join(points)


def _contains_cjk(text_val: str) -> bool:
    """Check if text contains CJK characters (Chinese/Japanese/Korean)."""
    return any("\u4e00" <= c <= "\u9fff" for c in text_val)


def _split_cjk_query(query: str) -> list[str]:
    """Split a query with CJK characters into usable search terms.

    For CJK text, extract contiguous CJK runs and non-CJK words separately.
    CJK runs longer than 2 chars are kept as-is (they form meaningful phrases).
    """
    terms: list[str] = []
    # Split into CJK runs and non-CJK words
    for segment in re.findall(r"[\u4e00-\u9fff]+|[a-zA-Z0-9]+", query):
        if segment:
            terms.append(segment)
    return terms[:8]


class SearchAgent:
    def __init__(self):
        self._client: openai.AsyncOpenAI | None = None

    @property
    def client(self) -> openai.AsyncOpenAI:
        """Lazily create the async OpenAI client on first access."""
        if self._client is None:
            self._client = openai.AsyncOpenAI(
                api_key=settings.openai_api_key,
                base_url=settings.openai_base_url,
            )
        return self._client

    async def search(self, query: str, user_id: str, db: AsyncSession) -> dict:
        """Execute the full agentic search pipeline."""
        query = query.strip()
        if not query:
            return {"answer": "Enter a search query.", "sources": []}

        # Step 1: Parse intent with AI
        intent = await self._parse_intent(query)

        # Step 2: Build and execute SQL query
        candidates = await self._search_index(intent, user_id, db)

        if not candidates:
            return {"answer": "No matching content found.", "sources": []}

        # Step 3: Rank candidates with AI
        ranked = await self._rank_candidates(query, candidates)

        # Step 4: Generate answer
        answer = await self._generate_answer(query, ranked)

        return answer

    async def retrieve(self, query: str, user_id: str, db: AsyncSession) -> list[dict]:
        """Execute lightweight retrieval for interactive search suggestions."""
        trimmed_query = query.strip()
        if not trimmed_query:
            return []

        candidates = await self._search_index(
            self._basic_intent(trimmed_query),
            user_id,
            db,
        )
        return self._serialize_sources(candidates, limit=10)

    def _basic_intent(self, query: str) -> dict:
        if _contains_cjk(query):
            terms = _split_cjk_query(query)
        else:
            terms = [term for term in re.split(r"\s+", query) if term]
        return {
            "search_terms": terms[:8],
            "time_filter": None,
        }

    async def _parse_intent(self, query: str) -> dict:
        """Use AI to parse a natural-language query into structured intent."""
        raw = await self._chat_completion(
            max_tokens=300,
            messages=[
                {
                    "role": "user",
                    "content": f"""Parse this search query into structured intent.
Query: "{query}"

Return JSON:
{{"search_terms": ["keyword1", "keyword2"], "time_filter": "7d" or "30d" or null}}

JSON only.""",
                }
            ],
        )
        if not raw:
            return self._basic_intent(query)
        try:
            return json.loads(_strip_code_fences(raw))
        except (json.JSONDecodeError, ValueError):
            return self._basic_intent(query)

    async def _search_index(
        self, intent: dict, user_id: str, db: AsyncSession
    ) -> list:
        """Query PostgreSQL full-text search index with parsed intent."""
        terms = intent.get("search_terms", [])
        query_str = " ".join(terms) if terms else ""

        sql = """
            SELECT id, title, l0_summary, l1_outline, source_url, created_at,
                ts_rank_cd(full_text_tsv,
                    websearch_to_tsquery('simple', :query)
                ) AS rank
            FROM contents
            WHERE user_id = :user_id
              AND full_text_tsv @@ websearch_to_tsquery('simple', :query)
        """
        params: dict = {"user_id": user_id, "query": query_str}

        time_filter = intent.get("time_filter")
        if time_filter == "7d":
            sql += " AND created_at > NOW() - INTERVAL '7 days'"
        elif time_filter == "30d":
            sql += " AND created_at > NOW() - INTERVAL '30 days'"

        sql += " ORDER BY rank DESC LIMIT 10"

        result = await db.execute(text(sql), params)
        rows = result.fetchall()

        # Fallback: if FTS returns nothing, try CJK ILIKE or keyword/tag match
        if not rows and terms:
            has_cjk = any(_contains_cjk(t) for t in terms)

            if has_cjk:
                # For CJK queries, use ILIKE substring match on text columns
                like_conditions = []
                like_params: dict = {"user_id": user_id}
                for i, term in enumerate(terms):
                    pkey = f"term_{i}"
                    like_conditions.append(
                        f"(title ILIKE :{pkey} OR l0_summary ILIKE :{pkey})"
                    )
                    like_params[pkey] = f"%{term}%"

                like_sql = f"""
                    SELECT id, title, l0_summary, l1_outline, source_url,
                           created_at
                    FROM contents
                    WHERE user_id = :user_id
                      AND ({" OR ".join(like_conditions)})
                    ORDER BY created_at DESC LIMIT 10
                """
                result = await db.execute(text(like_sql), like_params)
                rows = result.fetchall()

            if not rows:
                tag_sql = """
                    SELECT DISTINCT
                        c.id,
                        c.title,
                        c.l0_summary,
                        c.l1_outline,
                        c.source_url,
                        c.created_at
                    FROM contents c
                    LEFT JOIN content_tags ct ON c.id = ct.content_id
                    LEFT JOIN user_tags ut ON ct.tag_id = ut.id
                    WHERE c.user_id = :user_id
                      AND (c.keywords && CAST(:terms AS text[])
                        OR ut.tag_name = ANY(:terms))
                    ORDER BY c.created_at DESC LIMIT 10
                """
                result = await db.execute(
                    text(tag_sql), {"user_id": user_id, "terms": terms}
                )
                rows = result.fetchall()

        return rows

    async def _rank_candidates(self, query: str, candidates: list) -> list:
        """Use AI to re-rank search candidates by relevance."""
        if len(candidates) <= 3:
            return candidates

        summaries = "\n".join(
            f"[{i}] {_compact_text(c.title, 120)} — {_compact_text(c.l0_summary, 180)}"
            for i, c in enumerate(candidates)
        )
        raw = await self._chat_completion(
            max_tokens=100,
            messages=[
                {
                    "role": "user",
                    "content": f"""Rank these by relevance to: "{query}"
{summaries}
Return JSON array of indices, most relevant first. JSON only.""",
                }
            ],
        )
        if not raw:
            return candidates
        try:
            indices = json.loads(_strip_code_fences(raw))
            return [candidates[i] for i in indices if i < len(candidates)]
        except (json.JSONDecodeError, IndexError, TypeError):
            return candidates

    async def _generate_answer(self, query: str, sources: list) -> dict:
        """Synthesize a final answer from top-ranked sources."""
        context = "\n\n".join(
            (
                f"Source: {_compact_text(s.title, 120)}\n"
                f"Summary: {_compact_text(s.l0_summary, 280)}\n"
                f"Outline:\n{_outline_context(s.l1_outline)}"
            )
            for s in sources[:5]
        )
        raw = await self._chat_completion(
            max_tokens=500,
            messages=[
                {
                    "role": "user",
                    "content": f"""Answer this question using ONLY the \
provided sources. Cite each source by title.

Question: {query}

Sources:
{context}

If the answer spans multiple sources, synthesize them. \
If no source answers the question, say so.""",
                }
            ],
        )
        if not raw:
            return self._fallback_answer(sources)
        return {
            "answer": raw,
            "sources": self._serialize_sources(sources, limit=5),
        }

    def _serialize_sources(self, sources: list, limit: int) -> list[dict]:
        return [
            {
                "id": source.id,
                "title": source.title,
                "l0_summary": source.l0_summary,
                "source_url": source.source_url,
            }
            for source in sources[:limit]
        ]

    async def _chat_completion(
        self, *, messages: list[dict[str, str]], max_tokens: int
    ) -> str | None:
        if not settings.openai_api_key:
            return None

        try:
            message = await asyncio.wait_for(
                self.client.chat.completions.create(
                    model=settings.openai_model,
                    max_tokens=max_tokens,
                    messages=messages,
                ),
                timeout=settings.search_llm_timeout_seconds,
            )
        except Exception:
            return None

        return message.choices[0].message.content

    def _fallback_answer(self, sources: list) -> dict:
        if not sources:
            return {"answer": "No matching content found.", "sources": []}

        bullets = [
            (
                f"- {_compact_text(source.title, 120)}: "
                f"{_compact_text(source.l0_summary, 180) or 'No summary available.'}"
            )
            for source in sources[:3]
        ]
        return {
            "answer": "Here are the closest matches from your library:\n"
            + "\n".join(bullets),
            "sources": self._serialize_sources(sources, limit=5),
        }
