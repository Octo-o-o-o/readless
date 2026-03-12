"""add subscription auto renew status

Revision ID: 008
Revises: 007
Create Date: 2026-03-11

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "008"
down_revision: str | Sequence[str] | None = "007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        "users",
        sa.Column("subscription_auto_renew_enabled", sa.Boolean(), nullable=True),
    )
    op.create_index(
        "idx_users_apple_original_transaction_id",
        "users",
        ["apple_original_transaction_id"],
        unique=False,
        postgresql_where=sa.text("apple_original_transaction_id IS NOT NULL"),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("idx_users_apple_original_transaction_id", table_name="users")
    op.drop_column("users", "subscription_auto_renew_enabled")
