"""Pydantic models for content API requests and responses."""

from datetime import datetime

from pydantic import BaseModel


class ContentCreateRequest(BaseModel):
    """Request body for creating new content."""

    source_type: str  # url / text / pdf / image
    body: str  # URL string, raw text, or base64-encoded file
    source_app_name: str | None = None
    source_app_bundle_id: str | None = None
    channel: str = "manual"


class ContentListItemResponse(BaseModel):
    """Lightweight response model for content list items."""

    id: str
    title: str
    source_url: str | None
    source_type: str
    source_app_name: str | None
    source_app_bundle_id: str | None = None
    source_language: str | None = None
    l0_summary: str | None
    l1_outline: list[dict] | None = None
    tags: list[str] | None
    status: str
    created_at: datetime
    updated_at: datetime | None = None
    podcast_url: str | None = None


class ContentResponse(ContentListItemResponse):
    """Detailed response model for a single content item."""

    full_text: str | None = None  # For local search sync


class ContentStatusResponse(BaseModel):
    """Minimal response model for polling content processing state."""

    id: str
    status: str
    updated_at: datetime | None = None
    l0_summary: str | None = None
    processing_error: str | None = None


class ExpandRequest(BaseModel):
    """Request body for expanding an outline point."""

    point_index: int


class FollowUpRequest(BaseModel):
    """Request body for asking a follow-up question."""

    question: str


class TextResponse(BaseModel):
    """Simple text response."""

    text: str
