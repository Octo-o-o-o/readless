"""Translation service for content summaries using OpenAI."""

from __future__ import annotations

import json
import logging
import re

import openai

from app.config import settings
from app.schemas.summary import ContentSummary, OutlinePoint

logger = logging.getLogger(__name__)

DETECT_LANGUAGE_SYSTEM_PROMPT = """\
You are a language detection engine. You always respond with valid JSON only — \
no markdown fences, no explanation, no extra text."""

DETECT_LANGUAGE_USER_PROMPT = """\
Detect the primary language of the following text \
and return the ISO 639-1 language code.

Text: {text}

Return ONLY a JSON object with this structure:
{{
  "language_code": "en"
}}

Supported codes: en (English), zh (Chinese), ja (Japanese), es (Spanish), \
fr (French), de (German), ko (Korean), ru (Russian), ar (Arabic), pt (Portuguese)."""

TRANSLATE_SYSTEM_PROMPT = """\
You are a professional translator. You always respond with valid JSON only — \
no markdown fences, no explanation, no extra text. Preserve all paragraph \
markers like [¶1], [¶2], etc. exactly as they appear."""

TRANSLATE_SUMMARY_USER_PROMPT = """\
Translate the following content summary from {source_lang} to {target_lang}. \
IMPORTANT: Keep all paragraph markers [¶1], [¶2], etc. unchanged in the translated text.

L0 Summary: {l0_summary}

L1 Outline:
{l1_outline}

Return ONLY a JSON object with this structure:
{{
  "l0_summary": "translated one-line summary",
  "l1_outline": [
    {{
      "point": "translated point text",
      "anchors": ["¶1", "¶2"]
    }}
  ]
}}

Preserve the original anchors array unchanged."""

TRANSLATE_TEXT_SYSTEM_PROMPT = """\
You are a professional translator. Translate the text accurately while \
preserving all paragraph markers like [¶1], [¶2], etc. exactly as they appear."""

TRANSLATE_TEXT_USER_PROMPT = """\
Translate the following text from {source_lang} to {target_lang}. \
Preserve all paragraph markers [¶1], [¶2], etc. exactly as they appear.

Text: {text}"""


