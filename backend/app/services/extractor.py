"""Content extraction service for URLs, raw text, PDFs, and images."""

from __future__ import annotations

import asyncio
import base64
import binascii
import io
import logging
import re
from dataclasses import dataclass, field
from functools import partial
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
        loop = asyncio.get_event_loop()
        downloaded = await loop.run_in_executor(None, trafilatura.fetch_url, url)
        body: str | None = None
        title: str | None = None

        if downloaded:
            body = await loop.run_in_executor(None, trafilatura.extract, downloaded)
            title = await loop.run_in_executor(
                None, partial(trafilatura.extract, downloaded, output_format="xmltei")
            )
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
        """Extract text from a PDF path or base64 payload."""
        path = self._coerce_existing_path(file_path)

        def _extract_from_pdf_handle(pdf_handle) -> list[str]:
            pages: list[str] = []
            with pdfplumber.open(pdf_handle) as pdf:
                for page in pdf.pages:
                    page_text = page.extract_text()
                    if page_text:
                        pages.append(page_text)
            return pages

        if path is not None:
            title = path.stem
            pdf_source: str | io.BytesIO = path.as_posix()
        else:
            pdf_bytes = self._decode_base64_payload(file_path)
            if pdf_bytes is None:
                raise ValueError("Invalid PDF payload: expected file path or base64")
            title = "Uploaded PDF"
            pdf_source = io.BytesIO(pdf_bytes)

        def _do_pdf() -> list[str]:
            return _extract_from_pdf_handle(pdf_source)

        pages_text = await asyncio.get_event_loop().run_in_executor(None, _do_pdf)
        full_text = "\n\n".join(pages_text)
        paragraphs = self._segment_paragraphs(full_text)
        return ExtractedContent(
            title=title,
            full_text=full_text,
            paragraphs=paragraphs,
            source_url=None,
        )

    # ------------------------------------------------------------------ #
    #  Image / OCR extraction
    # ------------------------------------------------------------------ #

    async def extract_image(self, file_path: str) -> ExtractedContent:
        """Run OCR on an image path or base64 payload (Chinese + English)."""
        path = self._coerce_existing_path(file_path)
        image_bytes = (
            None
            if path is not None
            else self._decode_base64_payload(file_path)
        )
        if path is None and image_bytes is None:
            raise ValueError("Invalid image payload: expected file path or base64")

        title = path.stem if path is not None else "Uploaded Image"

        def _do_ocr() -> str:
            if path is not None:
                with Image.open(path) as image:
                    return pytesseract.image_to_string(image, lang="chi_sim+eng")

            assert image_bytes is not None
            with Image.open(io.BytesIO(image_bytes)) as image:
                return pytesseract.image_to_string(image, lang="chi_sim+eng")

        full_text = await asyncio.get_event_loop().run_in_executor(None, _do_ocr)
        paragraphs = self._segment_paragraphs(full_text)
        return ExtractedContent(
            title=title,
            full_text=full_text,
            paragraphs=paragraphs,
            source_url=None,
        )

    @staticmethod
    def _coerce_existing_path(payload: str) -> Path | None:
        """Return payload as a path only when the path exists on disk."""
        try:
            path = Path(payload)
        except (OSError, ValueError):
            return None

        return path if path.exists() else None

    @staticmethod
    def _decode_base64_payload(payload: str) -> bytes | None:
        """Decode plain base64 or data-URI payloads."""
        normalized = payload.strip()
        if normalized.startswith("data:") and "," in normalized:
            _, normalized = normalized.split(",", 1)

        try:
            return base64.b64decode(normalized, validate=True)
        except (binascii.Error, ValueError):
            return None
