"""Pytest configuration and fixtures for tests."""

import os
from unittest.mock import patch
from uuid import uuid4

# Ensure test imports do not require local production secrets.
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-0123456789abcd")
os.environ.setdefault("ADMIN_TOKEN", "test-admin-token-0123456789abcdef")

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.database import get_db
from app.main import app
from app.models.user import User


@pytest_asyncio.fixture
async def db_session():
    """Create an in-memory SQLite database for testing.

    Creates tables needed for tag-related and pipeline tests.
    Simulates PostgreSQL ARRAY/JSONB types using TEXT for SQLite compatibility.
    """
    # Use in-memory SQLite database for tests
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        json_serializer=lambda obj: __import__('json').dumps(obj),
        json_deserializer=lambda obj: __import__('json').loads(obj),
    )

    # Create tables needed for tag-related tests (avoids JSONB issues with other tables)
    async with engine.begin() as conn:
        await conn.execute(
            text(
                """
                CREATE TABLE user_tags (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    tag_name VARCHAR(50) NOT NULL,
                    deleted_at TIMESTAMP,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE (user_id, tag_name)
                )
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE TABLE contents (
                    id VARCHAR(36) PRIMARY KEY,
                    title TEXT,
                    source_url TEXT,
                    source_type VARCHAR(20) NOT NULL,
                    source_app_name VARCHAR(100),
                    source_app_bundle_id VARCHAR(200),
                    channel VARCHAR(20) NOT NULL DEFAULT 'manual',
                    l0_summary TEXT,
                    l1_outline TEXT,
                    keywords TEXT,
                    source_language VARCHAR(10),
                    full_text TEXT,
                    full_text_tsv TEXT,
                    user_id TEXT NOT NULL,
                    status VARCHAR(20) NOT NULL,
                    processing_started_at TIMESTAMP,
                    processing_finished_at TIMESTAMP,
                    processing_error TEXT,
                    processing_attempts INTEGER NOT NULL DEFAULT 0,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE TABLE content_tags (
                    content_id VARCHAR(36) NOT NULL,
                    tag_id INTEGER NOT NULL,
                    user_id TEXT NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (content_id, tag_id),
                    FOREIGN KEY (content_id) REFERENCES contents (id) ON DELETE CASCADE,
                    FOREIGN KEY (tag_id) REFERENCES user_tags (id) ON DELETE CASCADE
                )
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE TABLE paragraphs (
                    id VARCHAR(36) PRIMARY KEY,
                    content_id VARCHAR(36) NOT NULL,
                    anchor_id TEXT NOT NULL,
                    text TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    full_text_tsv TEXT,
                    FOREIGN KEY (content_id) REFERENCES contents (id) ON DELETE CASCADE
                )
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE TABLE content_jobs (
                    id VARCHAR(36) PRIMARY KEY,
                    content_id VARCHAR(36) NOT NULL UNIQUE,
                    user_id TEXT NOT NULL,
                    source_type VARCHAR(20) NOT NULL,
                    body TEXT NOT NULL,
                    status VARCHAR(20) NOT NULL DEFAULT 'queued',
                    attempts INTEGER NOT NULL DEFAULT 0,
                    scheduled_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    started_at TIMESTAMP,
                    finished_at TIMESTAMP,
                    last_error TEXT,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (content_id) REFERENCES contents (id) ON DELETE CASCADE
                )
                """
            )
        )

    # Create session
    async_session = async_sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with async_session() as session:
        yield session

    # Cleanup
    await engine.dispose()


@pytest_asyncio.fixture
async def auth_db_session():
    """Create an in-memory SQLite database for auth/subscription tests.

    Creates only users, refresh_tokens, and password_reset_tokens tables.
    Other tables (with JSONB) are not created to avoid SQLite compatibility issues.

    Note: We create tables manually to avoid JSONB issues with SQLite.
    """
    from sqlalchemy import event

    from app.models.refresh_token import (
        EmailLoginCode,
        PasswordResetToken,
        RefreshToken,
    )

    # Import models to ensure they're available
    User  # noqa: B018
    PasswordResetToken  # noqa: B018
    RefreshToken  # noqa: B018
    EmailLoginCode  # noqa: B018

    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

    # Enable foreign keys for SQLite
    @event.listens_for(engine.sync_engine, "connect")
    def set_sqlite_pragma(dbapi_conn, _connection_record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    async with engine.begin() as conn:
        # Create only the tables we need (User, RefreshToken, PasswordResetToken)
        # Manually create tables to work around SQLite limitations
        await conn.run_sync(lambda sync_conn: User.__table__.create(sync_conn))
        await conn.run_sync(
            lambda sync_conn: RefreshToken.__table__.create(sync_conn)
        )
        await conn.run_sync(
            lambda sync_conn: PasswordResetToken.__table__.create(sync_conn)
        )
        await conn.run_sync(
            lambda sync_conn: EmailLoginCode.__table__.create(sync_conn)
        )

    async_session = async_sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    # Patch models to auto-generate UUIDs for SQLite (no gen_random_uuid()).
    # Store originals and build patched versions in a loop.
    models_to_patch = [User, RefreshToken, PasswordResetToken, EmailLoginCode]
    originals = {model: model.__init__ for model in models_to_patch}

    def _make_patched_init(original_init):
        def patched_init(self, **kwargs):
            if "id" not in kwargs:
                kwargs["id"] = uuid4()
            original_init(self, **kwargs)
        return patched_init

    for model in models_to_patch:
        model.__init__ = _make_patched_init(originals[model])

    async with async_session() as session:
        try:
            yield session
        finally:
            for model, original_init in originals.items():
                model.__init__ = original_init

    await engine.dispose()


@pytest_asyncio.fixture
async def test_client(auth_db_session):
    """Create FastAPI test client with overridden database dependency."""

    async def override_get_db():
        yield auth_db_session

    app.dependency_overrides[get_db] = override_get_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()


@pytest_asyncio.fixture
def mock_apple_verify():
    """Mock Apple identity token verification."""
    # Patch where it's imported, not where it's defined
    with patch("app.services.apple_auth.verify_apple_identity_token") as mock:

        async def mock_verify(token):
            return {
                "apple_id": "test-apple-id-123",
                "email": "apple@example.com",
                "email_verified": True,
            }

        mock.side_effect = mock_verify
        yield mock


@pytest_asyncio.fixture
def mock_resend_email():
    """Mock Resend email sending and capture codes."""
    sent_codes: list[tuple[str, str]] = []

    async def mock_send(_self, to_email: str, code: str):
        sent_codes.append((to_email, code))

    with patch(
        "app.services.email_service.ResendEmailService.send_login_code",
        new=mock_send,
    ):
        yield sent_codes


@pytest_asyncio.fixture
def mock_storekit_verify():
    """Mock StoreKit receipt verification."""
    with patch("app.services.subscription_service.verify_storekit_receipt") as mock:
        from datetime import UTC, datetime, timedelta

        async def mock_verify(jws_receipt):
            # Parse mock receipt to determine tier
            tier = "basic"
            if "pro" in jws_receipt.lower():
                tier = "pro"

            return {
                "transaction_id": "test-txn-123",
                "original_transaction_id": "test-orig-txn-123",
                "product_id": f"com.readless.{tier}.monthly",
                "subscription_tier": tier,
                "purchase_date": datetime.now(UTC),
                "expires_date": datetime.now(UTC) + timedelta(days=30),
                "is_trial": False,
                "environment": "Sandbox",
                "app_account_token": None,
                "revocation_date": None,
                "is_upgraded": False,
            }

        mock.side_effect = mock_verify
        yield mock
