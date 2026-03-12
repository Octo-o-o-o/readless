"""Session issuance, refresh, and revocation primitives."""

import hashlib
import hmac
from datetime import UTC, datetime, timedelta
from uuid import UUID

from jwt import InvalidTokenError
from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth_utils import (
    create_access_token,
    create_refresh_token,
    verify_refresh_token,
)
from app.config import settings
from app.models.refresh_token import RefreshToken
from app.models.user import User, _to_utc


class SessionService:
    """Owns JWT session issuance and refresh-token persistence semantics."""

    def __init__(self, db: AsyncSession):
        self.db = db

    @staticmethod
    def hash_refresh_token(token: str) -> str:
        """Hash refresh token before storing in database."""
        return hmac.new(
            settings.jwt_secret_key.encode("utf-8"),
            token.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()

    async def issue_session(
        self,
        *,
        user: User,
        device_name: str | None = None,
        device_id: str | None = None,
        now: datetime | None = None,
    ) -> tuple[str, str]:
        """Issue access/refresh tokens and stage refresh token row for commit."""
        issued_at = now or datetime.now(UTC)
        user_id_str = str(user.id)
        access_token = create_access_token(user_id_str)
        refresh_token = create_refresh_token(user_id_str)

        refresh_token_row = RefreshToken(
            token=self.hash_refresh_token(refresh_token),
            user_id=user.id,
            expires_at=issued_at + timedelta(days=settings.refresh_token_expire_days),
            device_name=device_name,
            device_id=device_id,
            last_used_at=issued_at,
        )
        self.db.add(refresh_token_row)

        return access_token, refresh_token

    async def refresh_access_token(
        self,
        refresh_token_str: str,
        rotate_refresh_token: bool = False,
    ) -> tuple[str, str | None]:
        """Exchange refresh token for a new access token and optional rotated token."""
        try:
            payload = verify_refresh_token(refresh_token_str)
        except InvalidTokenError:
            raise ValueError("Invalid or expired session. Please log in again.")

        user_id_str = payload["sub"]
        hashed_refresh_token = self.hash_refresh_token(refresh_token_str)

        result = await self.db.execute(
            select(RefreshToken).where(
                or_(
                    RefreshToken.token == hashed_refresh_token,
                    RefreshToken.token == refresh_token_str,
                )
            )
        )
        token_record = result.scalars().first()

        if not token_record:
            raise ValueError("Your session has expired. Please log in again.")

        now = datetime.now(UTC)
        if _to_utc(token_record.expires_at) < now:
            raise ValueError("Your session has expired. Please log in again.")

        user_id = UUID(user_id_str)
        user_result = await self.db.execute(
            select(User).where(User.id == user_id, User.deleted_at.is_(None))
        )
        user = user_result.scalars().first()
        if not user:
            raise ValueError("Your session has expired. Please log in again.")

        token_record.last_used_at = now
        new_refresh_token: str | None = None
        if rotate_refresh_token:
            new_refresh_token = create_refresh_token(user_id_str)
            token_record.token = self.hash_refresh_token(new_refresh_token)

        await self.db.commit()
        return create_access_token(user_id_str), new_refresh_token

    async def revoke_all_sessions(self, user_id: UUID) -> None:
        """Delete all refresh-token rows for a user."""
        await self.db.execute(
            delete(RefreshToken).where(RefreshToken.user_id == user_id)
        )
