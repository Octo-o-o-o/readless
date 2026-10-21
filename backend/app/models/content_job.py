"""Database-backed content import job queue."""

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, Text, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ContentJob(Base):
    """Queued import work for a single content item."""

    __tablename__ = "content_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    content_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("contents.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    user_id: Mapped[str] = mapped_column(PGUUID(as_uuid=False), nullable=False)
    source_type: Mapped[str] = mapped_column(String(20), nullable=False)
    body: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="queued",
        server_default="queued",
    )
    attempts: Mapped[int] = mapped_column(
        nullable=False,
        default=0,
        server_default="0",
    )
    scheduled_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    finished_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    __table_args__ = (
        Index(
            "ix_content_jobs_status_scheduled",
            "status",
            "scheduled_at",
        ),
        Index("ix_content_jobs_user_created", "user_id", "created_at"),
    )
