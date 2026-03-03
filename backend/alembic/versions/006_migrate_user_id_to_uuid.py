"""migrate user_id to uuid and add foreign keys

Revision ID: 006
Revises: 005
Create Date: 2026-03-02

"""
from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '006'
down_revision: str | Sequence[str] | None = '005'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    # 1. Truncate tables (no production data yet - confirmed safe by user)
    op.execute("TRUNCATE TABLE content_tags, user_tags, paragraphs, podcasts, channels, contents CASCADE")

    # 2. Alter user_id columns to UUID
    op.alter_column('contents', 'user_id',
                   existing_type=sa.String(),
                   type_=postgresql.UUID(as_uuid=True),
                   postgresql_using='user_id::uuid',
                   nullable=False)

    op.alter_column('user_tags', 'user_id',
                   existing_type=sa.String(),
                   type_=postgresql.UUID(as_uuid=True),
                   postgresql_using='user_id::uuid',
                   nullable=False)

    op.alter_column('content_tags', 'user_id',
                   existing_type=sa.String(),
                   type_=postgresql.UUID(as_uuid=True),
                   postgresql_using='user_id::uuid',
                   nullable=False)

    # 3. Add foreign key constraints
    op.create_foreign_key(
        'fk_contents_user', 'contents', 'users',
        ['user_id'], ['id'],
        ondelete='CASCADE'
    )

    op.create_foreign_key(
        'fk_user_tags_user', 'user_tags', 'users',
        ['user_id'], ['id'],
        ondelete='CASCADE'
    )

    op.create_foreign_key(
        'fk_content_tags_user', 'content_tags', 'users',
        ['user_id'], ['id'],
        ondelete='CASCADE'
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint('fk_content_tags_user', 'content_tags', type_='foreignkey')
    op.drop_constraint('fk_user_tags_user', 'user_tags', type_='foreignkey')
    op.drop_constraint('fk_contents_user', 'contents', type_='foreignkey')

    op.alter_column('content_tags', 'user_id',
                   existing_type=postgresql.UUID(as_uuid=True),
                   type_=sa.String(),
                   nullable=False)

    op.alter_column('user_tags', 'user_id',
                   existing_type=postgresql.UUID(as_uuid=True),
                   type_=sa.String(),
                   nullable=False)

    op.alter_column('contents', 'user_id',
                   existing_type=postgresql.UUID(as_uuid=True),
                   type_=sa.String(),
                   nullable=False)
