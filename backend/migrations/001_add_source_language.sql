-- Migration: Add source_language field to contents table
-- Date: 2026-03-01
-- Description: Adds language detection support for content

-- Add source_language column
ALTER TABLE contents ADD COLUMN IF NOT EXISTS source_language VARCHAR(10);

-- Add comment
COMMENT ON COLUMN contents.source_language IS 'ISO 639-1 language code (e.g., en, zh, ja)';

-- No index needed for now as this field will primarily be used for filtering, not searching
