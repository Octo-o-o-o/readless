"""Tests for ContentTag model - verifies model structure without database."""

from sqlalchemy import inspect
from app.models.content_tag import ContentTag


def test_content_tag_relationship_structure():
    """Test ContentTag model structure for content-tag relationships."""
    mapper = inspect(ContentTag)

    # Verify table name
    assert mapper.local_table.name == "content_tags"

    # Verify composite primary key
    pk_cols = {col.name for col in mapper.primary_key}
    assert pk_cols == {"content_id", "tag_id"}

    # Verify all required columns exist
    columns = {col.name: col for col in mapper.columns}
    assert "content_id" in columns
    assert "tag_id" in columns
    assert "user_id" in columns
    assert "created_at" in columns

    # Verify content_id is String(36)
    assert str(columns["content_id"].type) == "VARCHAR(36)"

    # Verify tag_id is Integer
    assert "INTEGER" in str(columns["tag_id"].type).upper()

    # Verify user_id is String(100)
    assert str(columns["user_id"].type) == "VARCHAR(100)"

    # Verify user_id is not nullable
    assert columns["user_id"].nullable is False


def test_content_tag_cascade_delete_configuration():
    """Test CASCADE delete foreign key constraints are properly configured."""
    mapper = inspect(ContentTag)

    # Get foreign keys
    fks = list(mapper.local_table.foreign_keys)

    # Should have exactly 2 foreign keys
    assert len(fks) == 2

    # Check CASCADE delete on both foreign keys
    fk_details = {fk.parent.name: fk for fk in fks}

    # Verify content_id FK to contents.id with CASCADE
    content_fk = fk_details["content_id"]
    assert "contents.id" in str(content_fk.target_fullname)
    assert content_fk.ondelete == "CASCADE"

    # Verify tag_id FK to user_tags.id with CASCADE
    tag_fk = fk_details["tag_id"]
    assert "user_tags.id" in str(tag_fk.target_fullname)
    assert tag_fk.ondelete == "CASCADE"
