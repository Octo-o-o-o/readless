"""add content processing metadata

Revision ID: 009
Revises: 008
Create Date: 2026-03-12

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "009"
down_revision: str | Sequence[str] | None = "008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "contents",
        sa.Column("processing_started_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "contents",
        sa.Column("processing_finished_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "contents",
        sa.Column("processing_error", sa.Text(), nullable=True),
    )
    op.add_column(
        "contents",
        sa.Column(
            "processing_attempts",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("contents", "processing_attempts")
    op.drop_column("contents", "processing_error")
    op.drop_column("contents", "processing_finished_at")
    op.drop_column("contents", "processing_started_at")
