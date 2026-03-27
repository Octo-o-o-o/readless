"""Tests for translation service fallbacks and JSON parsing."""

from __future__ import annotations

from collections import deque
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.schemas.summary import ContentSummary, OutlinePoint
from app.services.translator import TranslationService


class FakeChatCompletions:
    def __init__(self, responses):
        self.responses = deque(responses)
        self.calls: list[dict] = []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        response = self.responses.popleft()
        if isinstance(response, Exception):
            raise response
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=response))]
        )


class FakeOpenAIClient:
    def __init__(self, responses):
        self.chat = SimpleNamespace(completions=FakeChatCompletions(responses))


def _summary() -> ContentSummary:
    return ContentSummary(
        l0_summary="A concise summary",
        l1_outline=[OutlinePoint(point="Point one", anchors=["¶1"])],
        tags=["ai"],
        keywords=["agent"],
    )


def _service_with_client(*responses) -> TranslationService:
    service = TranslationService.__new__(TranslationService)
    service.client = FakeOpenAIClient(responses)
    return service


def test_translation_helpers_strip_fences_and_map_language_names():
    assert (
        TranslationService._strip_code_fences("```json\n{\"a\":1}\n```")
        == "{\"a\":1}"
    )
    assert TranslationService._language_name("zh") == "Chinese"
    assert TranslationService._language_name("xx") == "XX"


@pytest.mark.asyncio
async def test_detect_language_falls_back_to_english_on_parse_error():
    service = _service_with_client("not-json")

    language = await service.detect_language("Bonjour le monde")

    assert language == "en"


@pytest.mark.asyncio
async def test_translate_summary_skips_when_source_matches_target():
    service = _service_with_client()
    service.detect_language = AsyncMock(return_value="en")
    summary = _summary()

    translated = await service.translate_summary(summary, target_lang="en")

    assert translated is summary


@pytest.mark.asyncio
async def test_translate_summary_parses_json_and_preserves_tags_and_keywords():
    service = _service_with_client(
        """```json
        {"l0_summary":"中文摘要","l1_outline":[{"point":"要点一","anchors":["¶1"]}]}
        ```"""
    )

    translated = await service.translate_summary(
        _summary(),
        target_lang="zh",
        source_lang="en",
    )

    assert translated.l0_summary == "中文摘要"
    assert translated.l1_outline[0].point == "要点一"
    assert translated.l1_outline[0].anchors == ["¶1"]
    assert translated.tags == ["ai"]
    assert translated.keywords == ["agent"]


@pytest.mark.asyncio
async def test_translate_text_auto_detects_and_returns_trimmed_result():
    service = _service_with_client("  翻译后的文本 [¶1]  ")
    service.detect_language = AsyncMock(return_value="en")

    translated = await service.translate_text(
        "Original text [¶1]",
        target_lang="zh",
    )

    assert translated == "翻译后的文本 [¶1]"