class TranslationService:
    """Detects language and translates content summaries via OpenAI."""

    def __init__(self) -> None:
        self.client = openai.AsyncOpenAI(
            api_key=settings.openai_api_key,
            base_url=settings.openai_base_url,
        )

    # ------------------------------------------------------------------ #
    #  Helpers
    # ------------------------------------------------------------------ #

    @staticmethod
    def _strip_code_fences(text: str) -> str:
        """Remove markdown code block fences if present."""
        text = text.strip()
        # Remove ```json ... ``` or ``` ... ```
        text = re.sub(r"^```(?:json)?\s*\n?", "", text)
        text = re.sub(r"\n?```\s*$", "", text)
        return text.strip()

    @staticmethod
    def _language_name(code: str) -> str:
        """Get human-readable language name from ISO code."""
        mapping = {
            "en": "English",
            "zh": "Chinese",
            "ja": "Japanese",
            "es": "Spanish",
            "fr": "French",
            "de": "German",
            "ko": "Korean",
            "ru": "Russian",
            "ar": "Arabic",
            "pt": "Portuguese",
        }
        return mapping.get(code, code.upper())

    # ------------------------------------------------------------------ #
    #  Language Detection
    # ------------------------------------------------------------------ #

    async def detect_language(self, text: str) -> str:
        """
        Detect the primary language of text using OpenAI.

        Args:
            text: Text to analyze (typically L0 summary)

        Returns:
            ISO 639-1 language code (e.g., 'en', 'zh', 'ja')

        Raises:
            Exception: If detection fails
        """
        logger.info("Detecting language for text: %s...", text[:50])

        try:
            response = await self.client.chat.completions.create(
                model=settings.openai_model,
                messages=[
                    {"role": "system", "content": DETECT_LANGUAGE_SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": DETECT_LANGUAGE_USER_PROMPT.format(text=text),
                    },
                ],
                temperature=0.0,
            )

            content = response.choices[0].message.content or ""
            content = self._strip_code_fences(content)

            result = json.loads(content)
            language_code = result.get("language_code", "en")

            logger.info("Detected language: %s", language_code)
            return language_code

        except Exception as e:
            logger.error("Language detection failed: %s", e)
            # Fallback to English
            return "en"

    # ------------------------------------------------------------------ #
    #  Translation
    # ------------------------------------------------------------------ #

    async def translate_summary(
        self,
        summary: ContentSummary,
        target_lang: str,
        source_lang: str | None = None,
    ) -> ContentSummary:
        """
        Translate a ContentSummary to target language.

        Args:
            summary: The summary to translate (L0 + L1)
            target_lang: Target language ISO code
            source_lang: Source language ISO code (optional, defaults to auto-detect)

        Returns:
            Translated ContentSummary with same structure

        Raises:
            Exception: If translation fails
        """
        # Auto-detect source language if not provided
        if source_lang is None:
            source_lang = await self.detect_language(summary.l0_summary)

        # Skip translation if same language
        if source_lang == target_lang:
            logger.info(
                "Source and target language are the same (%s), skipping translation",
                source_lang,
            )
            return summary

        logger.info(
            "Translating summary from %s to %s",
            self._language_name(source_lang),
            self._language_name(target_lang),
        )

        # Format L1 outline for prompt
        l1_outline_text = "\n".join(
            f"- {point.point} (anchors: {', '.join(point.anchors)})"
            for point in summary.l1_outline
        )

        try:
            response = await self.client.chat.completions.create(
                model=settings.openai_model,
                messages=[
                    {"role": "system", "content": TRANSLATE_SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": TRANSLATE_SUMMARY_USER_PROMPT.format(
                            source_lang=self._language_name(source_lang),
                            target_lang=self._language_name(target_lang),
                            l0_summary=summary.l0_summary,
                            l1_outline=l1_outline_text,
                        ),
                    },
                ],
                temperature=0.3,
            )

            content = response.choices[0].message.content or ""
            content = self._strip_code_fences(content)

            result = json.loads(content)

            # Build translated summary
            translated_outline = [
                OutlinePoint(
                    point=item["point"],
                    anchors=item["anchors"],
                )
                for item in result["l1_outline"]
            ]

            translated_summary = ContentSummary(
                l0_summary=result["l0_summary"],
                l1_outline=translated_outline,
                tags=summary.tags,  # Keep original tags
                keywords=summary.keywords,  # Keep original keywords
            )

            logger.info("Translation completed successfully")
            return translated_summary

        except Exception as e:
            logger.error("Translation failed: %s", e)
            raise

    async def translate_text(
        self,
        text: str,
        target_lang: str,
        source_lang: str | None = None,
    ) -> str:
        """
        Translate arbitrary text to target language.

        Args:
            text: Text to translate (e.g., L2 expanded detail)
            target_lang: Target language ISO code
            source_lang: Source language ISO code (optional)

        Returns:
            Translated text with preserved paragraph markers

        Raises:
            Exception: If translation fails
        """
        # Auto-detect source language if not provided
        if source_lang is None:
            source_lang = await self.detect_language(text[:200])

        # Skip translation if same language
        if source_lang == target_lang:
            return text

        logger.info(
            "Translating text from %s to %s",
            self._language_name(source_lang),
            self._language_name(target_lang),
        )

        try:
            response = await self.client.chat.completions.create(
                model=settings.openai_model,
                messages=[
                    {"role": "system", "content": TRANSLATE_TEXT_SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": TRANSLATE_TEXT_USER_PROMPT.format(
                            source_lang=self._language_name(source_lang),
                            target_lang=self._language_name(target_lang),
                            text=text,
                        ),
                    },
                ],
                temperature=0.3,
            )

            translated = response.choices[0].message.content or ""
            logger.info("Text translation completed")
            return translated.strip()

        except Exception as e:
            logger.error("Text translation failed: %s", e)
            raise


# Lazy singleton pattern
_service: TranslationService | None = None


def _get_service() -> TranslationService:
    """Get or create the singleton TranslationService instance."""
    global _service
    if _service is None:
        _service = TranslationService()
    return _service
