"""Paragraph model — stores individual paragraphs belonging to a Content."""

from sqlalchemy import (
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import TSVECTOR
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Paragraph(Base):
    __tablename__ = "paragraphs"

    id: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True
    )
    content_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("contents.id", ondelete="CASCADE"),
        nullable=False,
    )
    anchor_id: Mapped[str] = mapped_column(String(20), nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    full_text_tsv: Mapped[str | None] = mapped_column(
        TSVECTOR, nullable=True
    )

    __table_args__ = (
        Index("ix_paragraphs_content_anchor", "content_id", "anchor_id"),
        Index(
            "ix_paragraphs_full_text_tsv",
            "full_text_tsv",
            postgresql_using="gin",
        ),
    )
