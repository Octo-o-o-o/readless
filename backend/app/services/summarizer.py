"""AI summarization service using Claude for multi-level summaries."""

from __future__ import annotations

import json
import logging
import re

import anthropic

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
You are a detailed explanation engine. Cite sources using [¶N] markers."""

EXPAND_USER_PROMPT = """\
Below is a text with numbered paragraph markers [¶N].

{annotated_text}

Explain the following outline point in 2-3 paragraphs. Cite relevant source \
paragraphs using [¶N] markers.

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
    """Produces multi-level summaries via the Anthropic Claude API."""

    def __init__(self) -> None:
        self.client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

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

    async def summarize(self, content: ExtractedContent) -> ContentSummary:
        """Generate an L0 one-line summary and L1 structured outline."""
        annotated_text = self._build_annotated_text(content)

        message = self.client.messages.create(
            model="claude-sonnet-4-5-20250514",
            max_tokens=2000,
            system=SUMMARIZE_SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": SUMMARIZE_USER_PROMPT.format(
                        annotated_text=annotated_text
                    ),
                },
            ],
        )

        raw_text = message.content[0].text
        cleaned = self._strip_code_fences(raw_text)
        data = json.loads(cleaned)

        return ContentSummary(
            l0_summary=data["l0_summary"],
            l1_outline=[
                OutlinePoint(point=item["point"], anchors=item["anchors"])
                for item in data["l1_outline"]
            ],
            tags=data["tags"],
            keywords=data["keywords"],
        )

    # ------------------------------------------------------------------ #
    #  L2: Expand a specific outline point
    # ------------------------------------------------------------------ #

    async def expand_point(
        self, content: ExtractedContent, point: OutlinePoint
    ) -> str:
        """Expand a specific outline point into 2-3 detailed paragraphs."""
        annotated_text = self._build_annotated_text(content)

        message = self.client.messages.create(
            model="claude-sonnet-4-5-20250514",
            max_tokens=2000,
            system=EXPAND_SYSTEM_PROMPT,
            messages=[
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

        return message.content[0].text

    # ------------------------------------------------------------------ #
    #  L3: Follow-up Q&A
    # ------------------------------------------------------------------ #

    async def ask_followup(
        self, content: ExtractedContent, question: str
    ) -> str:
        """Answer a follow-up question based ONLY on the content."""
        annotated_text = self._build_annotated_text(content)

        message = self.client.messages.create(
            model="claude-sonnet-4-5-20250514",
            max_tokens=2000,
            system=FOLLOWUP_SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": FOLLOWUP_USER_PROMPT.format(
                        annotated_text=annotated_text,
                        question=question,
                    ),
                },
            ],
        )

        return message.content[0].text
