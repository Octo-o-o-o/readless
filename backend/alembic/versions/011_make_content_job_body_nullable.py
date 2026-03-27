"""make content_job body nullable

Revision ID: 011
Revises: 010
Create Date: 2026-03-22

"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "011"
down_revision: str | Sequence[str] | None = "010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Allow body column to be NULL so completed jobs can release payload."""
    op.alter_column("content_jobs", "body", nullable=True)


def downgrade() -> None:
    """Restore NOT NULL constraint on body column."""
    op.execute("UPDATE content_jobs SET body = '' WHERE body IS NULL")
    op.alter_column("content_jobs", "body", nullable=False)
