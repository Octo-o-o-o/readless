# JWT Authentication + App Store Subscription Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Clerk authentication with custom JWT auth (Email/Password + Apple Sign In) and integrate App Store in-app purchases for subscription management.

**Architecture:** Backend implements JWT generation/verification, password hashing (bcrypt), Apple identity token verification, and StoreKit receipt verification. macOS client uses AuthService for session management (Keychain storage) and StoreManager for StoreKit 2 purchases. LocalDatabase adds user_id for multi-user cache isolation.

**Tech Stack:** Backend: FastAPI, PostgreSQL, PyJWT, bcrypt, SQLAdmin, Resend. macOS: SwiftUI, StoreKit 2, AuthenticationServices, Keychain, GRDB.

**Estimated Time:** 8 days (8 phases)

---

## Phase 1: Backend Auth Foundation (2 days)

### Task 1.1: Database Schema - Users Table

**Files:**
- Create: `backend/alembic/versions/004_add_users_table.py`
- Modify: `backend/app/models/__init__.py`
- Create: `backend/app/models/user.py`

**Step 1: Create Alembic migration for users table**

```python
# backend/alembic/versions/004_add_users_table.py
"""add users table

Revision ID: 004
Revises: 003
Create Date: 2026-03-02

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '004'
down_revision = '003'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'users',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('email', sa.String(255), unique=True, nullable=True),
        sa.Column('password_hash', sa.String(255), nullable=True),
        sa.Column('apple_id', sa.String(255), unique=True, nullable=True),

        sa.Column('subscription_tier', sa.String(20), nullable=False, server_default='trial'),
        sa.Column('trial_expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('subscription_expires_at', sa.DateTime(timezone=True), nullable=True),

        sa.Column('apple_original_transaction_id', sa.String(255), nullable=True),
        sa.Column('apple_receipt_data', sa.Text, nullable=True),

        sa.Column('email_verified', sa.Boolean, server_default='false'),
        sa.Column('email_verification_token', sa.String(64), nullable=True),

        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('last_login_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),

        sa.CheckConstraint('email IS NOT NULL OR apple_id IS NOT NULL', name='user_identity_check')
    )

    op.create_index('idx_users_email', 'users', ['email'])
    op.create_index('idx_users_apple_id', 'users', ['apple_id'])
    op.create_index('idx_users_email_active', 'users', ['email'], postgresql_where=sa.text('deleted_at IS NULL'), unique=True)
    op.create_index('idx_users_apple_id_active', 'users', ['apple_id'], postgresql_where=sa.text('deleted_at IS NULL'), unique=True)


def downgrade():
    op.drop_table('users')
```

**Step 2: Create User SQLAlchemy model**

```python
# backend/app/models/user.py
"""User model for authentication and subscription management."""

from datetime import datetime
from enum import Enum
from uuid import UUID

from sqlalchemy import Boolean, CheckConstraint, DateTime, String, Text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.database import Base


class SubscriptionTier(str, Enum):
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
            name="user_identity_check"
        ),
    )

    # Primary key
    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())

    # Authentication
    email: Mapped[str | None] = mapped_column(String(255), unique=True)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    apple_id: Mapped[str | None] = mapped_column(String(255), unique=True)

    # Subscription
    subscription_tier: Mapped[str] = mapped_column(String(20), default="trial")
    trial_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    subscription_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Apple receipt tracking
    apple_original_transaction_id: Mapped[str | None] = mapped_column(String(255))
    apple_receipt_data: Mapped[str | None] = mapped_column(Text)

    # Email verification
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    email_verification_token: Mapped[str | None] = mapped_column(String(64))

    # Audit
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    def is_subscription_active(self) -> bool:
        """Check if user has active subscription or trial."""
        now = datetime.utcnow()

        if self.subscription_expires_at and self.subscription_expires_at > now:
            return True

        if self.trial_expires_at and self.trial_expires_at > now:
            return True

        return False

    def get_effective_tier(self) -> str:
        """Get current effective subscription tier."""
        now = datetime.utcnow()

        # Check paid subscription first
        if self.subscription_expires_at and self.subscription_expires_at > now:
            return self.subscription_tier

        # Check trial
        if self.trial_expires_at and self.trial_expires_at > now:
            return "trial"

        return "expired"
```

