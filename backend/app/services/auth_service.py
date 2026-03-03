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

import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta
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
from app.models.refresh_token import EmailLoginCode, PasswordResetToken, RefreshToken
from app.models.user import User, _to_utc
from app.services.email_service import ResendEmailService


def _normalize_email(email: str) -> str:
    """Normalize email for lookups and uniqueness checks."""
    return email.strip().lower()


class AuthService:
    """Authentication service for user operations."""

    def __init__(self, db: AsyncSession):
        """
        Initialize auth service.

        Args:
            db: AsyncSession for database operations
        """
        self.db = db
        self.email_service = ResendEmailService()

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
        email = _normalize_email(email)

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
            raise ValueError(
                "An account with this email already exists."
                " Try logging in instead."
            )

        # Hash password
        password_hash = hash_password(password)

        # Generate email verification token
        verification_token = generate_verification_token()

        # Calculate trial expiry (7 days from now)
        now = datetime.now(UTC)
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
        email = _normalize_email(email)

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
        now = datetime.now(UTC)
        user.last_login_at = now

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

    def _generate_email_login_code(self) -> str:
        """Generate 6-digit one-time login code."""
        return f"{secrets.randbelow(1_000_000):06d}"

    def _hash_email_login_code(self, email: str, code: str) -> str:
        """Create deterministic hash for stored login code validation."""
        normalized_email = _normalize_email(email)
        payload = f"{normalized_email}:{code}:{settings.jwt_secret_key}"
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    async def send_email_login_code(self, email: str) -> None:
        """
        Send one-time email login code.

        Raises:
            ValueError: If sending too frequently or email delivery fails
        """
        normalized_email = _normalize_email(email)
        now = datetime.now(UTC)

        # Basic anti-spam: throttle resend interval per email.
        latest_result = await self.db.execute(
            select(EmailLoginCode)
            .where(EmailLoginCode.email == normalized_email)
            .order_by(EmailLoginCode.created_at.desc())
            .limit(1)
        )
        latest_code = latest_result.scalar_one_or_none()
        if latest_code:
            last_sent_seconds = (now - _to_utc(latest_code.created_at)).total_seconds()
            if last_sent_seconds < settings.email_login_code_resend_interval_seconds:
                raise ValueError("Code sent too frequently. Please wait and try again.")

        # Invalidate previous unused codes for the same email.
        await self.db.execute(
            update(EmailLoginCode)
            .where(
                EmailLoginCode.email == normalized_email,
                EmailLoginCode.used_at.is_(None),
            )
            .values(used_at=now)
        )

        code = self._generate_email_login_code()
        code_record = EmailLoginCode(
            email=normalized_email,
            code_hash=self._hash_email_login_code(normalized_email, code),
            expires_at=now + timedelta(
                minutes=settings.email_login_code_expire_minutes,
            ),
        )
        self.db.add(code_record)
        await self.db.commit()
        await self.db.refresh(code_record)

        try:
            await self.email_service.send_login_code(
                to_email=normalized_email, code=code,
            )
        except ValueError:
            await self.db.execute(
                delete(EmailLoginCode).where(EmailLoginCode.id == code_record.id)
            )
            await self.db.commit()
            raise

    async def verify_email_login_code(
        self,
        email: str,
        code: str,
        device_name: str | None = None,
        device_id: str | None = None,
    ) -> tuple[User, str, str, bool]:
        """
        Verify one-time code and issue JWT session.

        Returns:
            Tuple of (user, access_token, refresh_token, is_new_user)
        """
        normalized_email = _normalize_email(email)
        now = datetime.now(UTC)

        result = await self.db.execute(
            select(EmailLoginCode).where(
                EmailLoginCode.email == normalized_email,
                EmailLoginCode.used_at.is_(None),
                EmailLoginCode.expires_at >= now,
            ).order_by(EmailLoginCode.created_at.desc())
        )
        code_record = result.scalars().first()

        if not code_record:
            raise ValueError("Verification code is invalid or expired.")

        expected_hash = self._hash_email_login_code(normalized_email, code.strip())
        if not hmac.compare_digest(code_record.code_hash, expected_hash):
            code_record.attempts += 1
            if code_record.attempts >= 5:
                code_record.used_at = now
            await self.db.commit()
            raise ValueError("Verification code is invalid or expired.")

        code_record.used_at = now

        # Find existing user by email or create a new trial user.
        user_result = await self.db.execute(
            select(User).where(
                User.email == normalized_email,
                User.deleted_at.is_(None),
            )
        )
        user = user_result.scalars().first()
        is_new_user = False

        if not user:
            user = User(
                email=normalized_email,
                email_verified=True,
                subscription_tier="trial",
                trial_expires_at=now + timedelta(days=7),
                last_login_at=now,
            )
            self.db.add(user)
            is_new_user = True
            await self.db.flush()
        else:
            user.last_login_at = now
            user.email_verified = True

        access_token = create_access_token(str(user.id))
        refresh_token_str = create_refresh_token(str(user.id))

        refresh_token = RefreshToken(
            token=refresh_token_str,
            user_id=user.id,
            expires_at=now + timedelta(days=settings.refresh_token_expire_days),
            device_name=device_name,
            device_id=device_id,
            last_used_at=now,
        )
        self.db.add(refresh_token)
        await self.db.commit()
        await self.db.refresh(user)

        return user, access_token, refresh_token_str, is_new_user

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
        except InvalidTokenError:
            raise ValueError("Invalid or expired session. Please log in again.")

        user_id_str = payload["sub"]

        # Check token exists in database
        result = await self.db.execute(
            select(RefreshToken).where(RefreshToken.token == refresh_token_str)
        )
        token_record = result.scalars().first()

        if not token_record:
            raise ValueError("Your session has expired. Please log in again.")

        # Check token not expired (double-check DB expiry)
        now = datetime.now(UTC)
        if _to_utc(token_record.expires_at) < now:
            raise ValueError("Your session has expired. Please log in again.")

        # Check user still exists and not deleted
        user_id = UUID(user_id_str)
        result = await self.db.execute(
            select(User).where(User.id == user_id, User.deleted_at.is_(None))
        )
        user = result.scalars().first()

        if not user:
            raise ValueError("Your session has expired. Please log in again.")

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
        now = datetime.now(UTC)
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
        now = datetime.now(UTC)
        if reset_token.expires_at < now:
            raise ValueError(
                "Password reset link has expired."
                " Please request a new one."
            )

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
        now = datetime.now(UTC)
        user.deleted_at = now

        # Revoke all refresh tokens
        await self.db.execute(
            delete(RefreshToken).where(RefreshToken.user_id == user_id)
        )

        await self.db.commit()

    # ==================== Apple Sign In ====================

    async def apple_signin(
        self,
        identity_token: str,
        device_name: str | None = None,
        device_id: str | None = None
    ) -> tuple[User, str, str, bool]:
        """
        Apple Sign In - find or create user, generate tokens.

        Args:
            identity_token: Apple identity token (JWT)
            device_name: Optional device name for token tracking
            device_id: Optional device ID for token tracking

        Returns:
            Tuple of (user, access_token, refresh_token, is_new_user)

        Raises:
            HTTPException: If Apple token verification fails
                (from verify_apple_identity_token)
            ValueError: If database operation fails
        """
        from app.services.apple_auth import verify_apple_identity_token

        # Verify Apple identity token
        apple_data = await verify_apple_identity_token(identity_token)
        apple_id = apple_data["apple_id"]
        email = apple_data.get("email")
        email_verified = apple_data.get("email_verified", False)

        # Check if user exists
        result = await self.db.execute(
            select(User).where(User.apple_id == apple_id, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        is_new_user = False

        if not user:
            # Create new user
            now = datetime.now(UTC)
            user = User(
                apple_id=apple_id,
                email=email,
                email_verified=email_verified if email else False,
                subscription_tier="trial",
                trial_expires_at=now + timedelta(days=7),
            )
            self.db.add(user)
            is_new_user = True
        else:
            # Update last login
            user.last_login_at = datetime.now(UTC)

        await self.db.commit()
        await self.db.refresh(user)

        # Generate tokens
        user_id_str = str(user.id)
        access_token = create_access_token(user_id_str)
        refresh_token_str = create_refresh_token(user_id_str)

        # Store refresh token
        now = datetime.now(UTC)
        refresh_token = RefreshToken(
            token=refresh_token_str,
            user_id=user.id,
            expires_at=now + timedelta(days=settings.refresh_token_expire_days),
            device_name=device_name,
            device_id=device_id,
        )
        self.db.add(refresh_token)
        await self.db.commit()

        return user, access_token, refresh_token_str, is_new_user
