"""
JWT and password utilities for authentication.

Provides:
- Password hashing and verification using bcrypt (cost factor 12)
- Password validation against complexity requirements
- JWT access/refresh token generation and verification (HS256)
- Secure token generation for email verification and password reset
"""

import secrets
from datetime import UTC, datetime, timedelta

import bcrypt
import jwt
from jwt import InvalidTokenError

from app.config import settings

# -------------------- Password Hashing --------------------


def hash_password(password: str) -> str:
    """Hash a password using bcrypt with cost factor 12."""
    password_bytes = password.encode("utf-8")
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its bcrypt hash."""
    return bcrypt.checkpw(
        plain_password.encode("utf-8"),
        hashed_password.encode("utf-8"),
    )


# -------------------- Password Validation --------------------


def validate_password(password: str) -> tuple[bool, str | None]:
    """
    Validate password against complexity requirements from settings.

    Returns:
        Tuple of (is_valid, error_message). Error message is None when valid.
    """
    requirements = []

    if len(password) < settings.min_password_length:
        requirements.append(f"at least {settings.min_password_length} characters")

    if settings.require_password_uppercase and not any(c.isupper() for c in password):
        requirements.append("one uppercase letter")

    if settings.require_password_lowercase and not any(c.islower() for c in password):
        requirements.append("one lowercase letter")

    if settings.require_password_digit and not any(c.isdigit() for c in password):
        requirements.append("one number")

    if not requirements:
        return True, None

    if len(requirements) == 1:
        return False, f"Password must include {requirements[0]}."

    requirements_str = ", ".join(requirements[:-1]) + f", and {requirements[-1]}"
    return False, f"Password must include {requirements_str}."


# -------------------- JWT Token Generation --------------------


def _create_token(user_id: str, token_type: str, expires_delta: timedelta) -> str:
    """Create a JWT token with the given type and expiration."""
    now = datetime.now(UTC)
    payload = {
        "sub": user_id,
        "exp": now + expires_delta,
        "iat": now,
        "jti": secrets.token_urlsafe(16),
        "type": token_type,
    }
    return jwt.encode(
        payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm
    )


def create_access_token(user_id: str) -> str:
    """Create a short-lived JWT access token (15 min default)."""
    return _create_token(
        user_id, "access", timedelta(minutes=settings.access_token_expire_minutes)
    )


def create_refresh_token(user_id: str) -> str:
    """Create a long-lived JWT refresh token (30 day default)."""
    return _create_token(
        user_id, "refresh", timedelta(days=settings.refresh_token_expire_days)
    )


# -------------------- JWT Token Verification --------------------


def _verify_token(token: str, expected_type: str) -> dict:
    """Decode and verify a JWT token, ensuring the correct type claim."""
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
        )

        if payload.get("type") != expected_type:
            raise InvalidTokenError("Invalid token type")

        return payload

    except InvalidTokenError as e:
        raise InvalidTokenError(f"Invalid {expected_type} token: {e}") from e


def verify_access_token(token: str) -> dict:
    """Verify a JWT access token and return its payload."""
    return _verify_token(token, "access")


def verify_refresh_token(token: str) -> dict:
    """Verify a JWT refresh token and return its payload."""
    return _verify_token(token, "refresh")


# -------------------- Secure Token Generation --------------------


def generate_secure_token() -> str:
    """Generate a cryptographically secure URL-safe random token."""
    return secrets.token_urlsafe(32)


# Keep descriptive aliases for call-site clarity
generate_verification_token = generate_secure_token
generate_password_reset_token = generate_secure_token