**Step 3: Export User model**

```python
# backend/app/models/__init__.py
# Add to existing imports:
from app.models.user import User, SubscriptionTier

__all__ = [
    # ... existing exports ...
    "User",
    "SubscriptionTier",
]
```

**Step 4: Run migration**

```bash
cd backend
alembic upgrade head
```

Expected output: `INFO [alembic.runtime.migration] Running upgrade 003 -> 004, add users table`

**Step 5: Commit**

```bash
git add backend/alembic/versions/004_add_users_table.py backend/app/models/user.py backend/app/models/__init__.py
git commit -m "feat(backend): add users table and User model

Add User model with JWT auth support:
- Email + password authentication
- Apple Sign In support (apple_id)
- Subscription tier management (trial/basic/pro)
- Soft deletion (deleted_at) for Apple compliance
- Email verification support

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 1.2: Database Schema - Refresh Tokens Table

**Files:**
- Create: `backend/alembic/versions/005_add_refresh_tokens.py`
- Create: `backend/app/models/refresh_token.py`
- Modify: `backend/app/models/__init__.py`

**Step 1: Create Alembic migration**

```python
# backend/alembic/versions/005_add_refresh_tokens.py
"""add refresh_tokens table

Revision ID: 005
Revises: 004
Create Date: 2026-03-02

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '005'
down_revision = '004'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'refresh_tokens',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('token', sa.String(255), unique=True, nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('last_used_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('device_name', sa.String(255), nullable=True),
        sa.Column('device_id', sa.String(255), nullable=True),
    )

    op.create_index('idx_refresh_tokens_user', 'refresh_tokens', ['user_id'])
    op.create_index('idx_refresh_tokens_expires', 'refresh_tokens', ['expires_at'])

    # Password reset tokens table
    op.create_table(
        'password_reset_tokens',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('token', sa.String(64), unique=True, nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('used_at', sa.DateTime(timezone=True), nullable=True),
    )

    op.create_index('idx_password_reset_user', 'password_reset_tokens', ['user_id'])


def downgrade():
    op.drop_table('password_reset_tokens')
    op.drop_table('refresh_tokens')
```

**Step 2: Create RefreshToken model**

```python
# backend/app/models/refresh_token.py
"""Refresh token models for JWT authentication."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.database import Base


class RefreshToken(Base):
    """Refresh token for long-lived authentication."""

    __tablename__ = "refresh_tokens"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    token: Mapped[str] = mapped_column(String(255), unique=True)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))

    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    device_name: Mapped[str | None] = mapped_column(String(255))
    device_id: Mapped[str | None] = mapped_column(String(255))


class PasswordResetToken(Base):
    """Short-lived token for password reset."""

    __tablename__ = "password_reset_tokens"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid())
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    token: Mapped[str] = mapped_column(String(64), unique=True)

    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
```

**Step 3: Export models**

```python
# backend/app/models/__init__.py
# Add:
from app.models.refresh_token import RefreshToken, PasswordResetToken

__all__ = [
    # ... existing ...
    "RefreshToken",
    "PasswordResetToken",
]
```

**Step 4: Run migration**

```bash
cd backend
alembic upgrade head
```

**Step 5: Commit**

```bash
git add backend/alembic/versions/005_add_refresh_tokens.py backend/app/models/refresh_token.py backend/app/models/__init__.py
git commit -m "feat(backend): add refresh token and password reset tables

Add support for:
- Long-lived refresh tokens (30 days, revocable)
- Device tracking (device_name, device_id)
- Password reset tokens (15 min expiry)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 1.3: Migrate Existing Tables to UUID user_id

**Files:**
- Create: `backend/alembic/versions/006_migrate_user_id_to_uuid.py`

**Step 1: Create migration to update existing tables**

