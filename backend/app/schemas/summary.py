"""Pydantic models for AI-generated summaries."""

from pydantic import BaseModel


class OutlinePoint(BaseModel):
    """A single outline point with source-paragraph anchors."""

    point: str
    anchors: list[str]
    detail: str | None = None


class ContentSummary(BaseModel):
    """Multi-level summary produced by the AI summarization service."""

    l0_summary: str
    l1_outline: list[OutlinePoint]
    tags: list[str]
    keywords: list[str]
