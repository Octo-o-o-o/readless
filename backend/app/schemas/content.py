"""Pydantic models for content API requests and responses."""

import math
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, model_validator

from app.config import settings


class ContentCreateRequest(BaseModel):
    """Request body for creating new content."""

    source_type: Literal["url", "text", "pdf", "image"]
    body: str  # URL string, raw text, or base64-encoded file
    source_app_name: str | None = None
    source_app_bundle_id: str | None = None
    channel: str = "manual"

    @model_validator(mode="after")
    def validate_body_size(self) -> "ContentCreateRequest":
        body_length = len(self.body.strip())
        if body_length == 0:
            raise ValueError("Content body must not be empty.")

        if self.source_type == "url" and body_length > settings.content_max_url_length:
            raise ValueError(
                "URL import is too large."
                f" Maximum length is {settings.content_max_url_length} characters."
            )

        if self.source_type == "text" and body_length > settings.content_max_text_chars:
            raise ValueError(
                "Text import is too large."
                f" Maximum length is {settings.content_max_text_chars} characters."
            )

        if self.source_type in {"pdf", "image"}:
            max_encoded_chars = (
                math.ceil(settings.content_max_upload_bytes * 4 / 3) + 1_024
            )
            if body_length > max_encoded_chars:
                raise ValueError(
                    "Uploaded file is too large."
                    f" Maximum size is {settings.content_max_upload_bytes} bytes."
                )

        return self


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
