"""add_tag_system

Revision ID: 73a2408925ed
Revises:
Create Date: 2026-03-01 22:58:14.823878

"""
from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '73a2408925ed'
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    # 1. Create user_tags table
    op.create_table(
        'user_tags',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.String(100), nullable=False),
        sa.Column('tag_name', sa.String(50), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )

    # Indexes for user_tags
    op.create_index('idx_user_tags_user_id', 'user_tags', ['user_id'], postgresql_where=sa.text('deleted_at IS NULL'))
    op.create_index('idx_user_tags_deleted_at', 'user_tags', ['deleted_at'])

    # Partial unique index - enforces uniqueness only for non-deleted tags
    op.create_index(
        'uq_user_tags_user_tag',
        'user_tags',
        ['user_id', 'tag_name'],
        unique=True,
        postgresql_where=sa.text('deleted_at IS NULL')
    )

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

    # 3. Migrate existing tags from contents.tags to new tables
    # This uses PostgreSQL's unnest() to expand array values
    op.execute("""
        -- First, create user_tags from all unique tags across all users
        INSERT INTO user_tags (user_id, tag_name)
        SELECT DISTINCT user_id, unnest(tags) as tag_name
        FROM contents
        WHERE tags IS NOT NULL AND array_length(tags, 1) > 0
        ON CONFLICT DO NOTHING;

        -- Then, create content_tags linking contents to their tags
        INSERT INTO content_tags (content_id, tag_id, user_id)
        SELECT c.id, ut.id, c.user_id
        FROM contents c
        CROSS JOIN LATERAL unnest(c.tags) as tag_name
        JOIN user_tags ut ON ut.user_id = c.user_id AND ut.tag_name = tag_name
        WHERE c.tags IS NOT NULL AND array_length(c.tags, 1) > 0;
    """)

    # 4. Drop old tags column and index from contents table
    op.drop_index('ix_contents_tags', table_name='contents', postgresql_using='gin')
    op.drop_column('contents', 'tags')


def downgrade() -> None:
    """Downgrade schema."""
    # 1. Restore tags column to contents table
    op.add_column('contents', sa.Column('tags', postgresql.ARRAY(sa.String()), nullable=True))
    op.create_index('ix_contents_tags', 'contents', ['tags'], postgresql_using='gin')

    # 2. Migrate data back from relational tables to array
    op.execute("""
        UPDATE contents c
        SET tags = ARRAY(
            SELECT ut.tag_name
            FROM content_tags ct
            JOIN user_tags ut ON ct.tag_id = ut.id
            WHERE ct.content_id = c.id
            ORDER BY ut.tag_name
        );
    """)

    # 3. Drop new tables
    op.drop_table('content_tags')
    op.drop_table('user_tags')
