"""Pytest configuration and fixtures for tests."""

import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import StaticPool


@pytest_asyncio.fixture
async def db_session():
    """Create an in-memory SQLite database for testing.

    Only creates the user_tags table needed for tag-related tests.
    This avoids JSONB compatibility issues with SQLite.
    """
    # Use in-memory SQLite database for tests
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

    # Create only the user_tags table (avoids JSONB issues with other tables)
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

    # Create session
    async_session = async_sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with async_session() as session:
        yield session

    # Cleanup
    await engine.dispose()
