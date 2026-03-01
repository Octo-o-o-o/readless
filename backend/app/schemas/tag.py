"""Pydantic models for tag API requests and responses."""

from datetime import datetime
from pydantic import BaseModel, Field


class UserTagResponse(BaseModel):
    """Response model for user tag."""

    id: int
    tag_name: str
    content_count: int = Field(description="Number of content items with this tag")
    created_at: datetime


class TagCreateRequest(BaseModel):
    """Request body for creating a tag."""

    tag_name: str = Field(min_length=1, max_length=50)


class ContentTagsUpdateRequest(BaseModel):
    """Request body for updating content tags."""

    tag_names: list[str] = Field(description="Complete list of tag names for this content")
