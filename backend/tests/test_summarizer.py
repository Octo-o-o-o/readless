"""Tests for the summarization schemas and helpers.

These tests validate Pydantic models and static helpers only.
They do NOT call the Claude API (no API key required).
"""

import pytest

from app.schemas.summary import ContentSummary, OutlinePoint
from app.services.extractor import ExtractedContent, ExtractedParagraph
from app.services.summarizer import SummarizationService


# ------------------------------------------------------------------ #
#  Schema validation
# ------------------------------------------------------------------ #


class TestOutlinePointSchema:
    """Verify OutlinePoint pydantic model validates correctly."""

    def test_outline_point_valid(self) -> None:
        point = OutlinePoint(point="Key idea here", anchors=["¶1", "¶3"])
        assert point.point == "Key idea here"
        assert point.anchors == ["¶1", "¶3"]

    def test_outline_point_empty_anchors(self) -> None:
        point = OutlinePoint(point="No anchors", anchors=[])
        assert point.anchors == []

    def test_outline_point_single_anchor(self) -> None:
        point = OutlinePoint(point="Single source", anchors=["¶5"])
        assert len(point.anchors) == 1

    def test_outline_point_serialization(self) -> None:
        point = OutlinePoint(point="Idea", anchors=["¶1"])
        data = point.model_dump()
        assert data == {"point": "Idea", "anchors": ["¶1"]}

    def test_outline_point_missing_field(self) -> None:
        with pytest.raises(Exception):
            OutlinePoint(point="Missing anchors")  # type: ignore[call-arg]

    def test_outline_point_from_dict(self) -> None:
        data = {"point": "From dict", "anchors": ["¶2", "¶4"]}
        point = OutlinePoint(**data)
        assert point.point == "From dict"
        assert point.anchors == ["¶2", "¶4"]


class TestContentSummarySchema:
    """Verify ContentSummary pydantic model validates correctly."""

    def test_content_summary_valid(self) -> None:
        summary = ContentSummary(
            l0_summary="A concise summary of the article.",
            l1_outline=[
                OutlinePoint(point="First point", anchors=["¶1"]),
                OutlinePoint(point="Second point", anchors=["¶2", "¶3"]),
                OutlinePoint(point="Third point", anchors=["¶4"]),
            ],
            tags=["technology", "AI", "summarization"],
            keywords=["NLP", "Claude", "summary", "extraction", "AI"],
        )
        assert summary.l0_summary == "A concise summary of the article."
        assert len(summary.l1_outline) == 3
        assert len(summary.tags) == 3
        assert len(summary.keywords) == 5

    def test_content_summary_empty_outline(self) -> None:
        summary = ContentSummary(
            l0_summary="Summary",
            l1_outline=[],
            tags=["tag"],
            keywords=["kw"],
        )
        assert summary.l1_outline == []

    def test_content_summary_serialization(self) -> None:
        summary = ContentSummary(
            l0_summary="Summary",
            l1_outline=[
                OutlinePoint(point="Point A", anchors=["¶1"]),
            ],
            tags=["tag1"],
            keywords=["kw1", "kw2"],
        )
        data = summary.model_dump()
        assert data["l0_summary"] == "Summary"
        assert len(data["l1_outline"]) == 1
        assert data["l1_outline"][0]["point"] == "Point A"
        assert data["tags"] == ["tag1"]
        assert data["keywords"] == ["kw1", "kw2"]

    def test_content_summary_missing_field(self) -> None:
        with pytest.raises(Exception):
            ContentSummary(
                l0_summary="Summary",
                l1_outline=[],
                tags=["tag"],
                # missing keywords
            )  # type: ignore[call-arg]

    def test_content_summary_from_json_roundtrip(self) -> None:
        original = ContentSummary(
            l0_summary="Round-trip test",
            l1_outline=[
                OutlinePoint(point="Point", anchors=["¶1", "¶2"]),
            ],
            tags=["test"],
            keywords=["roundtrip"],
        )
        json_str = original.model_dump_json()
        restored = ContentSummary.model_validate_json(json_str)
        assert restored == original


# ------------------------------------------------------------------ #
#  Helper method tests
# ------------------------------------------------------------------ #


