"""Content extraction service for URLs, raw text, PDFs, and images."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from pathlib import Path

import httpx
import pdfplumber
import pytesseract
import trafilatura
from PIL import Image

logger = logging.getLogger(__name__)


@dataclass
class ExtractedParagraph:
    """A single paragraph extracted from content."""

    anchor_id: str  # e.g. "¶1"
    text: str
    position: int


@dataclass
class ExtractedContent:
    """Full extracted content with metadata."""

    title: str
    full_text: str
    paragraphs: list[ExtractedParagraph] = field(default_factory=list)
    source_url: str | None = None


class ContentExtractor:
    """Extracts and segments text from various sources."""

    # ------------------------------------------------------------------ #
    #  Paragraph segmentation
    # ------------------------------------------------------------------ #

    @staticmethod
    def _segment_paragraphs(text: str) -> list[ExtractedParagraph]:
        """Split *text* on double newlines, merge short paragraphs (<30 chars)
        with the following one, and assign anchor IDs "¶1", "¶2", ...
        """
        raw_parts = [p.strip() for p in text.split("\n\n") if p.strip()]

        # Merge short paragraphs with the next one
        merged: list[str] = []
        carry = ""
        for part in raw_parts:
            combined = f"{carry}\n{part}" if carry else part
            if len(combined) < 30:
                carry = combined
            else:
                merged.append(combined)
                carry = ""
        if carry:
            # Trailing short fragment — attach to previous if possible
            if merged:
                merged[-1] = f"{merged[-1]}\n{carry}"
            else:
                merged.append(carry)

        paragraphs: list[ExtractedParagraph] = []
        for idx, para in enumerate(merged, start=1):
            paragraphs.append(
                ExtractedParagraph(
                    anchor_id=f"¶{idx}",
                    text=para,
                    position=idx,
                )
            )
        return paragraphs

    # ------------------------------------------------------------------ #
    #  URL extraction
    # ------------------------------------------------------------------ #

    async def extract_url(self, url: str) -> ExtractedContent:
        """Fetch and extract content from *url*.

        Primary strategy: trafilatura.
        Fallback: Jina Reader API.
        """
        downloaded = trafilatura.fetch_url(url)
        body: str | None = None
        title: str | None = None

        if downloaded:
            body = trafilatura.extract(downloaded)
            title = trafilatura.extract(downloaded, output_format="xmltei")
            # Try to pull <title> from the TEI header
            if title:
                m = re.search(r"<title[^>]*>([^<]+)</title>", title)
                title = m.group(1).strip() if m else None

        # Fallback to Jina Reader
        if not body:
            jina_url = f"https://r.jina.ai/{url}"
            async with httpx.AsyncClient(timeout=30) as client:
                resp = await client.get(
                    jina_url, headers={"Accept": "text/plain"}
                )
                resp.raise_for_status()
                body = resp.text

            # Jina's first line is usually the title
            if body:
                lines = body.split("\n", 1)
                if not title:
                    title = lines[0].strip()[:100]

        body = body or ""
        title = title or url

        paragraphs = self._segment_paragraphs(body)
        return ExtractedContent(
            title=title,
            full_text=body,
            paragraphs=paragraphs,
            source_url=url,
        )

    # ------------------------------------------------------------------ #
    #  Plain-text extraction
    # ------------------------------------------------------------------ #

    async def extract_text(self, text: str) -> ExtractedContent:
        """Treat the first line (max 100 chars) as title, segment the rest."""
        lines = text.split("\n", 1)
        title = lines[0].strip()[:100]
        paragraphs = self._segment_paragraphs(text)
        return ExtractedContent(
            title=title,
            full_text=text,
            paragraphs=paragraphs,
            source_url=None,
        )

    # ------------------------------------------------------------------ #
    #  PDF extraction
    # ------------------------------------------------------------------ #

    async def extract_pdf(self, file_path: str) -> ExtractedContent:
        """Extract text from every page of the PDF at *file_path*."""
        path = Path(file_path)
        pages_text: list[str] = []

        with pdfplumber.open(path) as pdf:
            for page in pdf.pages:
                page_text = page.extract_text()
                if page_text:
                    pages_text.append(page_text)

        full_text = "\n\n".join(pages_text)
        paragraphs = self._segment_paragraphs(full_text)
        return ExtractedContent(
            title=path.stem,
            full_text=full_text,
            paragraphs=paragraphs,
            source_url=None,
        )

    # ------------------------------------------------------------------ #
    #  Image / OCR extraction
    # ------------------------------------------------------------------ #

    async def extract_image(self, file_path: str) -> ExtractedContent:
        """Run OCR on the image at *file_path* (Chinese + English)."""
        path = Path(file_path)
        image = Image.open(path)
        full_text: str = pytesseract.image_to_string(image, lang="chi_sim+eng")
        paragraphs = self._segment_paragraphs(full_text)
        return ExtractedContent(
            title=path.stem,
            full_text=full_text,
            paragraphs=paragraphs,
            source_url=None,
        )
