"""Pytest configuration and fixtures for tests."""

import pytest_asyncio
from sqlalchemy import event, text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import StaticPool


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
                    user_id VARCHAR(100) NOT NULL,
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
                    user_id VARCHAR(100) NOT NULL,
                    status VARCHAR(20) NOT NULL,
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
                    user_id VARCHAR(100) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (content_id, tag_id),
                    FOREIGN KEY (content_id) REFERENCES contents (id) ON DELETE CASCADE,
                    FOREIGN KEY (tag_id) REFERENCES user_tags (id) ON DELETE CASCADE
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
