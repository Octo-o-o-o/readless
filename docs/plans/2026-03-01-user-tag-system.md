# User Tag System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement customizable per-user tag system with AI-powered tag selection and sidebar filtering.

**Architecture:** Relational database design with `user_tags` (tag library with logical deletion) and `content_tags` (many-to-many relationship). AI receives user's tag library during summarization and selects 0-N relevant tags. Frontend displays tags in sidebar for filtering and inline tag management in content view.

**Tech Stack:** PostgreSQL (user_tags, content_tags), SQLAlchemy (ORM), FastAPI (REST API), SwiftUI (macOS UI), OpenAI API (tag selection)

---

## Phase 1: Backend Database & Models

### Task 1: Create UserTag Model

**Files:**
- Create: `backend/app/models/user_tag.py`
- Test: `backend/tests/models/test_user_tag.py` (create if needed)

**Step 1: Write the failing test**

Create test file:
```python
"""Tests for UserTag model."""

from datetime import datetime, timezone
from sqlalchemy import select
from app.models.user_tag import UserTag


async def test_create_user_tag(db_session):
    """Test creating a user tag."""
    tag = UserTag(user_id="user123", tag_name="技术")
    db_session.add(tag)
    await db_session.commit()
    await db_session.refresh(tag)

    assert tag.id is not None
    assert tag.user_id == "user123"
    assert tag.tag_name == "技术"
    assert tag.deleted_at is None
    assert isinstance(tag.created_at, datetime)


async def test_user_tag_unique_constraint(db_session):
    """Test unique constraint on user_id + tag_name."""
    tag1 = UserTag(user_id="user123", tag_name="技术")
    db_session.add(tag1)
    await db_session.commit()

    # Attempting to add duplicate should fail
    tag2 = UserTag(user_id="user123", tag_name="技术")
    db_session.add(tag2)

    from sqlalchemy.exc import IntegrityError
    try:
        await db_session.commit()
        assert False, "Should have raised IntegrityError"
    except IntegrityError:
        await db_session.rollback()


async def test_soft_delete_user_tag(db_session):
    """Test logical deletion of user tag."""
    tag = UserTag(user_id="user123", tag_name="技术")
    db_session.add(tag)
    await db_session.commit()
    await db_session.refresh(tag)

    # Soft delete
    tag.deleted_at = datetime.now(timezone.utc)
    await db_session.commit()

    # Query should still find it
    stmt = select(UserTag).where(UserTag.id == tag.id)
    result = await db_session.execute(stmt)
    found_tag = result.scalar_one()
    assert found_tag.deleted_at is not None
```

**Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/models/test_user_tag.py -v`
Expected: FAIL with "No module named 'app.models.user_tag'"

**Step 3: Write minimal implementation**

Create `backend/app/models/user_tag.py`:
```python
"""User tag model — stores user's tag library."""

from datetime import datetime

from sqlalchemy import DateTime, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserTag(Base):
    """User tag model with logical deletion support."""

    __tablename__ = "user_tags"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(100), nullable=False)
    tag_name: Mapped[str] = mapped_column(String(50), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        Index(
            "idx_user_tags_user_id",
            "user_id",
            postgresql_where="deleted_at IS NULL",
        ),
        Index("idx_user_tags_deleted_at", "deleted_at"),
        # Unique constraint on user_id + tag_name
        # Note: PostgreSQL unique constraints don't work well with NULL deleted_at
        # So we enforce uniqueness at application level
    )
```

**Step 4: Update model imports**

Modify `backend/app/models/__init__.py`:
```python
from app.models.content import Content
from app.models.paragraph import Paragraph
from app.models.podcast import Podcast
from app.models.channel import Channel
from app.models.user_tag import UserTag  # Add this line

__all__ = ["Content", "Paragraph", "Podcast", "Channel", "UserTag"]
```

**Step 5: Run test to verify it passes**

Run: `cd backend && pytest tests/models/test_user_tag.py -v`
Expected: Tests may fail due to missing database tables - that's OK, we'll create migration next

**Step 6: Commit**

```bash
git add backend/app/models/user_tag.py backend/app/models/__init__.py backend/tests/models/test_user_tag.py
git commit -m "feat(models): add UserTag model with logical deletion

- Add UserTag ORM model with user_id, tag_name, deleted_at
- Add indexes for efficient querying
- Add tests for creation, uniqueness, and soft deletion

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Create ContentTag Model

**Files:**
- Create: `backend/app/models/content_tag.py`
- Test: `backend/tests/models/test_content_tag.py`

**Step 1: Write the failing test**

Create test file:
```python
"""Tests for ContentTag model."""

from datetime import datetime
from app.models.content_tag import ContentTag
from app.models.user_tag import UserTag
from app.models.content import Content


async def test_create_content_tag_relationship(db_session):
    """Test creating content-tag relationship."""
    # Create tag
    tag = UserTag(user_id="user123", tag_name="技术")
    db_session.add(tag)
    await db_session.flush()

    # Create content (simplified - may need to create properly)
    from uuid import uuid4
    content_id = str(uuid4())

    # Create relationship
    content_tag = ContentTag(
        content_id=content_id,
        tag_id=tag.id,
        user_id="user123"
    )
    db_session.add(content_tag)
    await db_session.commit()

    assert content_tag.content_id == content_id
    assert content_tag.tag_id == tag.id
    assert content_tag.user_id == "user123"
    assert isinstance(content_tag.created_at, datetime)


async def test_content_tag_cascade_delete(db_session):
    """Test CASCADE deletion when tag is deleted."""
    # Create tag
    tag = UserTag(user_id="user123", tag_name="技术")
    db_session.add(tag)
    await db_session.flush()

    # Create relationship
    from uuid import uuid4
    content_tag = ContentTag(
        content_id=str(uuid4()),
        tag_id=tag.id,
        user_id="user123"
    )
    db_session.add(content_tag)
    await db_session.commit()

    tag_id = tag.id

    # Delete tag
    await db_session.delete(tag)
    await db_session.commit()

    # Relationship should be deleted via CASCADE
    from sqlalchemy import select
    stmt = select(ContentTag).where(ContentTag.tag_id == tag_id)
    result = await db_session.execute(stmt)
    assert result.scalar_one_or_none() is None
```

**Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/models/test_content_tag.py -v`
Expected: FAIL with "No module named 'app.models.content_tag'"

**Step 3: Write minimal implementation**

Create `backend/app/models/content_tag.py`:
```python
"""Content-Tag relationship model."""

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ContentTag(Base):
    """Many-to-many relationship between content and tags."""

    __tablename__ = "content_tags"

    content_id: Mapped[str] = mapped_column(
        String(36),
        ForeignKey("contents.id", ondelete="CASCADE"),
        primary_key=True,
    )
    tag_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("user_tags.id", ondelete="CASCADE"),
        primary_key=True,
    )
    user_id: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        Index("idx_content_tags_tag_id", "tag_id"),
        Index("idx_content_tags_content_id", "content_id"),
        Index("idx_content_tags_user_id", "user_id"),
    )
```

**Step 4: Update model imports**

Modify `backend/app/models/__init__.py`:
```python
from app.models.content import Content
from app.models.paragraph import Paragraph
from app.models.podcast import Podcast
from app.models.channel import Channel
from app.models.user_tag import UserTag
from app.models.content_tag import ContentTag  # Add this line

__all__ = ["Content", "Paragraph", "Podcast", "Channel", "UserTag", "ContentTag"]
```

**Step 5: Run test to verify it passes**

Run: `cd backend && pytest tests/models/test_content_tag.py -v`
Expected: Tests may fail due to missing tables

**Step 6: Commit**

```bash
git add backend/app/models/content_tag.py backend/app/models/__init__.py backend/tests/models/test_content_tag.py
git commit -m "feat(models): add ContentTag relationship model

- Add ContentTag for many-to-many content-tag relationships
- Add CASCADE delete for tag deletion
- Add indexes for efficient querying
- Add tests for relationship creation and cascade deletion

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 3: Create Database Migration

**Files:**
- Create: `backend/alembic/versions/TIMESTAMP_add_tag_system.py`
- Modify: `backend/app/models/content.py` (remove tags column)

**Step 1: Generate migration skeleton**

Run: `cd backend && alembic revision -m "add_tag_system"`

This creates a file like `backend/alembic/versions/abc123_add_tag_system.py`

**Step 2: Write migration upgrade**

