-- Tag System Migration (73a2408925ed)
-- This migration creates user_tags and content_tags tables

BEGIN;

-- 1. Create user_tags table
CREATE TABLE user_tags (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(100) NOT NULL,
    tag_name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Indexes for user_tags
CREATE INDEX idx_user_tags_user_id ON user_tags (user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_user_tags_deleted_at ON user_tags (deleted_at);

-- Partial unique index - enforces uniqueness only for non-deleted tags
CREATE UNIQUE INDEX uq_user_tags_user_tag ON user_tags (user_id, tag_name) WHERE deleted_at IS NULL;

-- 2. Create content_tags table
CREATE TABLE content_tags (
    content_id VARCHAR(36) NOT NULL,
    tag_id INTEGER NOT NULL,
    user_id VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    PRIMARY KEY (content_id, tag_id),
    FOREIGN KEY (content_id) REFERENCES contents(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES user_tags(id) ON DELETE CASCADE
);

CREATE INDEX idx_content_tags_tag_id ON content_tags (tag_id);
CREATE INDEX idx_content_tags_content_id ON content_tags (content_id);
CREATE INDEX idx_content_tags_user_id ON content_tags (user_id);

-- 3. Migrate existing tags from contents.tags to new tables
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
CROSS JOIN LATERAL unnest(c.tags) WITH ORDINALITY AS t(tag_name, ord)
JOIN user_tags ut ON ut.user_id = c.user_id AND ut.tag_name = t.tag_name
WHERE c.tags IS NOT NULL AND array_length(c.tags, 1) > 0;

-- 4. Drop old tags column and index from contents table
DROP INDEX IF EXISTS ix_contents_tags;
ALTER TABLE contents DROP COLUMN IF EXISTS tags;

-- 5. Create alembic_version table if not exists
CREATE TABLE IF NOT EXISTS alembic_version (
    version_num VARCHAR(32) NOT NULL,
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);

-- 6. Record this migration
INSERT INTO alembic_version (version_num) VALUES ('73a2408925ed')
ON CONFLICT (version_num) DO NOTHING;

COMMIT;
