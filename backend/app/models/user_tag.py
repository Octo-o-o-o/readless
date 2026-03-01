"""User tag model — stores user's tag library."""

from datetime import datetime

from sqlalchemy import DateTime, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserTag(Base):
    """User tag model with logical deletion support."""

    __tablename__ = "user_tags"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(100), nullable=False)
    tag_name: Mapped[str] = mapped_column(String(50), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        Index(
            "idx_user_tags_user_id",
            "user_id",
            postgresql_where="deleted_at IS NULL",
        ),
        Index("idx_user_tags_deleted_at", "deleted_at"),
        Index(
            "uq_user_tags_user_tag",
            "user_id",
            "tag_name",
            unique=True,
            postgresql_where="deleted_at IS NULL",
        ),
    )
