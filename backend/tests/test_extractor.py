"""Tests for the ContentExtractor — text extraction and paragraph segmentation.

These tests require NO network access and NO external files.
"""

import base64
from io import BytesIO
from unittest.mock import patch

import pytest
from PIL import Image

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


async def test_extract_pdf_accepts_base64_payload(extractor: ContentExtractor) -> None:
    """Base64 PDF payloads should be decoded and parsed without file paths."""
    payload = base64.b64encode(b"%PDF-1.4 fake").decode()

    class _FakePage:
        def __init__(self, text: str):
            self._text = text

        def extract_text(self) -> str:
            return self._text

    class _FakePDF:
        def __init__(self, texts: list[str]):
            self.pages = [_FakePage(text) for text in texts]

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    with patch(
        "app.services.extractor.pdfplumber.open",
        return_value=_FakePDF(
            ["First PDF paragraph with enough characters.", "Second PDF paragraph."]
        ),
    ) as mock_open:
        result = await extractor.extract_pdf(payload)

    first_arg = mock_open.call_args.args[0]
    assert hasattr(first_arg, "read")
    assert result.title == "Uploaded PDF"
    assert "First PDF paragraph" in result.full_text
    assert len(result.paragraphs) >= 1


async def test_extract_image_accepts_base64_payload(
    extractor: ContentExtractor,
) -> None:
    """Base64 image payloads should be decoded and passed to OCR."""
    image = Image.new("RGB", (8, 8), color="white")
    image_buffer = BytesIO()
    image.save(image_buffer, format="PNG")
    payload = base64.b64encode(image_buffer.getvalue()).decode()

    with patch(
        "app.services.extractor.pytesseract.image_to_string",
        return_value="OCR result text",
    ) as mock_ocr:
        result = await extractor.extract_image(payload)

    assert mock_ocr.call_count == 1
    assert result.title == "Uploaded Image"
    assert "OCR result text" == result.full_text