class TestSummarizationHelpers:
    """Test static helper methods without requiring API access."""

    def test_build_annotated_text(self) -> None:
        content = ExtractedContent(
            title="Test",
            full_text="Para one.\n\nPara two.",
            paragraphs=[
                ExtractedParagraph(anchor_id="¶1", text="Para one.", position=1),
                ExtractedParagraph(anchor_id="¶2", text="Para two.", position=2),
            ],
        )
        result = SummarizationService._build_annotated_text(content)
        assert "[¶1] Para one." in result
        assert "[¶2] Para two." in result
        assert result.index("[¶1]") < result.index("[¶2]")

    def test_build_annotated_text_empty(self) -> None:
        content = ExtractedContent(
            title="Empty",
            full_text="",
            paragraphs=[],
        )
        result = SummarizationService._build_annotated_text(content)
        assert result == ""

    def test_strip_code_fences_json_block(self) -> None:
        raw = '```json\n{"key": "value"}\n```'
        assert SummarizationService._strip_code_fences(raw) == '{"key": "value"}'

    def test_strip_code_fences_plain_block(self) -> None:
        raw = '```\n{"key": "value"}\n```'
        assert SummarizationService._strip_code_fences(raw) == '{"key": "value"}'

    def test_strip_code_fences_no_fences(self) -> None:
        raw = '{"key": "value"}'
        assert SummarizationService._strip_code_fences(raw) == '{"key": "value"}'

    def test_strip_code_fences_with_whitespace(self) -> None:
        raw = '  ```json\n{"a": 1}\n```  '
        assert SummarizationService._strip_code_fences(raw) == '{"a": 1}'


# ------------------------------------------------------------------ #
#  AI Tag Selection Tests
# ------------------------------------------------------------------ #


class MockResponse:
    """Mock OpenAI API response."""

    def __init__(self, content_dict):
        import json

        self.choices = [
            type(
                "obj",
                (object,),
                {
                    "message": type(
                        "obj",
                        (object,),
                        {"content": json.dumps(content_dict)},
                    )()
                },
            )()
        ]


@pytest.fixture(autouse=True)
def reset_summarizer_singleton():
    """Reset the summarizer singleton between tests."""
    import app.services.summarizer as summarizer_module

    summarizer_module._service = None
    yield
    summarizer_module._service = None


@pytest.mark.asyncio
async def test_generate_summary_with_user_tags(db_session):
    """Test that summary generation includes user's tag library in prompt."""
    from app.services.summarizer import _get_summarizer, SummarizationService
    from app.models.user_tag import UserTag

    # Create user tags
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习")
    tag3 = UserTag(user_id="test_user", tag_name="投资")
    db_session.add_all([tag1, tag2, tag3])
    await db_session.commit()

    # Mock OpenAI response
    from unittest.mock import AsyncMock, patch

    mock_response = {
        "l0_summary": "Test summary",
        "l1_outline": [{"point": "Point 1", "anchors": ["¶1"]}],
        "tags": ["技术", "学习"],
        "keywords": ["test", "keyword"],
    }

    with patch("app.services.summarizer.openai") as mock_openai:
        mock_client = AsyncMock()
        mock_client.chat.completions.create = AsyncMock(
            return_value=MockResponse(mock_response)
        )
        mock_openai.AsyncOpenAI.return_value = mock_client

        summarizer = _get_summarizer()
        result = await summarizer.generate_summary(
            full_text="Test content about technology and learning",
            paragraphs=["Paragraph 1", "Paragraph 2"],
            user_id="test_user",
            db=db_session,
        )

        # Verify tags are returned
        assert result.tags == ["技术", "学习"]

        # Verify prompt included user's tags
        call_args = mock_client.chat.completions.create.call_args
        messages = call_args.kwargs["messages"]
        system_message = messages[0]["content"]

        assert "技术" in system_message
        assert "学习" in system_message
        assert "投资" in system_message


@pytest.mark.asyncio
async def test_generate_summary_with_no_user_tags(db_session):
    """Test summary generation when user has no tags."""
    from app.services.summarizer import _get_summarizer
    from unittest.mock import AsyncMock, patch

    mock_response = {
        "l0_summary": "Test summary",
        "l1_outline": [{"point": "Point 1", "anchors": ["¶1"]}],
        "tags": [],
        "keywords": ["test"],
    }

    with patch("app.services.summarizer.openai") as mock_openai:
        mock_client = AsyncMock()
        mock_client.chat.completions.create = AsyncMock(
            return_value=MockResponse(mock_response)
        )
        mock_openai.AsyncOpenAI.return_value = mock_client

        summarizer = _get_summarizer()
        result = await summarizer.generate_summary(
            full_text="Test content",
            paragraphs=["Paragraph 1"],
            user_id="test_user",
            db=db_session,
        )

        # Should return empty tags array
        assert result.tags == []

        # Verify prompt mentions empty tag library
        call_args = mock_client.chat.completions.create.call_args
        messages = call_args.kwargs["messages"]
        system_message = messages[0]["content"]

        assert (
            "Empty array" in system_message or "no tags" in system_message.lower()
        )
