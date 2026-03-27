"""add trigram index for chinese search

Revision ID: 012
Revises: 011
Create Date: 2026-03-22

"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "012"
down_revision: str | Sequence[str] | None = "011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Enable pg_trgm and add trigram GIN indexes for CJK substring search."""
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    op.execute(
        "CREATE INDEX IF NOT EXISTS "
        "ix_contents_title_trgm ON contents USING gin (title gin_trgm_ops)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS "
        "ix_contents_l0_summary_trgm ON contents USING gin "
        "(l0_summary gin_trgm_ops)"
    )


def downgrade() -> None:
    """Remove trigram indexes."""
    op.execute("DROP INDEX IF EXISTS ix_contents_l0_summary_trgm")
    op.execute("DROP INDEX IF EXISTS ix_contents_title_trgm")