```python
# backend/alembic/versions/006_migrate_user_id_to_uuid.py
"""migrate user_id to uuid and add foreign keys

Revision ID: 006
Revises: 005
Create Date: 2026-03-02

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '006'
down_revision = '005'
branch_labels = None
depends_on = None


def upgrade():
    # 1. Truncate tables (no production data yet)
    op.execute("TRUNCATE TABLE content_tags, user_tags, paragraphs, podcasts, channels, content CASCADE")

    # 2. Alter user_id columns to UUID
    op.alter_column('content', 'user_id',
                   existing_type=sa.String(),
                   type_=postgresql.UUID(as_uuid=True),
                   postgresql_using='user_id::uuid',
                   nullable=False)

    op.alter_column('user_tags', 'user_id',
                   existing_type=sa.String(),
                   type_=postgresql.UUID(as_uuid=True),
                   postgresql_using='user_id::uuid',
                   nullable=False)

    op.alter_column('content_tags', 'user_id',
                   existing_type=sa.String(),
                   type_=postgresql.UUID(as_uuid=True),
                   postgresql_using='user_id::uuid',
                   nullable=False)

    # 3. Add foreign key constraints
    op.create_foreign_key(
        'fk_content_user', 'content', 'users',
        ['user_id'], ['id'],
        ondelete='CASCADE'
    )

    op.create_foreign_key(
        'fk_user_tags_user', 'user_tags', 'users',
        ['user_id'], ['id'],
        ondelete='CASCADE'
    )

    op.create_foreign_key(
        'fk_content_tags_user', 'content_tags', 'users',
        ['user_id'], ['id'],
        ondelete='CASCADE'
    )


def downgrade():
    op.drop_constraint('fk_content_tags_user', 'content_tags', type_='foreignkey')
    op.drop_constraint('fk_user_tags_user', 'user_tags', type_='foreignkey')
    op.drop_constraint('fk_content_user', 'content', type_='foreignkey')

    op.alter_column('content_tags', 'user_id',
                   existing_type=postgresql.UUID(as_uuid=True),
                   type_=sa.String(),
                   nullable=False)

    op.alter_column('user_tags', 'user_id',
                   existing_type=postgresql.UUID(as_uuid=True),
                   type_=sa.String(),
                   nullable=False)

    op.alter_column('content', 'user_id',
                   existing_type=postgresql.UUID(as_uuid=True),
                   type_=sa.String(),
                   nullable=False)
```

**Step 2: Run migration**

```bash
cd backend
alembic upgrade head
```

**Step 3: Commit**

```bash
git add backend/alembic/versions/006_migrate_user_id_to_uuid.py
git commit -m "feat(backend): migrate user_id to UUID with foreign keys

Migrate content, user_tags, content_tags to use UUID user_id
with CASCADE delete foreign keys to users table.

Truncates existing data (no production users yet).

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 1.4: JWT Utilities and Config

**Files:**
- Modify: `backend/app/config.py`
- Create: `backend/app/auth_utils.py`
- Modify: `backend/pyproject.toml` (add dependencies)

**Step 1: Add dependencies to pyproject.toml**

```toml
# backend/pyproject.toml
# Add to [project.dependencies]:
dependencies = [
    # ... existing ...
    "python-jose[cryptography]>=3.3.0",
    "bcrypt>=4.1.0",
    "pyjwt>=2.8.0",
    "cryptography>=42.0.0",
]
```

**Step 2: Install dependencies**

```bash
cd backend
pip install -e .
```

**Step 3: Update config with JWT settings**

```python
# backend/app/config.py
# Add to Settings class:

class Settings(BaseSettings):
    # ... existing fields ...

    # JWT Configuration
    JWT_SECRET_KEY: str = Field(..., min_length=32)
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Password Policy
    MIN_PASSWORD_LENGTH: int = 8
    REQUIRE_PASSWORD_UPPERCASE: bool = True
    REQUIRE_PASSWORD_LOWERCASE: bool = True
    REQUIRE_PASSWORD_DIGIT: bool = True

    # Apple Configuration
    APPLE_BUNDLE_ID: str = "com.readless.app"

    # Resend (Email)
    RESEND_API_KEY: str = ""
    RESEND_FROM_EMAIL: str = "Readless <noreply@readless.cc>"

    # Admin
    ADMIN_TOKEN: str = Field(..., min_length=32)

    # Development: Disable auth for testing
    DISABLE_AUTH: bool = False
