"""Content-Tag relationship model."""

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ContentTag(Base):
    """Many-to-many relationship between content and tags."""

    __tablename__ = "content_tags"

    content_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("contents.id", ondelete="CASCADE"),
        primary_key=True,
    )
    tag_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("user_tags.id", ondelete="CASCADE"),
        primary_key=True,
    )
    user_id: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        Index("idx_content_tags_tag_id", "tag_id"),
        Index("idx_content_tags_content_id", "content_id"),
        Index("idx_content_tags_user_id", "user_id"),
    )
