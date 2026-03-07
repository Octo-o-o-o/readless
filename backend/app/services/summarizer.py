"""AI summarization service using OpenAI-compatible APIs for multi-level summaries."""

from __future__ import annotations

import asyncio
import json
import logging
import re

import openai
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.schemas.summary import ContentSummary, OutlinePoint
from app.services.extractor import ExtractedContent

logger = logging.getLogger(__name__)

SUMMARIZE_SYSTEM_PROMPT = """\
You are a precise summarization engine. You always respond with valid JSON only — \
no markdown fences, no explanation, no extra text."""

SUMMARIZE_USER_PROMPT = """\
Below is a text with numbered paragraph markers [¶N].

{annotated_text}

Produce a JSON object with exactly these keys:

- "l0_summary": a one-line summary (≤30 Chinese characters or ≤60 English characters).
- "l1_outline": an array of 3-5 objects, each with:
    - "point": a concise statement of the key idea.
    - "anchors": an array of source paragraph markers (e.g. ["¶1", "¶3"]).
- "tags": 3-5 topic tags.
- "keywords": 5-10 keywords.

Return ONLY the JSON object. No markdown, no code blocks."""

EXPAND_SYSTEM_PROMPT = """\
You are a detailed explanation engine. Cite sources using [¶N] markers. \
Be concise — your explanation should not exceed the length of the cited source paragraphs."""

EXPAND_USER_PROMPT = """\
Below is a text with numbered paragraph markers [¶N].

{annotated_text}

Explain the following outline point concisely. Keep the explanation \
proportional to the source material. Cite relevant source paragraphs using [¶N] markers.

Outline point: {point}
Related source paragraphs: {anchors}"""

FOLLOWUP_SYSTEM_PROMPT = """\
You are a Q&A engine. Answer ONLY based on the provided text. \
Cite sources using [¶N] markers. If the answer is not in the text, say so."""

FOLLOWUP_USER_PROMPT = """\
Below is a text with numbered paragraph markers [¶N].

{annotated_text}

Question: {question}

Answer the question based ONLY on the text above. Cite relevant source \
paragraphs using [¶N] markers."""


