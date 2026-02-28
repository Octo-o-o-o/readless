"""Tests that verify ORM model structure without requiring a running database."""

from sqlalchemy import inspect

from app.models.channel import Channel
from app.models.content import Content
from app.models.paragraph import Paragraph
from app.models.podcast import Podcast


def _column_names(model):
    """Return a set of column names for a mapped model class."""
    mapper = inspect(model)
    return {col.key for col in mapper.columns}


def _table_indexes(model):
    """Return a list of index names defined on a model's table."""
    return [idx.name for idx in model.__table__.indexes]


# ---------------------------------------------------------------------------
# Content
# ---------------------------------------------------------------------------

class TestContentModel:
    def test_tablename(self):
        assert Content.__tablename__ == "contents"

    def test_required_columns(self):
        cols = _column_names(Content)
        expected = {
            "id",
            "title",
            "source_url",
            "source_type",
            "source_app_name",
            "source_app_bundle_id",
            "channel",
            "l0_summary",
            "l1_outline",
            "tags",
            "keywords",
            "full_text",
            "full_text_tsv",
            "status",
            "user_id",
            "created_at",
            "updated_at",
        }
        assert expected.issubset(cols), f"Missing columns: {expected - cols}"

    def test_primary_key(self):
        mapper = inspect(Content)
        pk_cols = [col.key for col in mapper.columns if col.primary_key]
        assert pk_cols == ["id"]

    def test_indexes_exist(self):
        index_names = _table_indexes(Content)
        assert "ix_contents_full_text_tsv" in index_names
        assert "ix_contents_tags" in index_names
        assert "ix_contents_keywords" in index_names
        assert "ix_contents_l1_outline" in index_names
        assert "ix_contents_user_created" in index_names

    def test_default_values(self):
        mapper = inspect(Content)
        col_map = {col.key: col for col in mapper.columns}
        assert col_map["channel"].default.arg == "manual"
        assert col_map["status"].default.arg == "pending"


# ---------------------------------------------------------------------------
# Paragraph
# ---------------------------------------------------------------------------

class TestParagraphModel:
    def test_tablename(self):
        assert Paragraph.__tablename__ == "paragraphs"

    def test_required_columns(self):
        cols = _column_names(Paragraph)
        expected = {
            "id",
            "content_id",
            "anchor_id",
            "text",
            "position",
            "full_text_tsv",
        }
        assert expected.issubset(cols), f"Missing columns: {expected - cols}"

    def test_primary_key_autoincrement(self):
        mapper = inspect(Paragraph)
        pk_cols = [col for col in mapper.columns if col.primary_key]
        assert len(pk_cols) == 1
        assert pk_cols[0].key == "id"
        assert pk_cols[0].autoincrement is True or pk_cols[0].autoincrement == "auto"

    def test_foreign_key_cascade(self):
        col = Paragraph.__table__.c.content_id
        fk = list(col.foreign_keys)[0]
        assert fk.column.table.name == "contents"
        assert fk.ondelete == "CASCADE"

    def test_indexes_exist(self):
        index_names = _table_indexes(Paragraph)
        assert "ix_paragraphs_content_anchor" in index_names
        assert "ix_paragraphs_full_text_tsv" in index_names


# ---------------------------------------------------------------------------
# Podcast
# ---------------------------------------------------------------------------

class TestPodcastModel:
    def test_tablename(self):
        assert Podcast.__tablename__ == "podcasts"

    def test_required_columns(self):
        cols = _column_names(Podcast)
        expected = {
            "id",
            "content_id",
            "audio_url",
            "script",
            "chapters",
            "status",
            "created_at",
        }
        assert expected.issubset(cols), f"Missing columns: {expected - cols}"

    def test_foreign_key_cascade(self):
        col = Podcast.__table__.c.content_id
        fk = list(col.foreign_keys)[0]
        assert fk.column.table.name == "contents"
        assert fk.ondelete == "CASCADE"

    def test_default_status(self):
        mapper = inspect(Podcast)
        col_map = {col.key: col for col in mapper.columns}
        assert col_map["status"].default.arg == "generating"


# ---------------------------------------------------------------------------
# Channel
# ---------------------------------------------------------------------------

class TestChannelModel:
    def test_tablename(self):
        assert Channel.__tablename__ == "channels"

    def test_required_columns(self):
        cols = _column_names(Channel)
        expected = {
            "id",
            "user_id",
            "type",
            "name",
            "config",
            "is_active",
            "last_synced_at",
            "created_at",
        }
        assert expected.issubset(cols), f"Missing columns: {expected - cols}"

    def test_default_is_active(self):
        mapper = inspect(Channel)
        col_map = {col.key: col for col in mapper.columns}
        assert col_map["is_active"].default.arg is True


# ---------------------------------------------------------------------------
# __init__.py re-exports
# ---------------------------------------------------------------------------

class TestModelsInit:
    def test_all_models_importable(self):
        from app.models import Channel, Content, Paragraph, Podcast

        assert Content.__tablename__ == "contents"
        assert Paragraph.__tablename__ == "paragraphs"
        assert Podcast.__tablename__ == "podcasts"
        assert Channel.__tablename__ == "channels"