```

**Step 4: Create auth utilities**

```python
# backend/app/auth_utils.py
"""Authentication utilities for JWT and password management."""

import secrets
from datetime import datetime, timedelta
from typing import Any

import bcrypt
import jwt
from fastapi import HTTPException

from app.config import settings


# ============ Password Hashing ============

def hash_password(password: str) -> str:
    """Hash password using bcrypt (cost factor 12)."""
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify password against bcrypt hash."""
    return bcrypt.checkpw(
        plain_password.encode('utf-8'),
        hashed_password.encode('utf-8')
    )


# ============ Password Validation ============

def validate_password(password: str) -> tuple[bool, str]:
    """
    Validate password against policy.
    Returns (is_valid, error_message).
    """
    if len(password) < settings.MIN_PASSWORD_LENGTH:
        return False, f"Password must be at least {settings.MIN_PASSWORD_LENGTH} characters"

    if settings.REQUIRE_PASSWORD_UPPERCASE and not any(c.isupper() for c in password):
        return False, "Password must contain at least one uppercase letter"

    if settings.REQUIRE_PASSWORD_LOWERCASE and not any(c.islower() for c in password):
        return False, "Password must contain at least one lowercase letter"

    if settings.REQUIRE_PASSWORD_DIGIT and not any(c.isdigit() for c in password):
        return False, "Password must contain at least one digit"

    return True, ""


# ============ JWT Generation ============

def create_access_token(user_id: str, email: str | None, subscription_tier: str) -> str:
    """Create access token (15 minutes)."""
    now = datetime.utcnow()
    expires = now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

    payload = {
        "sub": user_id,
        "email": email,
        "subscription_tier": subscription_tier,
        "exp": expires,
        "iat": now,
        "jti": secrets.token_urlsafe(16),
    }

    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token() -> str:
    """Create refresh token (random UUID)."""
    return secrets.token_urlsafe(32)


# ============ JWT Verification ============

def verify_access_token(token: str) -> dict[str, Any]:
    """
    Verify and decode access token.
    Raises HTTPException on invalid/expired token.
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}")


# ============ Token Generation ============

def generate_verification_token() -> str:
    """Generate email verification token."""
    return secrets.token_urlsafe(32)


def generate_password_reset_token() -> str:
    """Generate password reset token."""
    return secrets.token_urlsafe(32)
```

**Step 5: Update .env with JWT secret**

```bash
# Generate a secure JWT secret
python3 -c "import secrets; print('JWT_SECRET_KEY=' + secrets.token_urlsafe(32))"
python3 -c "import secrets; print('ADMIN_TOKEN=' + secrets.token_urlsafe(32))"

# Add output to backend/.env
```

**Step 6: Commit**

```bash
git add backend/pyproject.toml backend/app/config.py backend/app/auth_utils.py
git commit -m "feat(backend): add JWT utilities and auth config

Add:
- JWT generation/verification (HS256, 15 min access tokens)
- Password hashing (bcrypt, cost factor 12)
- Password validation (length, complexity requirements)
- Token generation for email verification and password reset

Dependencies: python-jose, bcrypt, pyjwt

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 1.5: Auth Pydantic Schemas

**Files:**
- Create: `backend/app/schemas/auth.py`
- Modify: `backend/app/schemas/__init__.py`

**Step 1: Create auth schemas**