class SummarizationService:
    """Produces multi-level summaries via OpenAI-compatible APIs."""

    def __init__(self) -> None:
        self.client = openai.AsyncOpenAI(
            api_key=settings.openai_api_key,
            base_url=settings.openai_base_url,
        )

    # ------------------------------------------------------------------ #
    #  Helpers
    # ------------------------------------------------------------------ #

    @staticmethod
    def _build_annotated_text(content: ExtractedContent) -> str:
        """Build text with paragraph markers: [¶1] paragraph text ..."""
        parts: list[str] = []
        for para in content.paragraphs:
            parts.append(f"[{para.anchor_id}] {para.text}")
        return "\n\n".join(parts)

    @staticmethod
    def _strip_code_fences(text: str) -> str:
        """Remove markdown code block fences if present."""
        text = text.strip()
        # Remove ```json ... ``` or ``` ... ```
        text = re.sub(r"^```(?:json)?\s*\n?", "", text)
        text = re.sub(r"\n?```\s*$", "", text)
        return text.strip()

    # ------------------------------------------------------------------ #
    #  L0 + L1: Summarize
    # ------------------------------------------------------------------ #

    async def summarize(self, content: ExtractedContent) -> tuple[ContentSummary, str]:
        """
        Generate an L0 one-line summary and L1 structured outline.

        Returns:
            A tuple of (ContentSummary, detected_language_code)
        """
        annotated_text = self._build_annotated_text(content)

        message = await self.client.chat.completions.create(
            model=settings.openai_model,
            max_tokens=2000,
            messages=[
                {"role": "system", "content": SUMMARIZE_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": SUMMARIZE_USER_PROMPT.format(
                        annotated_text=annotated_text
                    ),
                },
            ],
        )

        raw_text = message.choices[0].message.content
        if not raw_text:
            raise ValueError("OpenAI returned empty content for summarization")
        cleaned = self._strip_code_fences(raw_text)
        data = json.loads(cleaned)

        summary = ContentSummary(
            l0_summary=data["l0_summary"],
            l1_outline=[
                OutlinePoint(point=item["point"], anchors=item["anchors"])
                for item in data["l1_outline"]
            ],
            tags=data["tags"],
            keywords=data["keywords"],
        )

        # Detect language from L0 summary
        from app.services.translator import _get_service
        translator = _get_service()
        detected_language = await translator.detect_language(summary.l0_summary)
        logger.info("Detected content language: %s", detected_language)

        return summary, detected_language

    # ------------------------------------------------------------------ #
    #  L2: Expand a specific outline point
    # ------------------------------------------------------------------ #

    async def expand_point(
        self, content: ExtractedContent, point: OutlinePoint
    ) -> str:
        """Expand a specific outline point into 2-3 detailed paragraphs."""
        annotated_text = self._build_annotated_text(content)

        message = await self.client.chat.completions.create(
            model=settings.openai_model,
            max_tokens=2000,
            messages=[
                {"role": "system", "content": EXPAND_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": EXPAND_USER_PROMPT.format(
                        annotated_text=annotated_text,
                        point=point.point,
                        anchors=", ".join(point.anchors),
                    ),
                },
            ],
        )

        return message.choices[0].message.content or ""

    # ------------------------------------------------------------------ #
    #  Pre-generate L2 details for all outline points
    # ------------------------------------------------------------------ #

    async def pre_generate_details(
        self,
        content: ExtractedContent,
        outline: list[OutlinePoint],
    ) -> list[OutlinePoint]:
        """Pre-generate L2 details for all outline points.

        - If an outline point's source paragraphs total < 200 chars,
          use the original text directly (no AI call needed).
        - Otherwise, generate L2 via AI (in parallel for all such points).
        """
        # Build anchor → paragraph text lookup
        anchor_map: dict[str, str] = {
            p.anchor_id: p.text for p in content.paragraphs
        }

        # Classify points: short (use raw text) vs long (need AI)
        ai_needed_indices: list[int] = []
        for i, point in enumerate(outline):
            source_texts = [
                anchor_map[a] for a in point.anchors if a in anchor_map
            ]
            combined = "\n\n".join(source_texts)
            if len(combined) < 200:
                point.detail = combined
            else:
                ai_needed_indices.append(i)

        # Generate AI expansions in parallel
        if ai_needed_indices:
            tasks = [
                self.expand_point(content, outline[i])
                for i in ai_needed_indices
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            for i, result in zip(ai_needed_indices, results):
                if isinstance(result, Exception):
                    logger.warning(
                        "Failed to pre-generate L2 for point %d: %s", i, result
                    )
                else:
                    outline[i].detail = result

        return outline

    # ------------------------------------------------------------------ #
    #  L3: Follow-up Q&A
    # ------------------------------------------------------------------ #

    async def ask_followup(
        self, content: ExtractedContent, question: str
    ) -> str:
        """Answer a follow-up question based ONLY on the content."""
        annotated_text = self._build_annotated_text(content)

        message = await self.client.chat.completions.create(
            model=settings.openai_model,
            max_tokens=2000,
            messages=[
                {"role": "system", "content": FOLLOWUP_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": FOLLOWUP_USER_PROMPT.format(
                        annotated_text=annotated_text,
                        question=question,
                    ),
                },
            ],
        )

        return message.choices[0].message.content or ""

    # ------------------------------------------------------------------ #
    #  Generate Summary with AI Tag Selection
    # ------------------------------------------------------------------ #

    async def generate_summary(
        self,
        full_text: str,
        paragraphs: list[str],
        user_id: str,
        db: AsyncSession,
        max_outline_points: int = 5,
    ) -> ContentSummary:
        """Generate multi-level summary with AI tag selection from user's library.

        Args:
            max_outline_points: Max L1 outline points to generate.
                0 = L0 summary only (no outline).
        """

        # 1. Fetch user's tag library
        from app.models.user_tag import UserTag

        try:
            stmt = select(UserTag.tag_name).where(
                UserTag.user_id == user_id,
                UserTag.deleted_at.is_(None),
            )
            result = await db.execute(stmt)
            available_tags = [row[0] for row in result.all()]
        except Exception:
            # Fallback to empty tag library on database error
            available_tags = []

        # 2. Build tag instruction based on user's library
        if available_tags:
            tag_instruction = (
                f'- "tags": Select 0-3 most relevant tags from'
                f" the user's tag library: {available_tags}\n"
                "  If none of the tags are relevant,"
                " return an empty array."
            )
        else:
            tag_instruction = (
                '- "tags": Empty array'
                " (user has no tags in their library yet)."
            )

        # 3. Build numbered paragraphs for anchoring
        numbered_paragraphs = [f"¶{i+1}: {p}" for i, p in enumerate(paragraphs)]
        user_message = "\n\n".join(numbered_paragraphs)

        # Detect language
        has_chinese = any("\u4e00" <= c <= "\u9fff" for c in full_text[:500])
        lang_note = "Chinese" if has_chinese else "English"

        # 4. Build outline instruction based on max_outline_points
        if max_outline_points > 0:
            outline_instruction = (
                f'- "l1_outline": an array of up to {max_outline_points}'
                " objects, each with:\n"
                '   - "point": a short key idea'
                " (≤15 Chinese chars or ≤30 English chars).\n"
                '   - "anchors": source paragraph markers (e.g. ["¶1", "¶3"]).\n'
                "  The total outline must be much shorter than the original text."
            )
        else:
            outline_instruction = '- "l1_outline": an empty array [].'

        # 5. Build system prompt
        system_prompt = f"""You are a professional content analyst. \
Generate a summary in {lang_note}.

Return a JSON object with:
- "l0_summary": one-line summary (≤30 Chinese chars or ≤60 English chars).
{outline_instruction}
{tag_instruction}
- "keywords": 5-10 keywords.

Return ONLY the JSON object. No markdown, no code blocks."""

        # 6. Call OpenAI API
        response = await self.client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
            temperature=0.3,
            max_tokens=2000,
        )

        # 7. Parse response
        raw = response.choices[0].message.content
        if not raw:
            raise ValueError("OpenAI returned empty content for summarization")

        # Remove markdown code fences if present
        cleaned = self._strip_code_fences(raw.strip())

        try:
            data = json.loads(cleaned)
        except json.JSONDecodeError as e:
            raise ValueError(f"Failed to parse AI response as JSON: {cleaned}") from e

        # 8. Validate tags are from user's library
        if available_tags and data.get("tags"):
            invalid_tags = [tag for tag in data["tags"] if tag not in available_tags]
            if invalid_tags:
                data["tags"] = [tag for tag in data["tags"] if tag in available_tags]

        # 9. Build outline (cap at max_outline_points)
        raw_outline = data.get("l1_outline") or []
        outline = [
            OutlinePoint(point=item["point"], anchors=item.get("anchors", []))
            for item in raw_outline[:max_outline_points]
        ] if max_outline_points > 0 else []

        return ContentSummary(
            l0_summary=data["l0_summary"],
            l1_outline=outline,
            tags=data.get("tags", []),
            keywords=data.get("keywords", []),
        )


# ------------------------------------------------------------------ #
#  Singleton
# ------------------------------------------------------------------ #

_service: SummarizationService | None = None


def _get_summarizer() -> SummarizationService:
    """Get or create the singleton SummarizationService instance."""
    global _service
    if _service is None:
        _service = SummarizationService()
    return _service