Edit the generated file:
```python
"""add tag system

Revision ID: abc123
Revises: <previous_revision>
Create Date: 2026-03-01
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = 'abc123'  # Will be auto-generated
down_revision = '<previous>'  # Will be auto-generated
branch_labels = None
depends_on = None


def upgrade():
    # 1. Create user_tags table
    op.create_table(
        'user_tags',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.String(100), nullable=False),
        sa.Column('tag_name', sa.String(50), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        'idx_user_tags_user_id',
        'user_tags',
        ['user_id'],
        postgresql_where=sa.text('deleted_at IS NULL')
    )
    op.create_index('idx_user_tags_deleted_at', 'user_tags', ['deleted_at'])

    # 2. Create content_tags table
    op.create_table(
        'content_tags',
        sa.Column('content_id', sa.String(36), nullable=False),
        sa.Column('tag_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.String(100), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['content_id'], ['contents.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['tag_id'], ['user_tags.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('content_id', 'tag_id')
    )
    op.create_index('idx_content_tags_tag_id', 'content_tags', ['tag_id'])
    op.create_index('idx_content_tags_content_id', 'content_tags', ['content_id'])
    op.create_index('idx_content_tags_user_id', 'content_tags', ['user_id'])

    # 3. Migrate existing tags from contents.tags array to new tables
    op.execute("""
        -- Insert unique tags into user_tags
        INSERT INTO user_tags (user_id, tag_name)
        SELECT DISTINCT user_id, unnest(tags) as tag_name
        FROM contents
        WHERE tags IS NOT NULL AND array_length(tags, 1) > 0
        ON CONFLICT DO NOTHING;

        -- Insert content-tag relationships
        INSERT INTO content_tags (content_id, tag_id, user_id)
        SELECT c.id, ut.id, c.user_id
        FROM contents c
        CROSS JOIN LATERAL unnest(c.tags) as tag_name
        JOIN user_tags ut ON ut.user_id = c.user_id AND ut.tag_name = tag_name
        WHERE c.tags IS NOT NULL AND array_length(c.tags, 1) > 0;
    """)

    # 4. Drop old tags column and index
    op.drop_index('ix_contents_tags', table_name='contents')
    op.drop_column('contents', 'tags')


def downgrade():
    # Restore tags column
    op.add_column('contents', sa.Column('tags', postgresql.ARRAY(sa.String()), nullable=True))
    op.create_index('ix_contents_tags', 'contents', ['tags'], postgresql_using='gin')

    # Migrate data back
    op.execute("""
        UPDATE contents c
        SET tags = ARRAY(
            SELECT ut.tag_name
            FROM content_tags ct
            JOIN user_tags ut ON ct.tag_id = ut.id
            WHERE ct.content_id = c.id
        );
    """)

    # Drop new tables
    op.drop_table('content_tags')
    op.drop_table('user_tags')
```

**Step 3: Update Content model**

Modify `backend/app/models/content.py`:

Remove these lines:
```python
# Classification
tags: Mapped[list[str] | None] = mapped_column(
    ARRAY(String), nullable=True
)
```

And in `__table_args__`:
```python
# Remove this line:
Index("ix_contents_tags", "tags", postgresql_using="gin"),
```

**Step 4: Run migration**

Run: `cd backend && alembic upgrade head`
Expected: Migration applies successfully

**Step 5: Run model tests**

Run: `cd backend && pytest tests/models/test_user_tag.py tests/models/test_content_tag.py -v`
Expected: All tests pass

**Step 6: Commit**

```bash
git add backend/alembic/versions/abc123_add_tag_system.py backend/app/models/content.py
git commit -m "feat(db): add tag system migration

- Create user_tags and content_tags tables
- Migrate existing tags from array to relational tables
- Remove tags column from contents table
- Add indexes for efficient querying

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 2: Backend API - Schemas & Endpoints

### Task 4: Create Tag Schemas

**Files:**
- Create: `backend/app/schemas/tag.py`

**Step 1: Write the schema file**

Create `backend/app/schemas/tag.py`:
```python
"""Pydantic models for tag API requests and responses."""

from datetime import datetime
from pydantic import BaseModel, Field


class UserTagResponse(BaseModel):
    """Response model for user tag."""

    id: int
    tag_name: str
    content_count: int = Field(description="Number of content items with this tag")
    created_at: datetime


class TagCreateRequest(BaseModel):
    """Request body for creating a tag."""

    tag_name: str = Field(min_length=1, max_length=50)


class ContentTagsUpdateRequest(BaseModel):
    """Request body for updating content tags."""

    tag_names: list[str] = Field(description="Complete list of tag names for this content")
```

**Step 2: Commit**

```bash
git add backend/app/schemas/tag.py
git commit -m "feat(schemas): add tag API schemas

- Add UserTagResponse with content count
- Add TagCreateRequest for tag creation
- Add ContentTagsUpdateRequest for content tag management

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Create Tag Router - GET /api/v1/tags

**Files:**
- Create: `backend/app/routers/tags.py`
- Test: `backend/tests/routers/test_tags.py`

**Step 1: Write failing test**

Create `backend/tests/routers/test_tags.py`:
```python
"""Tests for tag API endpoints."""

import pytest
from httpx import AsyncClient
from app.models.user_tag import UserTag
from app.models.content_tag import ContentTag


@pytest.mark.asyncio
async def test_list_user_tags_empty(client: AsyncClient, auth_headers):
    """Test listing tags when user has none."""
    response = await client.get("/api/v1/tags", headers=auth_headers)

    assert response.status_code == 200
    assert response.json() == []


@pytest.mark.asyncio
async def test_list_user_tags_with_content_count(client: AsyncClient, auth_headers, db_session):
    """Test listing tags with content count."""
    # Create tags
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习")
    db_session.add_all([tag1, tag2])
    await db_session.flush()

    # Create content-tag relationships for tag1
    from uuid import uuid4
    ct1 = ContentTag(content_id=str(uuid4()), tag_id=tag1.id, user_id="test_user")
    ct2 = ContentTag(content_id=str(uuid4()), tag_id=tag1.id, user_id="test_user")
    db_session.add_all([ct1, ct2])
    await db_session.commit()

    response = await client.get("/api/v1/tags", headers=auth_headers)

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2

    # Find tag1 in response
    tag1_data = next(t for t in data if t["tag_name"] == "技术")
    assert tag1_data["content_count"] == 2

    # tag2 should have 0 content
    tag2_data = next(t for t in data if t["tag_name"] == "学习")
    assert tag2_data["content_count"] == 0


@pytest.mark.asyncio
async def test_list_user_tags_excludes_deleted(client: AsyncClient, auth_headers, db_session):
    """Test that deleted tags are not listed."""
    from datetime import datetime, timezone

    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习", deleted_at=datetime.now(timezone.utc))
    db_session.add_all([tag1, tag2])
    await db_session.commit()

    response = await client.get("/api/v1/tags", headers=auth_headers)

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["tag_name"] == "技术"
```

**Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/routers/test_tags.py::test_list_user_tags_empty -v`
Expected: FAIL with 404 (route not found)

**Step 3: Implement GET /api/v1/tags endpoint**

Create `backend/app/routers/tags.py`:
```python
"""Tag management API endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.models.content_tag import ContentTag
from app.models.user_tag import UserTag
from app.schemas.tag import (
    ContentTagsUpdateRequest,
    TagCreateRequest,
    UserTagResponse,
)

router = APIRouter(prefix="/api/v1/tags", tags=["tags"])


@router.get("", response_model=list[UserTagResponse])
async def list_user_tags(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Get user's tag library with content count."""
    # Query tags with content count
    stmt = (
        select(
            UserTag.id,
            UserTag.tag_name,
            UserTag.created_at,
            func.count(ContentTag.content_id).label("content_count"),
        )
        .outerjoin(ContentTag, UserTag.id == ContentTag.tag_id)
        .where(UserTag.user_id == user_id, UserTag.deleted_at.is_(None))
        .group_by(UserTag.id, UserTag.tag_name, UserTag.created_at)
        .order_by(UserTag.created_at.desc())
    )
    result = await db.execute(stmt)
    rows = result.all()

    return [
        UserTagResponse(
            id=row.id,
            tag_name=row.tag_name,
            created_at=row.created_at,
            content_count=row.content_count,
        )
        for row in rows
    ]
```

**Step 4: Register router in main.py**

Modify `backend/app/main.py`:
```python
from app.routers import content, podcast, search, tags  # Add tags

# ...

app.include_router(content.router)
app.include_router(podcast.router)
app.include_router(search.router)
app.include_router(tags.router)  # Add this line
```

**Step 5: Run tests to verify they pass**

Run: `cd backend && pytest tests/routers/test_tags.py -v`
Expected: All tests pass

**Step 6: Commit**

```bash
git add backend/app/routers/tags.py backend/app/main.py backend/tests/routers/test_tags.py
git commit -m "feat(api): add GET /api/v1/tags endpoint

- List user's tag library with content count
- Exclude soft-deleted tags
- Order by creation date (newest first)
- Add comprehensive tests

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 6: Add POST /api/v1/tags Endpoint

**Files:**
- Modify: `backend/app/routers/tags.py`
- Test: `backend/tests/routers/test_tags.py`

**Step 1: Write failing tests**

