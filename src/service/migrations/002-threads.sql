-- Migration 002: Add thread_id column to sessions table
-- Run this after initial schema if upgrading existing database

-- Add thread_id to sessions
ALTER TABLE sessions ADD COLUMN thread_id TEXT REFERENCES threads(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_sessions_thread ON sessions(thread_id, updated_at DESC);

-- Mark migration complete
INSERT OR IGNORE INTO schema_migrations (version) VALUES (2);
