"""add users table

Revision ID: da76ab28fd64
Revises: 73a2408925ed
Create Date: 2026-03-02 17:28:24.091158

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'da76ab28fd64'
down_revision: Union[str, Sequence[str], None] = '73a2408925ed'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'users',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('email', sa.String(255), unique=True, nullable=True),
        sa.Column('password_hash', sa.String(255), nullable=True),
        sa.Column('apple_id', sa.String(255), unique=True, nullable=True),

        sa.Column('subscription_tier', sa.String(20), nullable=False, server_default='trial'),
        sa.Column('trial_expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('subscription_expires_at', sa.DateTime(timezone=True), nullable=True),

        sa.Column('apple_original_transaction_id', sa.String(255), nullable=True),
        sa.Column('apple_receipt_data', sa.Text, nullable=True),

        sa.Column('email_verified', sa.Boolean, server_default='false'),
        sa.Column('email_verification_token', sa.String(64), nullable=True),

        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        sa.Column('last_login_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),

        sa.CheckConstraint('email IS NOT NULL OR apple_id IS NOT NULL', name='user_identity_check')
    )

    op.create_index('idx_users_email', 'users', ['email'])
    op.create_index('idx_users_apple_id', 'users', ['apple_id'])
    op.create_index('idx_users_email_active', 'users', ['email'], postgresql_where=sa.text('deleted_at IS NULL'), unique=True)
    op.create_index('idx_users_apple_id_active', 'users', ['apple_id'], postgresql_where=sa.text('deleted_at IS NULL'), unique=True)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('users')