Add to `backend/tests/routers/test_tags.py`:
```python
@pytest.mark.asyncio
async def test_create_tag(client: AsyncClient, auth_headers):
    """Test creating a new tag."""
    response = await client.post(
        "/api/v1/tags",
        json={"tag_name": "投资"},
        headers=auth_headers
    )

    assert response.status_code == 200
    data = response.json()
    assert data["tag_name"] == "投资"
    assert data["content_count"] == 0
    assert "id" in data
    assert "created_at" in data


@pytest.mark.asyncio
async def test_create_duplicate_tag(client: AsyncClient, auth_headers, db_session):
    """Test creating a tag that already exists."""
    # Create tag directly
    tag = UserTag(user_id="test_user", tag_name="技术")
    db_session.add(tag)
    await db_session.commit()

    # Try to create duplicate
    response = await client.post(
        "/api/v1/tags",
        json={"tag_name": "技术"},
        headers=auth_headers
    )

    assert response.status_code == 400
    assert "already exists" in response.json()["detail"]


@pytest.mark.asyncio
async def test_restore_deleted_tag(client: AsyncClient, auth_headers, db_session):
    """Test that creating a deleted tag restores it."""
    from datetime import datetime, timezone

    # Create deleted tag
    tag = UserTag(user_id="test_user", tag_name="技术", deleted_at=datetime.now(timezone.utc))
    db_session.add(tag)
    await db_session.commit()
    tag_id = tag.id

    # Create tag with same name
    response = await client.post(
        "/api/v1/tags",
        json={"tag_name": "技术"},
        headers=auth_headers
    )

    assert response.status_code == 200
    data = response.json()
    assert data["id"] == tag_id  # Should be same tag
    assert data["tag_name"] == "技术"

    # Verify deleted_at is NULL
    from sqlalchemy import select
    stmt = select(UserTag).where(UserTag.id == tag_id)
    result = await db_session.execute(stmt)
    restored_tag = result.scalar_one()
    assert restored_tag.deleted_at is None
```

**Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/routers/test_tags.py::test_create_tag -v`
Expected: FAIL with 405 (method not allowed)

**Step 3: Implement POST endpoint**

Add to `backend/app/routers/tags.py`:
```python
@router.post("", response_model=UserTagResponse)
async def create_tag(
    request: TagCreateRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Create a new tag in user's tag library."""
    # Check if tag already exists (including soft-deleted)
    stmt = select(UserTag).where(
        UserTag.user_id == user_id,
        UserTag.tag_name == request.tag_name,
    )
    result = await db.execute(stmt)
    existing_tag = result.scalar_one_or_none()

    if existing_tag:
        if existing_tag.deleted_at:
            # Restore soft-deleted tag
            existing_tag.deleted_at = None
            await db.commit()
            await db.refresh(existing_tag)
            return UserTagResponse(
                id=existing_tag.id,
                tag_name=existing_tag.tag_name,
                created_at=existing_tag.created_at,
                content_count=0,
            )
        else:
            raise HTTPException(status_code=400, detail="Tag already exists")

    # Create new tag
    tag = UserTag(user_id=user_id, tag_name=request.tag_name)
    db.add(tag)
    await db.commit()
    await db.refresh(tag)

    return UserTagResponse(
        id=tag.id,
        tag_name=tag.tag_name,
        created_at=tag.created_at,
        content_count=0,
    )
```

**Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/routers/test_tags.py::test_create_tag tests/routers/test_tags.py::test_create_duplicate_tag tests/routers/test_tags.py::test_restore_deleted_tag -v`
Expected: All tests pass

**Step 5: Commit**

```bash
git add backend/app/routers/tags.py backend/tests/routers/test_tags.py
git commit -m "feat(api): add POST /api/v1/tags endpoint

- Create new tag in user's library
- Restore soft-deleted tag if exists
- Return 400 for duplicate active tags
- Add comprehensive tests

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 7: Add DELETE /api/v1/tags/{tag_id} Endpoint

**Files:**
- Modify: `backend/app/routers/tags.py`
- Test: `backend/tests/routers/test_tags.py`

**Step 1: Write failing tests**

Add to `backend/tests/routers/test_tags.py`:
```python
@pytest.mark.asyncio
async def test_delete_tag(client: AsyncClient, auth_headers, db_session):
    """Test deleting a tag."""
    # Create tag
    tag = UserTag(user_id="test_user", tag_name="技术")
    db_session.add(tag)
    await db_session.commit()
    tag_id = tag.id

    # Delete tag
    response = await client.delete(f"/api/v1/tags/{tag_id}", headers=auth_headers)

    assert response.status_code == 200

    # Verify soft deletion
    from sqlalchemy import select
    stmt = select(UserTag).where(UserTag.id == tag_id)
    result = await db_session.execute(stmt)
    deleted_tag = result.scalar_one()
    assert deleted_tag.deleted_at is not None


@pytest.mark.asyncio
async def test_delete_tag_removes_content_relationships(client: AsyncClient, auth_headers, db_session):
    """Test that deleting tag removes content-tag relationships."""
    # Create tag
    tag = UserTag(user_id="test_user", tag_name="技术")
    db_session.add(tag)
    await db_session.flush()

    # Create content-tag relationships
    from uuid import uuid4
    ct1 = ContentTag(content_id=str(uuid4()), tag_id=tag.id, user_id="test_user")
    ct2 = ContentTag(content_id=str(uuid4()), tag_id=tag.id, user_id="test_user")
    db_session.add_all([ct1, ct2])
    await db_session.commit()
    tag_id = tag.id

    # Delete tag
    response = await client.delete(f"/api/v1/tags/{tag_id}", headers=auth_headers)
    assert response.status_code == 200

    # Verify relationships are deleted
    from sqlalchemy import select
    stmt = select(ContentTag).where(ContentTag.tag_id == tag_id)
    result = await db_session.execute(stmt)
    assert result.scalar_one_or_none() is None


@pytest.mark.asyncio
async def test_delete_nonexistent_tag(client: AsyncClient, auth_headers):
    """Test deleting a tag that doesn't exist."""
    response = await client.delete("/api/v1/tags/99999", headers=auth_headers)

    assert response.status_code == 404
```

**Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/routers/test_tags.py::test_delete_tag -v`
Expected: FAIL with 405 (method not allowed)

**Step 3: Implement DELETE endpoint**

Add to `backend/app/routers/tags.py`:
```python
@router.delete("/{tag_id}")
async def delete_tag(
    tag_id: int,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Soft delete a tag and remove it from all content."""
    # Verify tag ownership
    stmt = select(UserTag).where(
        UserTag.id == tag_id,
        UserTag.user_id == user_id,
        UserTag.deleted_at.is_(None),
    )
    result = await db.execute(stmt)
    tag = result.scalar_one_or_none()

    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")

    # Soft delete tag
    tag.deleted_at = func.now()

    # Delete all content_tags relationships (CASCADE will handle this automatically,
    # but we do it explicitly for clarity)
    stmt = delete(ContentTag).where(ContentTag.tag_id == tag_id)
    await db.execute(stmt)

    await db.commit()
    return {"message": "Tag deleted successfully"}
```

**Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/routers/test_tags.py::test_delete_tag tests/routers/test_tags.py::test_delete_tag_removes_content_relationships tests/routers/test_tags.py::test_delete_nonexistent_tag -v`
Expected: All tests pass

**Step 5: Commit**

```bash
git add backend/app/routers/tags.py backend/tests/routers/test_tags.py
git commit -m "feat(api): add DELETE /api/v1/tags/{tag_id} endpoint

- Soft delete tag (set deleted_at)
- Remove all content-tag relationships
- Verify tag ownership before deletion
- Return 404 for nonexistent tags
- Add comprehensive tests

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 8: Add Content Tag Management Endpoints

**Files:**
- Modify: `backend/app/routers/tags.py`
- Test: `backend/tests/routers/test_tags.py`

**Step 1: Write failing tests**

Add to `backend/tests/routers/test_tags.py`:
```python
@pytest.mark.asyncio
async def test_get_content_tags(client: AsyncClient, auth_headers, db_session):
    """Test getting tags for a content item."""
    # Create tags
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习")
    db_session.add_all([tag1, tag2])
    await db_session.flush()

    # Create content-tag relationships
    from uuid import uuid4
    content_id = str(uuid4())
    ct1 = ContentTag(content_id=content_id, tag_id=tag1.id, user_id="test_user")
    ct2 = ContentTag(content_id=content_id, tag_id=tag2.id, user_id="test_user")
    db_session.add_all([ct1, ct2])
    await db_session.commit()

    # Get tags
    response = await client.get(f"/api/v1/tags/content/{content_id}/tags", headers=auth_headers)

    assert response.status_code == 200
    tags = response.json()
    assert len(tags) == 2
    assert "技术" in tags
    assert "学习" in tags


@pytest.mark.asyncio
async def test_update_content_tags_with_existing_tags(client: AsyncClient, auth_headers, db_session):
    """Test updating content tags with existing tags."""
    # Create tags
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习")
    db_session.add_all([tag1, tag2])
    await db_session.commit()

    # Update content tags
    from uuid import uuid4
    content_id = str(uuid4())
    response = await client.put(
        f"/api/v1/tags/content/{content_id}/tags",
        json={"tag_names": ["技术", "学习"]},
        headers=auth_headers
    )

    assert response.status_code == 200

    # Verify tags were assigned
    from sqlalchemy import select
    stmt = select(ContentTag).where(ContentTag.content_id == content_id)
    result = await db_session.execute(stmt)
    content_tags = result.scalars().all()
    assert len(content_tags) == 2


@pytest.mark.asyncio
async def test_update_content_tags_auto_creates_new_tags(client: AsyncClient, auth_headers, db_session):
    """Test that updating content tags auto-creates missing tags."""
    # Create one existing tag
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    db_session.add(tag1)
    await db_session.commit()

    # Update content with existing + new tags
    from uuid import uuid4
    content_id = str(uuid4())
    response = await client.put(
        f"/api/v1/tags/content/{content_id}/tags",
        json={"tag_names": ["技术", "投资", "理财"]},
        headers=auth_headers
    )

    assert response.status_code == 200

    # Verify new tags were created
    from sqlalchemy import select
    stmt = select(UserTag).where(
        UserTag.user_id == "test_user",
        UserTag.deleted_at.is_(None)
    )
    result = await db_session.execute(stmt)
    all_tags = result.scalars().all()
    tag_names = [t.tag_name for t in all_tags]
    assert len(tag_names) == 3
    assert "技术" in tag_names
    assert "投资" in tag_names
    assert "理财" in tag_names


@pytest.mark.asyncio
async def test_update_content_tags_replaces_existing(client: AsyncClient, auth_headers, db_session):
    """Test that updating content tags replaces existing tags."""
    # Create tags
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习")
    tag3 = UserTag(user_id="test_user", tag_name="投资")
    db_session.add_all([tag1, tag2, tag3])
    await db_session.flush()

    # Create content with initial tags
    from uuid import uuid4
    content_id = str(uuid4())
    ct1 = ContentTag(content_id=content_id, tag_id=tag1.id, user_id="test_user")
    ct2 = ContentTag(content_id=content_id, tag_id=tag2.id, user_id="test_user")
    db_session.add_all([ct1, ct2])
    await db_session.commit()

    # Update tags (replace with different set)
    response = await client.put(
        f"/api/v1/tags/content/{content_id}/tags",
        json={"tag_names": ["学习", "投资"]},
        headers=auth_headers
    )

    assert response.status_code == 200

    # Verify only new tags are assigned
    from sqlalchemy import select
    stmt = (
        select(UserTag.tag_name)
        .join(ContentTag, UserTag.id == ContentTag.tag_id)
        .where(ContentTag.content_id == content_id)
    )
    result = await db_session.execute(stmt)
    tags = [row[0] for row in result.all()]
    assert len(tags) == 2
    assert "学习" in tags
    assert "投资" in tags
    assert "技术" not in tags  # Should be removed
```

**Step 2: Run tests to verify they fail**

Run: `cd backend && pytest tests/routers/test_tags.py::test_get_content_tags -v`
Expected: FAIL with 405 (method not allowed)

**Step 3: Implement content tag endpoints**

Add to `backend/app/routers/tags.py`:
```python
@router.get("/content/{content_id}/tags", response_model=list[str])
async def get_content_tags(
    content_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Get tags for a specific content item."""
    stmt = (
        select(UserTag.tag_name)
        .join(ContentTag, UserTag.id == ContentTag.tag_id)
        .where(
            ContentTag.content_id == content_id,
            ContentTag.user_id == user_id,
            UserTag.deleted_at.is_(None),
        )
    )
    result = await db.execute(stmt)
    return [row[0] for row in result.all()]


@router.put("/content/{content_id}/tags")
async def update_content_tags(
    content_id: str,
    request: ContentTagsUpdateRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Update tags for a content item (auto-create missing tags)."""
    # Remove all existing tags for this content
    stmt = delete(ContentTag).where(
        ContentTag.content_id == content_id,
        ContentTag.user_id == user_id,
    )
    await db.execute(stmt)

    # Get or create tags
    for tag_name in request.tag_names:
        # Check if tag exists
        stmt = select(UserTag).where(
            UserTag.user_id == user_id,
            UserTag.tag_name == tag_name,
            UserTag.deleted_at.is_(None),
        )
        result = await db.execute(stmt)
        tag = result.scalar_one_or_none()

        if not tag:
            # Create new tag
            tag = UserTag(user_id=user_id, tag_name=tag_name)
            db.add(tag)
            await db.flush()  # Get tag.id

        # Create content-tag relationship
        content_tag = ContentTag(
            content_id=content_id,
            tag_id=tag.id,
            user_id=user_id,
        )
        db.add(content_tag)

    await db.commit()
    return {"message": "Tags updated successfully"}
```

**Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/routers/test_tags.py::test_get_content_tags tests/routers/test_tags.py::test_update_content_tags_with_existing_tags tests/routers/test_tags.py::test_update_content_tags_auto_creates_new_tags tests/routers/test_tags.py::test_update_content_tags_replaces_existing -v`
Expected: All tests pass

**Step 5: Commit**

```bash
git add backend/app/routers/tags.py backend/tests/routers/test_tags.py
git commit -m "feat(api): add content tag management endpoints

- GET /api/v1/tags/content/{id}/tags - get content tags
- PUT /api/v1/tags/content/{id}/tags - update content tags
- Auto-create tags that don't exist in user library
- Replace existing tags (delete + insert)
- Add comprehensive tests

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 9: Add Filter Content by Tag Endpoint

**Files:**
- Modify: `backend/app/routers/tags.py`
- Test: `backend/tests/routers/test_tags.py`

**Step 1: Write failing test**

Add to `backend/tests/routers/test_tags.py`:
```python
@pytest.mark.asyncio
async def test_filter_contents_by_tag(client: AsyncClient, auth_headers, db_session):
    """Test filtering content items by tag."""
    # Create tag
    tag = UserTag(user_id="test_user", tag_name="技术")
    db_session.add(tag)
    await db_session.flush()

    # Create content items (simplified - you may need to create properly with all fields)
    from uuid import uuid4
    from app.models.content import Content

    content1_id = str(uuid4())
    content2_id = str(uuid4())
    content3_id = str(uuid4())

    # Assign tag to content1 and content2
    ct1 = ContentTag(content_id=content1_id, tag_id=tag.id, user_id="test_user")
    ct2 = ContentTag(content_id=content2_id, tag_id=tag.id, user_id="test_user")
    db_session.add_all([ct1, ct2])
    await db_session.commit()

    # Filter by tag
    response = await client.get(f"/api/v1/tags/{tag.id}/contents", headers=auth_headers)

    assert response.status_code == 200
    contents = response.json()

    # Should return content1 and content2, but not content3
    content_ids = [c["id"] for c in contents]
    assert content1_id in content_ids
    assert content2_id in content_ids
    assert content3_id not in content_ids
```

**Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/routers/test_tags.py::test_filter_contents_by_tag -v`
Expected: FAIL with 405 (method not allowed)

**Step 3: Implement filter endpoint**

Add to `backend/app/routers/tags.py`:
```python
from app.models.content import Content
from app.schemas.content import ContentResponse


@router.get("/{tag_id}/contents", response_model=list[ContentResponse])
async def filter_contents_by_tag(
    tag_id: int,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Get all content items with this tag."""
    # Verify tag ownership
    stmt = select(UserTag).where(
        UserTag.id == tag_id,
        UserTag.user_id == user_id,
        UserTag.deleted_at.is_(None),
    )
    result = await db.execute(stmt)
    tag = result.scalar_one_or_none()

    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")

    # Get content items with this tag
    stmt = (
        select(Content)
        .join(ContentTag, Content.id == ContentTag.content_id)
        .where(
            ContentTag.tag_id == tag_id,
            ContentTag.user_id == user_id,
        )
        .order_by(Content.created_at.desc())
    )
    result = await db.execute(stmt)
    contents = result.scalars().all()

    # Build responses with tags
    responses = []
    for content in contents:
        # Get tags for this content
        tag_stmt = (
            select(UserTag.tag_name)
            .join(ContentTag, UserTag.id == ContentTag.tag_id)
            .where(
                ContentTag.content_id == content.id,
                UserTag.deleted_at.is_(None),
            )
        )
        tag_result = await db.execute(tag_stmt)
        tags = [row[0] for row in tag_result.all()]

        responses.append(
            ContentResponse(
                id=content.id,
                title=content.title,
                source_url=content.source_url,
                source_type=content.source_type,
                source_app_name=content.source_app_name,
                source_app_bundle_id=content.source_app_bundle_id,
                source_language=content.source_language,
                l0_summary=content.l0_summary,
                l1_outline=content.l1_outline,
                tags=tags,
                status=content.status,
                created_at=content.created_at,
                updated_at=content.updated_at,
                podcast_url=None,  # TODO: Add podcast URL if needed
            )
        )

    return responses
```

**Step 4: Run test to verify it passes**

Run: `cd backend && pytest tests/routers/test_tags.py::test_filter_contents_by_tag -v`
Expected: Test passes (may need to adjust based on Content model requirements)

**Step 5: Commit**

```bash
git add backend/app/routers/tags.py backend/tests/routers/test_tags.py
git commit -m "feat(api): add GET /api/v1/tags/{id}/contents endpoint

- Filter content items by tag
- Return full ContentResponse with tags
- Verify tag ownership
- Order by created_at descending
- Add test

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 3: AI Integration

### Task 10: Modify Summarization Service for Tag Selection

**Files:**
- Modify: `backend/app/services/summarizer.py`
- Test: `backend/tests/services/test_summarizer.py`

**Step 1: Write failing test**

Add to `backend/tests/services/test_summarizer.py`:
```python
@pytest.mark.asyncio
async def test_generate_summary_with_user_tags(db_session):
    """Test that summary generation includes user's tag library in prompt."""
    from app.services.summarizer import _get_summarizer, SummarizationService
    from app.models.user_tag import UserTag

    # Create user tags
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习")
    tag3 = UserTag(user_id="test_user", tag_name="投资")
    db_session.add_all([tag1, tag2, tag3])
    await db_session.commit()

    # Mock OpenAI response
    from unittest.mock import AsyncMock, patch
    mock_response = {
        "l0_summary": "Test summary",
        "l1_outline": [{"point": "Point 1", "anchors": ["¶1"]}],
        "tags": ["技术", "学习"],
        "keywords": ["test", "keyword"]
    }

    with patch("app.services.summarizer.openai_client") as mock_client:
        mock_client.chat.completions.create = AsyncMock(return_value=MockResponse(mock_response))

        summarizer = _get_summarizer()
        result = await summarizer.generate_summary(
            full_text="Test content about technology and learning",
            paragraphs=["Paragraph 1", "Paragraph 2"],
            user_id="test_user",
            db=db_session,
        )

        # Verify tags are returned
        assert result.tags == ["技术", "学习"]

        # Verify prompt included user's tags
        call_args = mock_client.chat.completions.create.call_args
        messages = call_args.kwargs["messages"]
        system_message = messages[0]["content"]

        assert "技术" in system_message
        assert "学习" in system_message
        assert "投资" in system_message


@pytest.mark.asyncio
async def test_generate_summary_with_no_user_tags(db_session):
    """Test summary generation when user has no tags."""
    from app.services.summarizer import _get_summarizer
    from unittest.mock import AsyncMock, patch

    mock_response = {
        "l0_summary": "Test summary",
        "l1_outline": [{"point": "Point 1", "anchors": ["¶1"]}],
        "tags": [],
        "keywords": ["test"]
    }

    with patch("app.services.summarizer.openai_client") as mock_client:
        mock_client.chat.completions.create = AsyncMock(return_value=MockResponse(mock_response))

        summarizer = _get_summarizer()
        result = await summarizer.generate_summary(
            full_text="Test content",
            paragraphs=["Paragraph 1"],
            user_id="test_user",
            db=db_session,
        )

        # Should return empty tags array
        assert result.tags == []

        # Verify prompt mentions empty tag library
        call_args = mock_client.chat.completions.create.call_args
        messages = call_args.kwargs["messages"]
        system_message = messages[0]["content"]

        assert "Empty array" in system_message or "no tags" in system_message.lower()


class MockResponse:
    """Mock OpenAI API response."""
    def __init__(self, content_dict):
        import json
        self.choices = [
            type('obj', (object,), {
                'message': type('obj', (object,), {
                    'content': json.dumps(content_dict)
                })()
            })()
        ]
```

**Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/services/test_summarizer.py::test_generate_summary_with_user_tags -v`
Expected: FAIL - generate_summary doesn't accept user_id and db parameters

**Step 3: Modify SummarizationService**

Modify `backend/app/services/summarizer.py`:

```python
# Add imports at top
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession


class SummarizationService:
    """Handles content summarization using OpenAI."""

    async def generate_summary(
        self,
        full_text: str,
        paragraphs: list[str],
        user_id: str,  # NEW parameter
        db: AsyncSession,  # NEW parameter
    ) -> SummarizationResult:
        """Generate multi-level summary with AI tag selection from user's library."""

        # 1. Fetch user's tag library
        from app.models.user_tag import UserTag

        stmt = select(UserTag.tag_name).where(
            UserTag.user_id == user_id,
            UserTag.deleted_at.is_(None),
        )
        result = await db.execute(stmt)
        available_tags = [row[0] for row in result.all()]

        # 2. Build tag instruction based on user's library
        if available_tags:
            tag_instruction = f"""- "tags": Select 0-3 most relevant tags from the user's tag library: {available_tags}
  If none of the tags are relevant, return an empty array."""
        else:
            tag_instruction = """- "tags": Empty array (user has no tags in their library yet)."""

        # 3. Build numbered paragraphs for anchoring
        numbered_paragraphs = [
            f"¶{i+1}: {p}" for i, p in enumerate(paragraphs)
        ]
        user_message = "\n\n".join(numbered_paragraphs)

        # Detect language
        has_chinese = any('\u4e00' <= c <= '\u9fff' for c in full_text[:500])
        lang_note = "Chinese" if has_chinese else "English"

        # 4. Build system prompt with tag instruction
        system_prompt = f"""You are a professional content analyst. Generate a multi-level summary in {lang_note}.

Return a JSON object with:
- "l0_summary": one-line summary (≤30 Chinese chars or ≤60 English chars).
- "l1_outline": an array of 3-5 objects, each with:
   - "point": a concise statement of the key idea.
   - "anchors": an array of source paragraph markers (e.g. ["¶1", "¶3"]).
{tag_instruction}
- "keywords": 5-10 keywords.

Return ONLY the JSON object. No markdown, no code blocks."""

        # 5. Call OpenAI API
        response = await openai_client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
            temperature=0.3,
        )

        # 6. Parse response (existing code)
        raw = response.choices[0].message.content.strip()

        # Remove markdown code fences if present
        if raw.startswith("```"):
            lines = raw.split("\n")
            raw = "\n".join(lines[1:-1]) if len(lines) > 2 else raw

        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            raise ValueError(f"Failed to parse AI response as JSON: {raw}") from e

        return SummarizationResult(
            l0_summary=data["l0_summary"],
            l1_outline=[
                OutlinePoint(point=item["point"], anchors=item["anchors"])
                for item in data["l1_outline"]
            ],
            tags=data["tags"],
            keywords=data["keywords"],
        )
```

**Step 4: Run tests to verify they pass**

Run: `cd backend && pytest tests/services/test_summarizer.py::test_generate_summary_with_user_tags tests/services/test_summarizer.py::test_generate_summary_with_no_user_tags -v`
Expected: All tests pass

**Step 5: Commit**

```bash
git add backend/app/services/summarizer.py backend/tests/services/test_summarizer.py
git commit -m "feat(summarizer): add AI tag selection from user library

- Add user_id and db parameters to generate_summary
- Fetch user's tag library before summarization
- Include available tags in AI prompt
- AI selects 0-3 relevant tags from library
- Handle empty tag library case
- Add comprehensive tests

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 11: Update Pipeline Service to Save Tags

**Files:**
- Modify: `backend/app/services/pipeline.py`
- Test: `backend/tests/services/test_pipeline.py`

**Step 1: Write failing test**

Add to `backend/tests/services/test_pipeline.py`:
```python
@pytest.mark.asyncio
async def test_process_content_saves_tags_to_content_tags_table(db_session):
    """Test that pipeline saves AI-selected tags to content_tags table."""
    from app.services.pipeline import _get_pipeline
    from app.models.content import Content
    from app.models.user_tag import UserTag
    from app.models.content_tag import ContentTag
    from unittest.mock import AsyncMock, patch
    from uuid import uuid4

    # Create user tags
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习")
    db_session.add_all([tag1, tag2])
    await db_session.commit()

    # Create content
    content_id = str(uuid4())
    content = Content(
        id=content_id,
        title="Test",
        source_type="text",
        user_id="test_user",
        status="pending",
    )
    db_session.add(content)
    await db_session.commit()

    # Mock summarizer to return tags
    mock_summary = type('obj', (object,), {
        'l0_summary': 'Test summary',
        'l1_outline': [],
        'tags': ['技术', '学习'],
        'keywords': ['test']
    })()

    with patch("app.services.pipeline.summarizer") as mock_summarizer:
        mock_summarizer.generate_summary = AsyncMock(return_value=mock_summary)

        pipeline = _get_pipeline()
        await pipeline.process_content(
            content_id=content_id,
            user_id="test_user",
            db=db_session,
        )

    # Verify content_tags were created
    from sqlalchemy import select
    stmt = (
        select(UserTag.tag_name)
        .join(ContentTag, UserTag.id == ContentTag.tag_id)
        .where(ContentTag.content_id == content_id)
    )
    result = await db_session.execute(stmt)
    assigned_tags = [row[0] for row in result.all()]

    assert len(assigned_tags) == 2
    assert "技术" in assigned_tags
    assert "学习" in assigned_tags
```

**Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/services/test_pipeline.py::test_process_content_saves_tags_to_content_tags_table -v`
Expected: FAIL - tags not saved to content_tags table

**Step 3: Modify ProcessingPipeline**

Modify `backend/app/services/pipeline.py`:

```python
async def process_content(
    self,
    content_id: str,
    user_id: str,
    db: AsyncSession,
) -> None:
    """Process content through extraction and summarization pipeline."""

    # ... existing extraction code ...

    # Generate summary with user's tag library
    summary_result = await summarizer.generate_summary(
        full_text=full_text,
        paragraphs=paragraphs,
        user_id=user_id,  # Pass user_id
        db=db,  # Pass db session
    )

    # Save summary to content
    content.l0_summary = summary_result.l0_summary
    content.l1_outline = [
        {
            "point": point.point,
            "anchors": point.anchors,
        }
        for point in summary_result.l1_outline
    ]
    content.keywords = summary_result.keywords
    # Don't save tags to content model anymore

    # Save tags to content_tags table
    from app.models.user_tag import UserTag
    from app.models.content_tag import ContentTag

    for tag_name in summary_result.tags:
        # Get tag_id from user's library
        stmt = select(UserTag.id).where(
            UserTag.user_id == user_id,
            UserTag.tag_name == tag_name,
            UserTag.deleted_at.is_(None),
        )
        result = await db.execute(stmt)
        tag_id = result.scalar_one_or_none()

        if tag_id:
            # Create content-tag relationship
            content_tag = ContentTag(
                content_id=content_id,
                tag_id=tag_id,
                user_id=user_id,
            )
            db.add(content_tag)

    content.status = "ready"
    await db.commit()
```

**Step 4: Run test to verify it passes**

Run: `cd backend && pytest tests/services/test_pipeline.py::test_process_content_saves_tags_to_content_tags_table -v`
Expected: Test passes

**Step 5: Commit**

```bash
git add backend/app/services/pipeline.py backend/tests/services/test_pipeline.py
git commit -m "feat(pipeline): save AI-selected tags to content_tags table

- Pass user_id and db to summarizer.generate_summary
- Save tags to content_tags instead of content.tags array
- Create content-tag relationships for each AI-selected tag
- Add test for tag saving

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 12: Update Content Router to Return Tags from JOIN

**Files:**
- Modify: `backend/app/routers/content.py`
- Test: `backend/tests/routers/test_content.py`

**Step 1: Write failing test**

Add to `backend/tests/routers/test_content.py`:
```python
@pytest.mark.asyncio
async def test_get_content_returns_tags_from_join(client: AsyncClient, auth_headers, db_session):
    """Test that GET /api/v1/content/{id} returns tags from content_tags table."""
    from app.models.content import Content
    from app.models.user_tag import UserTag
    from app.models.content_tag import ContentTag
    from uuid import uuid4

    # Create content
    content_id = str(uuid4())
    content = Content(
        id=content_id,
        title="Test Article",
        source_type="text",
        user_id="test_user",
        status="ready",
        l0_summary="Test summary",
    )
    db_session.add(content)

    # Create tags
    tag1 = UserTag(user_id="test_user", tag_name="技术")
    tag2 = UserTag(user_id="test_user", tag_name="学习")
    db_session.add_all([tag1, tag2])
    await db_session.flush()

    # Create content-tag relationships
    ct1 = ContentTag(content_id=content_id, tag_id=tag1.id, user_id="test_user")
    ct2 = ContentTag(content_id=content_id, tag_id=tag2.id, user_id="test_user")
    db_session.add_all([ct1, ct2])
    await db_session.commit()

    # Get content
    response = await client.get(f"/api/v1/content/{content_id}", headers=auth_headers)

    assert response.status_code == 200
    data = response.json()

    assert "tags" in data
    assert len(data["tags"]) == 2
    assert "技术" in data["tags"]
    assert "学习" in data["tags"]
```

**Step 2: Run test to verify it fails**

Run: `cd backend && pytest tests/routers/test_content.py::test_get_content_returns_tags_from_join -v`
Expected: FAIL - tags field is None or missing

**Step 3: Create helper function for fetching tags**

Modify `backend/app/routers/content.py`:

```python
# Add at top of file
from app.models.user_tag import UserTag
from app.models.content_tag import ContentTag


async def _get_content_tags(
    content_id: str,
    db: AsyncSession,
) -> list[str]:
    """Helper to fetch tags for a content item."""
    stmt = (
        select(UserTag.tag_name)
        .join(ContentTag, UserTag.id == ContentTag.tag_id)
        .where(
            ContentTag.content_id == content_id,
            UserTag.deleted_at.is_(None),
        )
    )
    result = await db.execute(stmt)
    return [row[0] for row in result.all()]


# Update GET /api/v1/content/{content_id} endpoint
@router.get("/{content_id}", response_model=ContentResponse)
async def get_content(
    content_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Get content by ID."""
    stmt = select(Content).where(
        Content.id == content_id,
        Content.user_id == user_id,
    )
    result = await db.execute(stmt)
    content = result.scalar_one_or_none()

    if not content:
        raise HTTPException(status_code=404, detail="Content not found")

    # Fetch tags via JOIN
    tags = await _get_content_tags(content_id, db)

    return ContentResponse(
        id=content.id,
        title=content.title,
        source_url=content.source_url,
        source_type=content.source_type,
        source_app_name=content.source_app_name,
        source_app_bundle_id=content.source_app_bundle_id,
        source_language=content.source_language,
        l0_summary=content.l0_summary,
        l1_outline=content.l1_outline,
        tags=tags,  # Use fetched tags
        status=content.status,
        created_at=content.created_at,
        updated_at=content.updated_at,
        podcast_url=None,  # TODO: fetch if needed
    )


# Update list endpoint similarly
@router.get("", response_model=list[ContentResponse])
async def list_content(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """List all content for user."""
    stmt = (
        select(Content)
        .where(Content.user_id == user_id)
        .order_by(Content.created_at.desc())
    )
    result = await db.execute(stmt)
    contents = result.scalars().all()

    responses = []
    for content in contents:
        tags = await _get_content_tags(content.id, db)

        responses.append(
            ContentResponse(
                id=content.id,
                title=content.title,
                source_url=content.source_url,
                source_type=content.source_type,
                source_app_name=content.source_app_name,
                source_app_bundle_id=content.source_app_bundle_id,
                source_language=content.source_language,
                l0_summary=content.l0_summary,
                l1_outline=content.l1_outline,
                tags=tags,
                status=content.status,
                created_at=content.created_at,
                updated_at=content.updated_at,
                podcast_url=None,
            )
        )

    return responses
```

**Step 4: Run test to verify it passes**

Run: `cd backend && pytest tests/routers/test_content.py::test_get_content_returns_tags_from_join -v`
Expected: Test passes

**Step 5: Commit**

```bash
git add backend/app/routers/content.py backend/tests/routers/test_content.py
git commit -m "feat(content): fetch tags from content_tags via JOIN

- Add _get_content_tags helper function
- Update GET /api/v1/content/{id} to fetch tags via JOIN
- Update GET /api/v1/content to fetch tags for all items
- Exclude soft-deleted tags
- Add test

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 4: macOS Frontend

### Task 13: Create UserTag Model (Swift)

**Files:**
- Create: `macos/Sources/Core/Models/Tag.swift`

**Step 1: Create Tag model**

Create `macos/Sources/Core/Models/Tag.swift`:
```swift
import Foundation

// MARK: - User Tag

public struct UserTag: Identifiable, Codable, Sendable {
    public let id: Int
    public var tagName: String
    public var contentCount: Int
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case contentCount = "content_count"
        case createdAt = "created_at"
    }

    public init(
        id: Int,
        tagName: String,
        contentCount: Int,
        createdAt: Date
    ) {
        self.id = id
        self.tagName = tagName
        self.contentCount = contentCount
        self.createdAt = createdAt
    }
}
```

**Step 2: Commit**

```bash
git add macos/Sources/Core/Models/Tag.swift
git commit -m "feat(macos): add UserTag model

- Add UserTag struct with id, tagName, contentCount, createdAt
- Conform to Identifiable, Codable, Sendable
- Map snake_case API fields to camelCase

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 14: Add Tag API Methods to APIClient

**Files:**
- Modify: `macos/Sources/Networking/APIClient.swift`

**Step 1: Add tag-related methods**

Add to `macos/Sources/Networking/APIClient.swift`:

```swift
// Add import at top
import Core

// Add methods to APIClient class

/// Fetch user's tag library
func fetchUserTags() async throws -> [UserTag] {
    let url = baseURL.appendingPathComponent("/api/v1/tags")
    var request = URLRequest(url: url)
    request.setValue("Bearer \(getAuthToken())", forHTTPHeaderField: "Authorization")

    let (data, _) = try await session.data(for: request)
    return try decoder.decode([UserTag].self, from: data)
}

/// Create a new tag
func createTag(name: String) async throws -> UserTag {
    let url = baseURL.appendingPathComponent("/api/v1/tags")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(getAuthToken())", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ["tag_name": name]
    request.httpBody = try encoder.encode(body)

    let (data, _) = try await session.data(for: request)
    return try decoder.decode(UserTag.self, from: data)
}

/// Delete a tag
func deleteTag(id: Int) async throws {
    let url = baseURL.appendingPathComponent("/api/v1/tags/\(id)")
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("Bearer \(getAuthToken())", forHTTPHeaderField: "Authorization")

    let (_, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw APIError.invalidResponse
    }
}

/// Update tags for a content item
func updateContentTags(contentId: String, tags: [String]) async throws {
    let url = baseURL.appendingPathComponent("/api/v1/tags/content/\(contentId)/tags")
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("Bearer \(getAuthToken())", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ["tag_names": tags]
    request.httpBody = try encoder.encode(body)

    let (_, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw APIError.invalidResponse
    }
}

/// Fetch content items by tag
func fetchContentsByTag(tagId: Int) async throws -> [Content] {
    let url = baseURL.appendingPathComponent("/api/v1/tags/\(tagId)/contents")
    var request = URLRequest(url: url)
    request.setValue("Bearer \(getAuthToken())", forHTTPHeaderField: "Authorization")

    let (data, _) = try await session.data(for: request)
    return try decoder.decode([Content].self, from: data)
}
```

**Step 2: Commit**

```bash
git add macos/Sources/Networking/APIClient.swift
git commit -m "feat(macos): add tag API methods to APIClient

- fetchUserTags() - get user's tag library
- createTag(name:) - create new tag
- deleteTag(id:) - delete tag
- updateContentTags(contentId:tags:) - update content tags
- fetchContentsByTag(tagId:) - filter content by tag

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 15: Create TagManager Service

**Files:**
- Create: `macos/Sources/App/Services/TagManager.swift`

**Step 1: Create TagManager**

Create `macos/Sources/App/Services/TagManager.swift`:
```swift
import Foundation
import Core
import Networking

/// Manages user's tag library and tag filtering
@Observable
@MainActor
final class TagManager {
    private let apiClient: APIClient

    // MARK: - State

    /// User's tag library
    var userTags: [UserTag] = []

    /// Currently selected tag for filtering (nil = show all)
    var selectedTagId: Int?

    /// Loading state
    var isLoading = false

    /// Error state
    var error: Error?

    // MARK: - Initialization

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Public Methods

    /// Load user's tag library
    func loadUserTags() async {
        isLoading = true
        defer { isLoading = false }

        do {
            userTags = try await apiClient.fetchUserTags()
            error = nil
        } catch {
            self.error = error
            print("[TagManager] Failed to load tags: \(error)")
        }
    }

    /// Create a new tag
    func createTag(name: String) async throws {
        let tag = try await apiClient.createTag(name: name)
        userTags.append(tag)
        error = nil
    }

    /// Delete a tag
    func deleteTag(id: Int) async throws {
        try await apiClient.deleteTag(id: id)
        userTags.removeAll { $0.id == id }

        // Clear selection if deleted tag was selected
        if selectedTagId == id {
            selectedTagId = nil
        }

        error = nil
    }

    /// Select a tag for filtering (nil to show all)
    func selectTag(_ tagId: Int?) {
        selectedTagId = tagId
    }

    /// Clear tag selection
    func clearSelection() {
        selectedTagId = nil
    }
}
```

**Step 2: Commit**

```bash
git add macos/Sources/App/Services/TagManager.swift
git commit -m "feat(macos): add TagManager service

- Manage user's tag library state
- Load, create, delete tags
- Track selected tag for filtering
- Observable for SwiftUI integration

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 16: Inject TagManager into App

**Files:**
- Modify: `macos/Sources/App/ReadlessApp.swift`

**Step 1: Add TagManager to app**

Modify `macos/Sources/App/ReadlessApp.swift`:
```swift
@main
struct ReadlessApp: App {
    @State private var contentManager = ContentManager()
    @State private var tagManager = TagManager()  // Add this line

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(contentManager)
                .environment(tagManager)  // Add this line
        }
    }
}
```

**Step 2: Commit**

```bash
git add macos/Sources/App/ReadlessApp.swift
git commit -m "feat(macos): inject TagManager into app environment

- Add TagManager to app state
- Inject into environment for SwiftUI views

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 17: Add Knowledge Section to Sidebar

**Files:**
- Modify: `macos/Sources/App/Views/SidebarView.swift` (or create if doesn't exist)

**Step 1: Update sidebar to show tags**

Note: The exact file path may vary. Find the sidebar view and add:

```swift
import SwiftUI
import Core

struct SidebarView: View {
    @Environment(ContentManager.self) private var contentManager
    @Environment(TagManager.self) private var tagManager

    var body: some View {
        List {
            // Existing Library section
            Section("Library") {
                NavigationLink(value: SidebarItem.allItems) {
                    Label("All Items", systemImage: "tray.fill")
                }
                NavigationLink(value: SidebarItem.unread) {
                    Label("Unread", systemImage: "circle")
                }
                // ... other items
            }

            // New Knowledge section
            Section("Knowledge") {
                ForEach(tagManager.userTags) { tag in
                    Button {
                        tagManager.selectTag(tag.id)
                        Task {
                            await filterByTag(tag.id)
                        }
                    } label: {
                        HStack {
                            Label(tag.tagName, systemImage: "tag")
                            Spacer()
                            Text("\(tag.contentCount)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete Tag", role: .destructive) {
                            Task {
                                try? await tagManager.deleteTag(id: tag.id)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await tagManager.loadUserTags()
        }
    }

    private func filterByTag(_ tagId: Int) async {
        // This will be implemented in ContentManager
        // For now, just a placeholder
        print("[Sidebar] Filter by tag \(tagId)")
    }
}

enum SidebarItem {
    case allItems
    case unread
    // ... other cases
}
```

**Step 2: Commit**

```bash
git add macos/Sources/App/Views/SidebarView.swift
git commit -m "feat(macos): add Knowledge section to sidebar

- Display user's tag library in sidebar
- Show content count for each tag
- Add context menu to delete tags
- Load tags on view appear

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 18: Add Tag Filtering to ContentManager

**Files:**
- Modify: `macos/Sources/App/Services/ContentManager.swift`

**Step 1: Add filterByTag method**

Add to `macos/Sources/App/Services/ContentManager.swift`:
```swift
/// Filter content items by tag
func filterByTag(tagId: Int) async {
    isLoading = true
    defer { isLoading = false }

    do {
        let filteredContent = try await apiClient.fetchContentsByTag(tagId: tagId)
        contents = filteredContent
        error = nil
    } catch {
        self.error = error
        print("[ContentManager] Failed to filter by tag: \(error)")
    }
}

/// Clear tag filter and show all content
func clearTagFilter() async {
    await loadContents()
}
```

**Step 2: Update sidebar to use filterByTag**

Modify `macos/Sources/App/Views/SidebarView.swift`:
```swift
private func filterByTag(_ tagId: Int) async {
    await contentManager.filterByTag(tagId: tagId)
}
```

**Step 3: Commit**

```bash
git add macos/Sources/App/Services/ContentManager.swift macos/Sources/App/Views/SidebarView.swift
git commit -m "feat(macos): add tag filtering to ContentManager

- filterByTag(tagId:) - filter content by tag
- clearTagFilter() - show all content
- Update sidebar to trigger filtering

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 19: Create Tag UI Components

**Files:**
- Create: `macos/Sources/App/Views/Components/TagsView.swift`
- Create: `macos/Sources/App/Views/Components/TagChip.swift`

**Step 1: Create TagChip component**

Create `macos/Sources/App/Views/Components/TagChip.swift`:
```swift
import SwiftUI

/// A single tag chip with optional remove button
struct TagChip: View {
    let text: String
    let onRemove: (() -> Void)?

    init(text: String, onRemove: (() -> Void)? = nil) {
        self.text = text
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(12)
    }
}
```

**Step 2: Create TagsView component**

Create `macos/Sources/App/Views/Components/TagsView.swift`:
```swift
import SwiftUI

/// Display and manage tags for a content item
struct TagsView: View {
    let tags: [String]
    let availableTags: [String]
    let onAdd: (String) async -> Void
    let onRemove: (String) async -> Void

    @State private var showingTagPicker = false
    @State private var newTagName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Display existing tags
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(text: tag) {
                        Task {
                            await onRemove(tag)
                        }
                    }
                }

                // Add button
                Button {
                    showingTagPicker = true
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .popover(isPresented: $showingTagPicker) {
            TagPickerView(
                availableTags: availableTags.filter { !tags.contains($0) },
                newTagName: $newTagName,
                onSelect: { tag in
                    Task {
                        await onAdd(tag)
                        showingTagPicker = false
                    }
                },
                onCreateNew: {
                    Task {
                        await onAdd(newTagName)
                        newTagName = ""
                        showingTagPicker = false
                    }
                }
            )
            .frame(width: 250, height: 300)
        }
    }
}

/// Popover for selecting or creating tags
struct TagPickerView: View {
    let availableTags: [String]
    @Binding var newTagName: String
    let onSelect: (String) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Tag")
                .font(.headline)

            // Create new tag
            HStack {
                TextField("New tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                Button("Create") {
                    onCreateNew()
                }
                .disabled(newTagName.isEmpty)
            }

            Divider()

            // Select existing tag
            Text("Or select existing:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            onSelect(tag)
                        } label: {
                            HStack {
                                Image(systemName: "tag")
                                Text(tag)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }

                    if availableTags.isEmpty {
                        Text("No available tags")
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
            }
        }
        .padding()
    }
}

/// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
```

**Step 3: Commit**

```bash
git add macos/Sources/App/Views/Components/TagChip.swift macos/Sources/App/Views/Components/TagsView.swift
git commit -m "feat(macos): add tag UI components

- TagChip: display single tag with remove button
- TagsView: display and manage content tags
- TagPickerView: popover to select or create tags
- FlowLayout: custom layout for tag chips

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 20: Add Tags to ReaderView

**Files:**
- Modify: `macos/Sources/App/Views/ReaderView.swift`

**Step 1: Add TagsView to ReaderView**

Modify `macos/Sources/App/Views/ReaderView.swift`:
```swift
import SwiftUI
import Core

struct ReaderView: View {
    let content: Content

    @Environment(ContentManager.self) private var contentManager
    @Environment(TagManager.self) private var tagManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(content.title)
                    .font(.title)
                    .fontWeight(.bold)

                // Tags
                TagsView(
                    tags: content.tags,
                    availableTags: tagManager.userTags.map(\.tagName),
                    onAdd: { tagName in
                        await addTag(tagName)
                    },
                    onRemove: { tagName in
                        await removeTag(tagName)
                    }
                )

                // L0 Summary
                if let l0Summary = content.l0Summary {
                    Text(l0Summary)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                // L1 Outline
                // ... existing outline display code
            }
            .padding()
        }
    }

    private func addTag(_ tagName: String) async {
        var newTags = content.tags
        if !newTags.contains(tagName) {
            newTags.append(tagName)

            do {
                try await APIClient.shared.updateContentTags(
                    contentId: content.id,
                    tags: newTags
                )

                // Refresh content
                await contentManager.refreshContent(id: content.id)

                // Reload tags to update counts
                await tagManager.loadUserTags()
            } catch {
                print("[ReaderView] Failed to add tag: \(error)")
            }
        }
    }

    private func removeTag(_ tagName: String) async {
        var newTags = content.tags
        newTags.removeAll { $0 == tagName }

        do {
            try await APIClient.shared.updateContentTags(
                contentId: content.id,
                tags: newTags
            )

            // Refresh content
            await contentManager.refreshContent(id: content.id)

            // Reload tags to update counts
            await tagManager.loadUserTags()
        } catch {
            print("[ReaderView] Failed to remove tag: \(error)")
        }
    }
}
```

**Step 2: Add refreshContent method to ContentManager**

Add to `macos/Sources/App/Services/ContentManager.swift`:
```swift
/// Refresh a single content item
func refreshContent(id: String) async {
    do {
        let updatedContent = try await apiClient.fetchContent(id: id)

        // Update in array
        if let index = contents.firstIndex(where: { $0.id == id }) {
            contents[index] = updatedContent
        }

        // Update selected if it's the same
        if selectedContent?.id == id {
            selectedContent = updatedContent
        }

        error = nil
    } catch {
        self.error = error
        print("[ContentManager] Failed to refresh content: \(error)")
    }
}
```

**Step 3: Add fetchContent method to APIClient**

Add to `macos/Sources/Networking/APIClient.swift`:
```swift
/// Fetch a single content item by ID
func fetchContent(id: String) async throws -> Content {
    let url = baseURL.appendingPathComponent("/api/v1/content/\(id)")
    var request = URLRequest(url: url)
    request.setValue("Bearer \(getAuthToken())", forHTTPHeaderField: "Authorization")

    let (data, _) = try await session.data(for: request)
    return try decoder.decode(Content.self, from: data)
}
```

**Step 4: Commit**

```bash
git add macos/Sources/App/Views/ReaderView.swift macos/Sources/App/Services/ContentManager.swift macos/Sources/Networking/APIClient.swift
git commit -m "feat(macos): add tag management to ReaderView

- Display tags in ReaderView
- Add/remove tags inline
- Auto-refresh content and tag counts after changes
- Add fetchContent and refreshContent methods

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 5: Testing & Polish

### Task 21: Run All Backend Tests

**Step 1: Run all backend tests**

Run: `cd backend && pytest -v`
Expected: All tests pass

**Step 2: Fix any failing tests**

If tests fail, fix them and commit the fixes.

**Step 3: Commit if fixes were needed**

```bash
git add backend/tests/
git commit -m "test: fix failing tests after tag system implementation

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 22: Run Backend Server and Test API Manually

**Step 1: Start backend server**

Run: `cd backend && uvicorn app.main:app --reload`

**Step 2: Test API endpoints manually**

Use curl or Postman to test:
- GET /api/v1/tags (should return empty array initially)
- POST /api/v1/tags (create a tag)
- GET /api/v1/tags (should return the created tag)
- PUT /api/v1/tags/content/{id}/tags (assign tags to content)
- GET /api/v1/content/{id} (should include tags)
- DELETE /api/v1/tags/{id} (delete tag)

**Step 3: Document any issues**

If issues are found, create GitHub issues or fix immediately.

---

### Task 23: Build and Test macOS App

**Step 1: Build macOS app**

Run: `cd macos && swift build`
Expected: Build succeeds

**Step 2: Run macOS app**

Run: `cd macos && swift run App`

**Step 3: Test tag functionality**

Manual testing:
1. Open app, verify sidebar shows "Knowledge" section (empty initially)
2. Create content, verify tags are auto-assigned by AI
3. Add tag manually to content, verify it appears in sidebar
4. Click tag in sidebar, verify content filters
5. Delete tag, verify it's removed from content and sidebar

**Step 4: Document any bugs**

If bugs are found, create issues or fix immediately.

---

### Task 24: Update Documentation

**Files:**
- Modify: `README.md` or `CLAUDE.md`

**Step 1: Document tag system**

Add section to documentation:
```markdown
## Tag System

### Overview
Users can organize content using customizable tags. Tags are:
- User-specific and isolated
- Auto-suggested by AI during summarization
- Manageable inline when viewing content
- Filterable in the sidebar

### API Endpoints
- `GET /api/v1/tags` - List user's tags
- `POST /api/v1/tags` - Create tag
- `DELETE /api/v1/tags/{id}` - Delete tag
- `GET /api/v1/tags/content/{id}/tags` - Get content tags
- `PUT /api/v1/tags/content/{id}/tags` - Update content tags
- `GET /api/v1/tags/{id}/contents` - Filter content by tag

### Database Schema
- `user_tags` - User's tag library (with logical deletion)
- `content_tags` - Many-to-many content-tag relationships

### Frontend Features
- Sidebar "Knowledge" section displays tags with counts
- Inline tag editing in ReaderView
- Tag filtering by clicking tags in sidebar
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add tag system documentation

- Document API endpoints
- Document database schema
- Document frontend features

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Execution Summary

This plan implements the complete user tag system in 24 bite-sized tasks:

**Phase 1: Backend Database (Tasks 1-3)**
- Create UserTag and ContentTag models
- Create database migration
- Remove tags array from Content model

**Phase 2: Backend API (Tasks 4-9)**
- Create tag schemas
- Implement tag CRUD endpoints
- Implement content tag management
- Implement tag filtering

**Phase 3: AI Integration (Tasks 10-12)**
- Modify summarizer to fetch and use user tags
- Update pipeline to save tags to content_tags
- Update content router to return tags via JOIN

**Phase 4: macOS Frontend (Tasks 13-20)**
- Create UserTag model (Swift)
- Add tag API methods to APIClient
- Create TagManager service
- Update sidebar with Knowledge section
- Create tag UI components
- Add tag management to ReaderView

**Phase 5: Testing (Tasks 21-24)**
- Run all backend tests
- Manual API testing
- Build and test macOS app
- Update documentation

Each task follows TDD principles with tests written first, followed by minimal implementation, and frequent commits.

---

**Total Estimated Time:** 8-12 hours for skilled developer
**Tasks:** 24
**Commits:** ~24 (one per task)
