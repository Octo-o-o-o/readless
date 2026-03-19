"""Agentic search: intent parsing, PostgreSQL FTS, AI ranking, answer synthesis."""

import json
import re

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
        terms = [term for term in re.split(r"\s+", query) if term]
        return {
            "search_terms": terms[:8],
            "time_filter": None,
            "source_type": None,
        }

    async def _parse_intent(self, query: str) -> dict:
        """Use AI to parse a natural-language query into structured intent."""
        message = await self.client.chat.completions.create(
            model=settings.openai_model,
            max_tokens=300,
            messages=[
                {
                    "role": "user",
                    "content": f"""Parse this search query into structured intent.
Query: "{query}"

Return JSON:
{{"search_terms": ["keyword1", "keyword2"], "time_filter": "7d" or "30d" or null,
"source_type": "url" or "pdf" or null}}

JSON only.""",
                }
            ],
        )
        raw = message.choices[0].message.content
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

        # Fallback: if FTS returns nothing, try keyword match or tag join
        if not rows and terms:
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
            f"[{i}] {c.title} — {c.l0_summary}"
            for i, c in enumerate(candidates)
        )
        message = await self.client.chat.completions.create(
            model=settings.openai_model,
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
        raw = message.choices[0].message.content
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
            f"Source: {s.title}\nSummary: {s.l0_summary}\n"
            f"Outline: {json.dumps(s.l1_outline, ensure_ascii=False)}"
            for s in sources[:5]
        )
        message = await self.client.chat.completions.create(
            model=settings.openai_model,
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
        return {
            "answer": message.choices[0].message.content or "No answer generated.",
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
