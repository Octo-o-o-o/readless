"""
Authentication service layer.

Provides high-level authentication operations:
- User registration with 7-day trial
- Login and token generation
- Token refresh
- Logout (revoke tokens)
- Email verification
- Password reset
- Account deletion (soft delete)

All database operations use AsyncSession.
Passwords are hashed using bcrypt (cost factor 12).
JWT tokens use HS256 with configurable expiry.
"""

from datetime import datetime, timedelta, timezone
from uuid import UUID

from jwt import InvalidTokenError
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth_utils import (
    create_access_token,
    create_refresh_token,
    generate_password_reset_token,
    generate_verification_token,
    hash_password,
    validate_password,
    verify_password,
    verify_refresh_token,
)
from app.config import settings
from app.models.refresh_token import PasswordResetToken, RefreshToken
from app.models.user import User


class AuthService:
    """Authentication service for user operations."""

    def __init__(self, db: AsyncSession):
        """
        Initialize auth service.

        Args:
            db: AsyncSession for database operations
        """
        self.db = db

    # ==================== User Registration ====================

    async def register_user(self, email: str, password: str) -> tuple[User, str]:
        """
        Register a new user with email/password.

        Creates user with:
        - Hashed password
        - 7-day trial (subscription_tier="trial")
        - Email verification token
        - Email not verified by default

        Args:
            email: User email address
            password: Plain text password (will be hashed)

        Returns:
            Tuple of (User, verification_token)

        Raises:
            ValueError: If email exists, password invalid, or DB error
        """
        # Validate password
        is_valid, error_msg = validate_password(password)
        if not is_valid:
            raise ValueError(error_msg)

        # Check if email already exists
        result = await self.db.execute(
            select(User).where(User.email == email, User.deleted_at.is_(None))
        )
        existing_user = result.scalars().first()
        if existing_user:
            raise ValueError("Email already registered")

        # Hash password
        password_hash = hash_password(password)

        # Generate email verification token
        verification_token = generate_verification_token()

        # Calculate trial expiry (7 days from now)
        now = datetime.now(timezone.utc)
        trial_expires = now + timedelta(days=7)

        # Create user
        user = User(
            email=email,
            password_hash=password_hash,
            subscription_tier="trial",
            trial_expires_at=trial_expires,
            email_verified=False,
            email_verification_token=verification_token,
        )

        self.db.add(user)
        await self.db.commit()
        await self.db.refresh(user)

        return user, verification_token

    # ==================== Login ====================

    async def login_user(
        self,
        email: str,
        password: str,
        device_name: str | None = None,
        device_id: str | None = None,
    ) -> tuple[User, str, str]:
        """
        Authenticate user and generate tokens.

        Args:
            email: User email address
            password: Plain text password
            device_name: Optional device name for token tracking
            device_id: Optional device ID for token tracking

        Returns:
            Tuple of (User, access_token, refresh_token)

        Raises:
            ValueError: If credentials invalid or user deleted
        """
        # Find user by email
        result = await self.db.execute(
            select(User).where(User.email == email, User.deleted_at.is_(None))
        )
        user = result.scalars().first()

        if not user:
            raise ValueError("Invalid email or password")

        # Verify password
        if not user.password_hash or not verify_password(password, user.password_hash):
            raise ValueError("Invalid email or password")

        # Update last login time
        now = datetime.now(timezone.utc)
        user.last_login_at = now
        await self.db.commit()

        # Generate tokens
        user_id_str = str(user.id)
        access_token = create_access_token(user_id_str)
        refresh_token_str = create_refresh_token(user_id_str)

        # Store refresh token
        expires_at = now + timedelta(days=settings.refresh_token_expire_days)
        refresh_token = RefreshToken(
            token=refresh_token_str,
            user_id=user.id,
            expires_at=expires_at,
            device_name=device_name,
            device_id=device_id,
            last_used_at=now,
        )
        self.db.add(refresh_token)
        await self.db.commit()

        return user, access_token, refresh_token_str

    # ==================== Token Refresh ====================

    async def refresh_access_token(self, refresh_token_str: str) -> str:
        """
        Exchange refresh token for new access token.

        Args:
            refresh_token_str: JWT refresh token string

        Returns:
            New access token string

        Raises:
            ValueError: If token invalid, expired, revoked, or user deleted
        """
        # Verify JWT signature and expiry
        try:
            payload = verify_refresh_token(refresh_token_str)
        except InvalidTokenError as e:
            raise ValueError(f"Invalid refresh token: {e}") from e

        user_id_str = payload["sub"]

        # Check token exists in database
        result = await self.db.execute(
            select(RefreshToken).where(RefreshToken.token == refresh_token_str)
        )
        token_record = result.scalars().first()

        if not token_record:
            raise ValueError("Refresh token not found or revoked")

        # Check token not expired (double-check DB expiry)
        now = datetime.now(timezone.utc)
        if token_record.expires_at < now:
            raise ValueError("Refresh token expired")

        # Check user still exists and not deleted
        user_id = UUID(user_id_str)
        result = await self.db.execute(
            select(User).where(User.id == user_id, User.deleted_at.is_(None))
        )
        user = result.scalars().first()

        if not user:
            raise ValueError("User not found")

        # Update last used time
        token_record.last_used_at = now
        await self.db.commit()

        # Generate new access token
        access_token = create_access_token(user_id_str)
        return access_token

    # ==================== Logout ====================

    async def logout_user(self, user_id: UUID) -> None:
        """
        Revoke all refresh tokens for a user (logout from all devices).

        Args:
            user_id: User UUID

        Raises:
            ValueError: If user not found
        """
        # Check user exists
        result = await self.db.execute(
            select(User).where(User.id == user_id, User.deleted_at.is_(None))
        )
        user = result.scalars().first()

        if not user:
            raise ValueError("User not found")

        # Delete all refresh tokens for this user
        await self.db.execute(
            delete(RefreshToken).where(RefreshToken.user_id == user_id)
        )
        await self.db.commit()

    # ==================== Email Verification ====================

    async def verify_email(self, token: str) -> User:
        """
        Verify user's email address using verification token.

        Args:
            token: Email verification token (from registration)

        Returns:
            User object with email_verified=True

        Raises:
            ValueError: If token invalid or user not found
        """
        # Find user by verification token
        result = await self.db.execute(
            select(User).where(
                User.email_verification_token == token,
                User.deleted_at.is_(None),
            )
        )
        user = result.scalars().first()

        if not user:
            raise ValueError("Invalid verification token")

        # Mark email as verified
        user.email_verified = True
        user.email_verification_token = None  # Clear token after use
        await self.db.commit()
        await self.db.refresh(user)

        return user

    async def resend_verification_email(self, email: str) -> str:
        """
        Generate new verification token for user.

        Args:
            email: User email address

        Returns:
            New verification token

        Raises:
            ValueError: If user not found or already verified
        """
        # Find user by email
        result = await self.db.execute(
            select(User).where(User.email == email, User.deleted_at.is_(None))
        )
        user = result.scalars().first()

        if not user:
            raise ValueError("User not found")

        if user.email_verified:
            raise ValueError("Email already verified")

        # Generate new token
        verification_token = generate_verification_token()
        user.email_verification_token = verification_token
        await self.db.commit()

        return verification_token

    # ==================== Password Reset ====================

    async def create_password_reset_token(self, email: str) -> str:
        """
        Create password reset token for user.

        Token expires after 1 hour.

        Args:
            email: User email address

        Returns:
            Password reset token string

        Raises:
            ValueError: If user not found
        """
        # Find user by email
        result = await self.db.execute(
            select(User).where(User.email == email, User.deleted_at.is_(None))
        )
        user = result.scalars().first()

        if not user:
            raise ValueError("User not found")

        # Generate token
        token = generate_password_reset_token()

        # Calculate expiry (1 hour from now)
        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(hours=1)

        # Store token
        reset_token = PasswordResetToken(
            user_id=user.id,
            token=token,
            expires_at=expires_at,
        )
        self.db.add(reset_token)
        await self.db.commit()

        return token

    async def reset_password(self, token: str, new_password: str) -> User:
        """
        Reset user password using reset token.

        Also revokes all refresh tokens (logout from all devices).

        Args:
            token: Password reset token
            new_password: New plain text password (will be hashed)

        Returns:
            User object with updated password

        Raises:
            ValueError: If token invalid, expired, or password invalid
        """
        # Validate new password
        is_valid, error_msg = validate_password(new_password)
        if not is_valid:
            raise ValueError(error_msg)

        # Find token
        result = await self.db.execute(
            select(PasswordResetToken).where(
                PasswordResetToken.token == token,
                PasswordResetToken.used_at.is_(None),
            )
        )
        reset_token = result.scalars().first()

        if not reset_token:
            raise ValueError("Invalid or already used reset token")

        # Check token not expired
        now = datetime.now(timezone.utc)
        if reset_token.expires_at < now:
            raise ValueError("Reset token expired")

        # Find user
        result = await self.db.execute(
            select(User).where(
                User.id == reset_token.user_id,
                User.deleted_at.is_(None),
            )
        )
        user = result.scalars().first()

        if not user:
            raise ValueError("User not found")

        # Update password
        user.password_hash = hash_password(new_password)

        # Mark token as used
        reset_token.used_at = now

        # Revoke all refresh tokens (logout from all devices)
        await self.db.execute(
            delete(RefreshToken).where(RefreshToken.user_id == user.id)
        )

        await self.db.commit()
        await self.db.refresh(user)

        return user

    # ==================== Account Deletion ====================

    async def delete_account(self, user_id: UUID) -> None:
        """
        Soft delete user account.

        Sets deleted_at timestamp and revokes all refresh tokens.

        Args:
            user_id: User UUID

        Raises:
            ValueError: If user not found or already deleted
        """
        # Find user
        result = await self.db.execute(
            select(User).where(User.id == user_id, User.deleted_at.is_(None))
        )
        user = result.scalars().first()

        if not user:
            raise ValueError("User not found")

        # Soft delete user
        now = datetime.now(timezone.utc)
        user.deleted_at = now

        # Revoke all refresh tokens
        await self.db.execute(
            delete(RefreshToken).where(RefreshToken.user_id == user_id)
        )

        await self.db.commit()
