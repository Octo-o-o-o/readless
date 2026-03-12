"""User model for authentication and subscription management."""

from datetime import UTC, datetime
from enum import StrEnum
from uuid import UUID

from sqlalchemy import Boolean, CheckConstraint, DateTime, String, Text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.database import Base


def _to_utc(dt: datetime) -> datetime:
    """Normalize datetimes to UTC, handling naive values from SQLite/tests."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


class SubscriptionTier(StrEnum):
    """Subscription tier enum."""
    TRIAL = "trial"
    BASIC = "basic"
    PRO = "pro"
    EXPIRED = "expired"


class User(Base):
    """User model with JWT auth and subscription support."""

    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint(
            "email IS NOT NULL OR apple_id IS NOT NULL",
            name="user_identity_check",
        ),
    )

    # Primary key
    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )

    # Authentication
    email: Mapped[str | None] = mapped_column(String(255), unique=True)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    apple_id: Mapped[str | None] = mapped_column(String(255), unique=True)

    # Subscription
    subscription_tier: Mapped[str] = mapped_column(String(20), default="trial")
    trial_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    subscription_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
    )

    # Apple receipt tracking
    apple_original_transaction_id: Mapped[str | None] = mapped_column(String(255))
    apple_receipt_data: Mapped[str | None] = mapped_column(Text)
    subscription_auto_renew_enabled: Mapped[bool | None] = mapped_column(Boolean)

    # Email verification
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    email_verification_token: Mapped[str | None] = mapped_column(String(64))

    # Audit
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    def is_subscription_active(self) -> bool:
        """Check if user has active subscription or trial."""
        now = datetime.now(UTC)

        if self.subscription_expires_at and _to_utc(self.subscription_expires_at) > now:
            return True

        if self.trial_expires_at and _to_utc(self.trial_expires_at) > now:
            return True

        return False

    def get_effective_tier(self) -> str:
        """Get current effective subscription tier."""
        now = datetime.now(UTC)

        # Check paid subscription first
        if self.subscription_expires_at and _to_utc(self.subscription_expires_at) > now:
            return self.subscription_tier

        # Check trial
        if self.trial_expires_at and _to_utc(self.trial_expires_at) > now:
            return "trial"

        return "expired"