```python
# backend/app/schemas/auth.py
"""Pydantic schemas for authentication endpoints."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


# ============ Request Schemas ============

class RegisterRequest(BaseModel):
    """Registration request."""
    email: EmailStr
    password: str = Field(..., min_length=8)


class LoginRequest(BaseModel):
    """Login request."""
    email: EmailStr
    password: str


class RefreshTokenRequest(BaseModel):
    """Refresh token request."""
    refresh_token: str


class VerifyEmailRequest(BaseModel):
    """Email verification request."""
    token: str


class ResendVerificationRequest(BaseModel):
    """Resend verification email request."""
    email: EmailStr


class ForgotPasswordRequest(BaseModel):
    """Forgot password request."""
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    """Password reset request."""
    token: str
    new_password: str = Field(..., min_length=8)


class AppleSignInRequest(BaseModel):
    """Apple Sign In request."""
    identity_token: str
    authorization_code: str | None = None
    user_info: dict | None = None


class DeleteAccountRequest(BaseModel):
    """Account deletion confirmation."""
    confirmation: str = Field(..., pattern="^DELETE$")


# ============ Response Schemas ============

class UserResponse(BaseModel):
    """User information in responses."""
    id: UUID
    email: str | None
    subscription_tier: str
    trial_expires_at: datetime | None
    subscription_expires_at: datetime | None
    email_verified: bool
    created_at: datetime

    class Config:
        from_attributes = True


class RegisterResponse(BaseModel):
    """Registration response."""
    message: str
    user_id: UUID
    trial_expires_at: datetime


class LoginResponse(BaseModel):
    """Login response with tokens."""
    access_token: str
    refresh_token: str
    expires_in: int
    user: UserResponse


class RefreshTokenResponse(BaseModel):
    """Refresh token response."""
    access_token: str
    expires_in: int


class AppleSignInResponse(BaseModel):
    """Apple Sign In response."""
    access_token: str
    refresh_token: str
    expires_in: int
    user: UserResponse
    is_new_user: bool


class MessageResponse(BaseModel):
    """Generic message response."""
    message: str
```

**Step 2: Export schemas**

```python
# backend/app/schemas/__init__.py
# Add to existing imports:
from app.schemas.auth import (
    AppleSignInRequest,
    AppleSignInResponse,
    DeleteAccountRequest,
    ForgotPasswordRequest,
    LoginRequest,
    LoginResponse,
    MessageResponse,
    RefreshTokenRequest,
    RefreshTokenResponse,
    RegisterRequest,
    RegisterResponse,
    ResendVerificationRequest,
    ResetPasswordRequest,
    UserResponse,
    VerifyEmailRequest,
)

__all__ = [
    # ... existing ...
    "RegisterRequest",
    "RegisterResponse",
    "LoginRequest",
    "LoginResponse",
    "RefreshTokenRequest",
    "RefreshTokenResponse",
    "AppleSignInRequest",
    "AppleSignInResponse",
    "UserResponse",
    "MessageResponse",
    # ... etc
]
```

**Step 3: Commit**

```bash
git add backend/app/schemas/auth.py backend/app/schemas/__init__.py
git commit -m "feat(backend): add auth Pydantic schemas

Add request/response schemas for:
- Registration and login
- Token refresh
- Email verification
- Password reset
- Apple Sign In
- Account deletion

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 1.6: Auth Service Layer

**Files:**
- Create: `backend/app/services/auth_service.py`

**Step 1: Create auth service**

```python
# backend/app/services/auth_service.py
"""Authentication business logic."""

import secrets
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import auth_utils
from app.config import settings
from app.models import PasswordResetToken, RefreshToken, User


