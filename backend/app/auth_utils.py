"""
JWT and password utilities for authentication.

Provides:
- Password hashing and verification using bcrypt (cost factor 12)
- Password validation against complexity requirements
- JWT access token generation and verification (HS256, 15 min expiry)
- JWT refresh token generation and verification (HS256, 30 day expiry)
- Secure token generation for email verification and password reset
"""

import secrets
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from jwt import InvalidTokenError

from app.config import settings


# -------------------- Password Hashing --------------------


def hash_password(password: str) -> str:
    """
    Hash a password using bcrypt with cost factor 12.

    Args:
        password: Plain text password

    Returns:
        Hashed password as string (bcrypt automatically includes salt)

    Example:
        >>> hashed = hash_password("MySecurePass123")
        >>> verify_password("MySecurePass123", hashed)
        True
    """
    password_bytes = password.encode("utf-8")
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a password against its bcrypt hash.

    Args:
        plain_password: Plain text password to verify
        hashed_password: Bcrypt hash to check against

    Returns:
        True if password matches, False otherwise

    Example:
        >>> hashed = hash_password("correct")
        >>> verify_password("correct", hashed)
        True
        >>> verify_password("wrong", hashed)
        False
    """
    password_bytes = plain_password.encode("utf-8")
    hashed_bytes = hashed_password.encode("utf-8")
    return bcrypt.checkpw(password_bytes, hashed_bytes)


# -------------------- Password Validation --------------------


def validate_password(password: str) -> tuple[bool, str | None]:
    """
    Validate password against complexity requirements.

    Requirements (from config.py):
    - Minimum length (default: 8 characters)
    - At least one uppercase letter (if REQUIRE_PASSWORD_UPPERCASE=True)
    - At least one lowercase letter (if REQUIRE_PASSWORD_LOWERCASE=True)
    - At least one digit (if REQUIRE_PASSWORD_DIGIT=True)

    Args:
        password: Plain text password to validate

    Returns:
        Tuple of (is_valid, error_message)
        - (True, None) if valid
        - (False, "error message") if invalid

    Example:
        >>> validate_password("Test123")
        (False, "Password must be at least 8 characters")
        >>> validate_password("Test1234")
        (True, None)
    """
    if len(password) < settings.min_password_length:
        return (
            False,
            f"Password must be at least {settings.min_password_length} characters",
        )

    if settings.require_password_uppercase and not any(c.isupper() for c in password):
        return False, "Password must contain at least one uppercase letter"

    if settings.require_password_lowercase and not any(c.islower() for c in password):
        return False, "Password must contain at least one lowercase letter"

    if settings.require_password_digit and not any(c.isdigit() for c in password):
        return False, "Password must contain at least one digit"

    return True, None


# -------------------- JWT Token Generation --------------------


def create_access_token(user_id: str) -> str:
    """
    Create a JWT access token for a user.

    Token contains:
    - sub: user_id
    - exp: expiration time (15 minutes from now)
    - iat: issued at time (current time)
    - type: "access"

    Args:
        user_id: UUID string of the user

    Returns:
        JWT token string

    Example:
        >>> token = create_access_token("user123")
        >>> payload = verify_access_token(token)
        >>> payload["sub"] == "user123"
        True
    """
    now = datetime.now(timezone.utc)
    expires_delta = timedelta(minutes=settings.access_token_expire_minutes)
    expire = now + expires_delta

    payload = {
        "sub": user_id,
        "exp": expire,
        "iat": now,
        "type": "access",
    }

    token = jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
    return token


def create_refresh_token(user_id: str) -> str:
    """
    Create a JWT refresh token for a user.

    Token contains:
    - sub: user_id
    - exp: expiration time (30 days from now)
    - iat: issued at time (current time)
    - type: "refresh"

    Args:
        user_id: UUID string of the user

    Returns:
        JWT token string

    Example:
        >>> token = create_refresh_token("user123")
        >>> payload = verify_refresh_token(token)
        >>> payload["sub"] == "user123"
        True
    """
    now = datetime.now(timezone.utc)
    expires_delta = timedelta(days=settings.refresh_token_expire_days)
    expire = now + expires_delta

    payload = {
        "sub": user_id,
        "exp": expire,
        "iat": now,
        "type": "refresh",
    }

    token = jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
    return token


# -------------------- JWT Token Verification --------------------


def verify_access_token(token: str) -> dict:
    """
    Verify a JWT access token and return its payload.

    Args:
        token: JWT token string

    Returns:
        Decoded token payload dict with keys: sub, exp, iat, type

    Raises:
        InvalidTokenError: If token is invalid, expired, or wrong type

    Example:
        >>> token = create_access_token("user123")
        >>> payload = verify_access_token(token)
        >>> payload["sub"]
        'user123'
    """
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
        )

        # Verify token type
        if payload.get("type") != "access":
            raise InvalidTokenError("Invalid token type")

        return payload

    except InvalidTokenError as e:
        raise InvalidTokenError(f"Invalid access token: {e}") from e


def verify_refresh_token(token: str) -> dict:
    """
    Verify a JWT refresh token and return its payload.

    Args:
        token: JWT token string

    Returns:
        Decoded token payload dict with keys: sub, exp, iat, type

    Raises:
        InvalidTokenError: If token is invalid, expired, or wrong type

    Example:
        >>> token = create_refresh_token("user123")
        >>> payload = verify_refresh_token(token)
        >>> payload["sub"]
        'user123'
    """
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
        )

        # Verify token type
        if payload.get("type") != "refresh":
            raise InvalidTokenError("Invalid token type")

        return payload

    except InvalidTokenError as e:
        raise InvalidTokenError(f"Invalid refresh token: {e}") from e


# -------------------- Secure Token Generation --------------------


def generate_verification_token() -> str:
    """
    Generate a secure random token for email verification.

    Uses secrets.token_urlsafe() for cryptographically strong randomness.
    Token is URL-safe (no special characters).

    Returns:
        32-character URL-safe token string

    Example:
        >>> token = generate_verification_token()
        >>> len(token) == 32
        True
    """
    return secrets.token_urlsafe(32)


def generate_password_reset_token() -> str:
    """
    Generate a secure random token for password reset.

    Uses secrets.token_urlsafe() for cryptographically strong randomness.
    Token is URL-safe (no special characters).

    Returns:
        32-character URL-safe token string

    Example:
        >>> token = generate_password_reset_token()
        >>> len(token) == 32
        True
    """
    return secrets.token_urlsafe(32)
