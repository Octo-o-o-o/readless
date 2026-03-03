"""Content model — stores ingested articles, PDFs, and other source material."""

from datetime import datetime

from sqlalchemy import (
    ARRAY,
    DateTime,
    Index,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, TSVECTOR, UUID as pgUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Content(Base):
    __tablename__ = "contents"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    source_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_type: Mapped[str] = mapped_column(String(20), nullable=False)
    source_app_name: Mapped[str | None] = mapped_column(
        String(100), nullable=True
    )
    source_app_bundle_id: Mapped[str | None] = mapped_column(
        String(200), nullable=True
    )
    channel: Mapped[str] = mapped_column(
        String(20), nullable=False, default="manual"
    )

    # AI-generated summaries
    l0_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    l1_outline: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    # Classification
    keywords: Mapped[list[str] | None] = mapped_column(
        ARRAY(String), nullable=True
    )
    # Note: tags are now in content_tags table (many-to-many with user_tags)

    # Language
    source_language: Mapped[str | None] = mapped_column(
        String(10), nullable=True
    )

    # Full text & search
    full_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    full_text_tsv: Mapped[str | None] = mapped_column(
        TSVECTOR, nullable=True
    )

    # Status & ownership
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="pending"
    )
    user_id: Mapped[str] = mapped_column(pgUUID(as_uuid=False), nullable=False)

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    __table_args__ = (
        Index("ix_contents_full_text_tsv", "full_text_tsv", postgresql_using="gin"),
        Index("ix_contents_keywords", "keywords", postgresql_using="gin"),
        Index("ix_contents_l1_outline", "l1_outline", postgresql_using="gin"),
        Index("ix_contents_user_created", "user_id", "created_at"),
    )