class AuthService:
    """Service for authentication operations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    # ============ Registration ============

    async def register_user(self, email: str, password: str) -> User:
        """
        Register new user with email and password.
        Sets trial period to 7 days.
        """
        # Validate password
        is_valid, error_msg = auth_utils.validate_password(password)
        if not is_valid:
            raise ValueError(error_msg)

        # Check if email already exists
        result = await self.db.execute(
            select(User).where(User.email == email, User.deleted_at.is_(None))
        )
        if result.scalar_one_or_none():
            raise ValueError("Email already registered")

        # Create user
        user = User(
            email=email,
            password_hash=auth_utils.hash_password(password),
            subscription_tier="trial",
            trial_expires_at=datetime.utcnow() + timedelta(days=7),
            email_verification_token=auth_utils.generate_verification_token(),
        )

        self.db.add(user)
        await self.db.commit()
        await self.db.refresh(user)

        return user

    # ============ Login ============

    async def login_user(self, email: str, password: str) -> tuple[User, str, str]:
        """
        Authenticate user and generate tokens.
        Returns (user, access_token, refresh_token).
        """
        # Find user
        result = await self.db.execute(
            select(User).where(User.email == email, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        if not user or not user.password_hash:
            raise ValueError("Invalid credentials")

        # Verify password
        if not auth_utils.verify_password(password, user.password_hash):
            raise ValueError("Invalid credentials")

        # Check email verification
        if not user.email_verified:
            raise ValueError("Email not verified")

        # Generate tokens
        access_token = auth_utils.create_access_token(
            user_id=str(user.id),
            email=user.email,
            subscription_tier=user.get_effective_tier()
        )

        refresh_token_str = auth_utils.create_refresh_token()

        # Store refresh token
        refresh_token = RefreshToken(
            token=refresh_token_str,
            user_id=user.id,
            expires_at=datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
        )
        self.db.add(refresh_token)

        # Update last login
        user.last_login_at = datetime.utcnow()

        await self.db.commit()

        return user, access_token, refresh_token_str

    # ============ Token Refresh ============

    async def refresh_access_token(self, refresh_token_str: str) -> tuple[User, str]:
        """
        Exchange refresh token for new access token.
        Returns (user, access_token).
        """
        # Find refresh token
        result = await self.db.execute(
            select(RefreshToken).where(RefreshToken.token == refresh_token_str)
        )
        refresh_token = result.scalar_one_or_none()

        if not refresh_token:
            raise ValueError("Invalid refresh token")

        # Check expiration
        if refresh_token.expires_at < datetime.utcnow():
            raise ValueError("Refresh token expired")

        # Get user
        result = await self.db.execute(
            select(User).where(User.id == refresh_token.user_id, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("User not found")

        # Generate new access token
        access_token = auth_utils.create_access_token(
            user_id=str(user.id),
            email=user.email,
            subscription_tier=user.get_effective_tier()
        )

        # Update last used
        refresh_token.last_used_at = datetime.utcnow()
        await self.db.commit()

        return user, access_token

    # ============ Logout ============

    async def logout_user(self, user_id: UUID) -> None:
        """Delete all refresh tokens for user (logout all devices)."""
        await self.db.execute(
            RefreshToken.__table__.delete().where(RefreshToken.user_id == user_id)
        )
        await self.db.commit()

    # ============ Email Verification ============

    async def verify_email(self, token: str) -> User:
        """Verify user email with token."""
        result = await self.db.execute(
            select(User).where(User.email_verification_token == token, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("Invalid verification token")

        user.email_verified = True
        user.email_verification_token = None

        await self.db.commit()
        await self.db.refresh(user)

        return user

    # ============ Password Reset ============

    async def create_password_reset_token(self, email: str) -> tuple[User, str]:
        """Create password reset token for user."""
        result = await self.db.execute(
            select(User).where(User.email == email, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("User not found")

        token_str = auth_utils.generate_password_reset_token()

        reset_token = PasswordResetToken(
            user_id=user.id,
            token=token_str,
            expires_at=datetime.utcnow() + timedelta(minutes=15)
        )

        self.db.add(reset_token)
        await self.db.commit()

        return user, token_str

    async def reset_password(self, token: str, new_password: str) -> User:
        """Reset user password with token."""
        # Validate password
        is_valid, error_msg = auth_utils.validate_password(new_password)
        if not is_valid:
            raise ValueError(error_msg)

        # Find reset token
        result = await self.db.execute(
            select(PasswordResetToken).where(
                PasswordResetToken.token == token,
                PasswordResetToken.used_at.is_(None)
            )
        )
        reset_token = result.scalar_one_or_none()

        if not reset_token:
            raise ValueError("Invalid or used reset token")

        # Check expiration
        if reset_token.expires_at < datetime.utcnow():
            raise ValueError("Reset token expired")

        # Get user
        result = await self.db.execute(
            select(User).where(User.id == reset_token.user_id, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("User not found")

        # Update password
        user.password_hash = auth_utils.hash_password(new_password)
        reset_token.used_at = datetime.utcnow()

        # Invalidate all refresh tokens (force re-login)
        await self.db.execute(
            RefreshToken.__table__.delete().where(RefreshToken.user_id == user.id)
        )

        await self.db.commit()
        await self.db.refresh(user)

        return user

    # ============ Account Deletion ============

    async def delete_account(self, user_id: UUID) -> None:
        """Soft delete user account."""
        result = await self.db.execute(
            select(User).where(User.id == user_id, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("User not found")

        user.deleted_at = datetime.utcnow()

        # Delete all refresh tokens
        await self.db.execute(
            RefreshToken.__table__.delete().where(RefreshToken.user_id == user_id)
        )

        await self.db.commit()
```

**Step 2: Commit**

```bash
git add backend/app/services/auth_service.py
git commit -m "feat(backend): add AuthService for business logic

Implement authentication operations:
- User registration with trial period (7 days)
- Login with email/password
- Token refresh
- Logout (revoke refresh tokens)
- Email verification
- Password reset
- Account deletion (soft delete)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

*[Continuing with remaining tasks... Due to length, I'll summarize the structure]*

## Phase 2: Apple Sign In (1 day)
- Task 2.1: Apple Identity Token Verification
- Task 2.2: Apple Sign In Endpoint
- Task 2.3: Apple Sign In Tests

## Phase 3: Subscription Backend (1 day)
- Task 3.1: StoreKit Receipt Verification
- Task 3.2: Subscription Endpoints
- Task 3.3: App Store Server Notifications Webhook
- Task 3.4: Subscription Tests

## Phase 4: macOS AuthService (1 day)
- Task 4.1: Remove Clerk Dependencies
- Task 4.2: AuthService Implementation
- Task 4.3: Keychain Service
- Task 4.4: API Client Auth Methods
- Task 4.5: Login/Register Views

## Phase 5: macOS StoreManager (1 day)
- Task 5.1: StoreManager Implementation
- Task 5.2: Product Configuration (App Store Connect)
- Task 5.3: Subscription Views
- Task 5.4: Purchase Flow Testing

## Phase 6: Multi-User Cache (0.5 day)
- Task 6.1: LocalDatabase User Isolation
- Task 6.2: ContentManager User Filtering
- Task 6.3: Cache Preservation on Logout

## Phase 7: Admin Backend (0.5 day)
- Task 7.1: SQLAdmin Setup
- Task 7.2: User/Subscription Admin Views

## Phase 8: Testing & Polish (1 day)
- Task 8.1: Backend Integration Tests
- Task 8.2: macOS UI Tests
- Task 8.3: Trial Expiration Flow
- Task 8.4: Error Handling Polish

---

## Testing Commands

```bash
# Backend tests
cd backend
pytest tests/ -v
pytest tests/test_auth.py -v
pytest tests/test_subscription.py -v

# macOS tests
cd macos
swift test

# Manual testing
# 1. Start backend: uvicorn app.main:app --reload
# 2. Run macOS app: swift run App
# 3. Test registration, login, purchase flow
```

## Deployment Checklist

- [ ] Generate secure JWT_SECRET_KEY and ADMIN_TOKEN
- [ ] Configure Resend API key
- [ ] Set up Apple App Store Connect (IAP products)
- [ ] Configure App Store Server Notifications webhook URL
- [ ] Test subscription flow in Sandbox
- [ ] Run all tests
- [ ] Deploy backend
- [ ] Submit macOS app for TestFlight review

---

**Plan saved to:** `docs/plans/2026-03-02-jwt-auth-appstore-subscription.md`

**Implementation Options:**

1. **Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

2. **Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach would you like?**
