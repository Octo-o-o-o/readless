"""add content jobs

Revision ID: 010
Revises: 009
Create Date: 2026-03-18

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "010"
down_revision: str | Sequence[str] | None = "009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "content_jobs",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("content_id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("source_type", sa.String(length=20), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default="queued",
        ),
        sa.Column(
            "attempts",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column(
            "scheduled_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(
            ["content_id"],
            ["contents.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("content_id"),
    )
    op.create_index(
        "ix_content_jobs_status_scheduled",
        "content_jobs",
        ["status", "scheduled_at"],
        unique=False,
    )
    op.create_index(
        "ix_content_jobs_user_created",
        "content_jobs",
        ["user_id", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_content_jobs_user_created", table_name="content_jobs")
    op.drop_index("ix_content_jobs_status_scheduled", table_name="content_jobs")
    op.drop_table("content_jobs")
