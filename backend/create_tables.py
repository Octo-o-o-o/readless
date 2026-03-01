#!/usr/bin/env python3
"""Create all database tables from SQLAlchemy models."""

import asyncio

from app.database import Base, get_engine
# Import all models to register them with Base.metadata
from app.models import Channel, Content, Paragraph, Podcast


async def create_tables():
    """Create all tables defined in Base.metadata."""
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    print("✅ All tables created successfully!")


if __name__ == "__main__":
    asyncio.run(create_tables())
