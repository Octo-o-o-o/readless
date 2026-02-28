"""Tests for the ContentExtractor — text extraction and paragraph segmentation.

These tests require NO network access and NO external files.
"""

import pytest

from app.services.extractor import ContentExtractor


@pytest.fixture
def extractor() -> ContentExtractor:
    return ContentExtractor()


# ------------------------------------------------------------------ #
#  test_extract_from_text
# ------------------------------------------------------------------ #


async def test_extract_from_text(extractor: ContentExtractor) -> None:
    """Two paragraphs separated by a double newline produce anchor_ids ¶1, ¶2."""
    text = (
        "This is the first paragraph with enough characters to stay alone.\n\n"
        "This is the second paragraph, also long enough to remain separate."
    )
    result = await extractor.extract_text(text)

    assert len(result.paragraphs) == 2
    assert result.paragraphs[0].anchor_id == "¶1"
    assert result.paragraphs[1].anchor_id == "¶2"
    assert "first paragraph" in result.paragraphs[0].text
    assert "second paragraph" in result.paragraphs[1].text


# ------------------------------------------------------------------ #
#  test_segment_merges_short_paragraphs
# ------------------------------------------------------------------ #


async def test_segment_merges_short_paragraphs(extractor: ContentExtractor) -> None:
    """Paragraphs shorter than 30 chars are merged with the next one."""
    text = (
        "Short\n\n"
        "This paragraph is long enough to exceed the thirty-character threshold easily."
    )
    paragraphs = extractor._segment_paragraphs(text)

    # "Short" (5 chars) should be merged into the next paragraph
    assert len(paragraphs) == 1
    assert "Short" in paragraphs[0].text
    assert "long enough" in paragraphs[0].text
    assert paragraphs[0].anchor_id == "¶1"


# ------------------------------------------------------------------ #
#  test_extract_text_uses_first_line_as_title
# ------------------------------------------------------------------ #


async def test_extract_text_uses_first_line_as_title(
    extractor: ContentExtractor,
) -> None:
    """The first line of the input text (max 100 chars) becomes the title."""
    title_line = "My Article Title"
    body = "Some body text that is definitely more than thirty characters long."
    text = f"{title_line}\n\n{body}"

    result = await extractor.extract_text(text)

    assert result.title == title_line
    assert result.source_url is None
