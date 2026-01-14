-- Chrysalis Forge Multi-User Service Schema
-- SQLite-compatible with PostgreSQL notes

-- ============================================================================
-- USERS & AUTHENTICATION
-- ============================================================================

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    email_verified BOOLEAN DEFAULT FALSE,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted'))
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);

-- API Keys (service-generated for programmatic access)
CREATE TABLE IF NOT EXISTS api_keys (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    org_id TEXT REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    key_hash TEXT NOT NULL,
    prefix TEXT NOT NULL,  -- First 8 chars for identification (e.g., "chs_xxxx")
    scopes TEXT DEFAULT '*',  -- Comma-separated scopes or '*' for all
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_used TIMESTAMP,
    expires_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_api_keys_user ON api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_prefix ON api_keys(prefix);

-- ============================================================================
-- ORGANIZATIONS
-- ============================================================================

-- Organizations
CREATE TABLE IF NOT EXISTS organizations (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    owner_id TEXT NOT NULL REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    settings TEXT DEFAULT '{}'  -- JSON: default_model, usage_limits, allowed_tools, etc.
);

CREATE INDEX IF NOT EXISTS idx_orgs_slug ON organizations(slug);
CREATE INDEX IF NOT EXISTS idx_orgs_owner ON organizations(owner_id);

-- Organization Members
CREATE TABLE IF NOT EXISTS org_members (
    org_id TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member', 'reader')),
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    invited_by TEXT REFERENCES users(id),
    PRIMARY KEY (org_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_org_members_user ON org_members(user_id);

-- Organization Invites
CREATE TABLE IF NOT EXISTS org_invites (
    id TEXT PRIMARY KEY,
    org_id TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'member',
    invited_by TEXT NOT NULL REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    accepted_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_org_invites_email ON org_invites(email);

-- ============================================================================
-- BYOK (Bring Your Own Key)
-- ============================================================================

-- LLM Provider Keys
CREATE TABLE IF NOT EXISTS provider_keys (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    org_id TEXT REFERENCES organizations(id) ON DELETE CASCADE,  -- NULL = personal key
    provider TEXT NOT NULL,  -- openai, anthropic, google, mistral, ollama, custom
    key_encrypted BLOB NOT NULL,
    key_hint TEXT,  -- Last 4 chars for identification
    base_url TEXT,  -- Custom endpoint URL (for ollama, vllm, etc.)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    validated_at TIMESTAMP,
    is_valid BOOLEAN DEFAULT TRUE,
    UNIQUE(user_id, org_id, provider)  -- One key per provider per user/org combo
);

CREATE INDEX IF NOT EXISTS idx_provider_keys_user ON provider_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_provider_keys_org ON provider_keys(org_id);

-- ============================================================================
-- SESSIONS & CONVERSATIONS
-- ============================================================================

-- Sessions (agent conversations)
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    org_id TEXT REFERENCES organizations(id) ON DELETE SET NULL,
    mode TEXT DEFAULT 'code' CHECK (mode IN ('ask', 'architect', 'code', 'semantic')),
    title TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    context TEXT DEFAULT '{}',  -- JSON: system prompt, memory, tool hints
    is_archived BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_org ON sessions(org_id);
CREATE INDEX IF NOT EXISTS idx_sessions_updated ON sessions(updated_at DESC);

-- Session Messages (conversation history)
CREATE TABLE IF NOT EXISTS session_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('system', 'user', 'assistant', 'tool')),
    content TEXT NOT NULL,
    tool_calls TEXT,  -- JSON: array of tool calls if role=assistant
    tool_call_id TEXT,  -- Reference if role=tool
    model TEXT,
    tokens_in INTEGER,
    tokens_out INTEGER,
    cost_usd REAL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_messages_session ON session_messages(session_id);

-- ============================================================================
-- SOCIAL FEATURES
-- ============================================================================

-- Shared Threads (make sessions visible to org)
CREATE TABLE IF NOT EXISTS shared_threads (
    id TEXT PRIMARY KEY,
    session_id TEXT UNIQUE NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    org_id TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    shared_by TEXT NOT NULL REFERENCES users(id),
    visibility TEXT DEFAULT 'org' CHECK (visibility IN ('org', 'public')),
    title TEXT,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_shared_threads_org ON shared_threads(org_id);

-- Thread Comments
CREATE TABLE IF NOT EXISTS thread_comments (
    id TEXT PRIMARY KEY,
    thread_id TEXT NOT NULL REFERENCES shared_threads(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_thread_comments_thread ON thread_comments(thread_id);

-- Shared Prompts Library
CREATE TABLE IF NOT EXISTS shared_prompts (
    id TEXT PRIMARY KEY,
    org_id TEXT REFERENCES organizations(id) ON DELETE CASCADE,  -- NULL = public
    user_id TEXT NOT NULL REFERENCES users(id),
    title TEXT NOT NULL,
    description TEXT,
    content TEXT NOT NULL,
    tags TEXT DEFAULT '[]',  -- JSON array
    use_count INTEGER DEFAULT 0,
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_prompts_org ON shared_prompts(org_id);
CREATE INDEX IF NOT EXISTS idx_prompts_public ON shared_prompts(is_public);

-- Activity Feed
CREATE TABLE IF NOT EXISTS activity_feed (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    org_id TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id),
    action_type TEXT NOT NULL,  -- session_created, thread_shared, member_joined, prompt_created, etc.
    target_type TEXT,  -- session, thread, prompt, member
    target_id TEXT,
    metadata TEXT DEFAULT '{}',  -- JSON with additional context
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_activity_org ON activity_feed(org_id, created_at DESC);

-- ============================================================================
-- BILLING & USAGE
-- ============================================================================

-- Subscription Plans (cached from Autumn)
CREATE TABLE IF NOT EXISTS subscriptions (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
    org_id TEXT REFERENCES organizations(id) ON DELETE CASCADE,
    plan_id TEXT NOT NULL,  -- free, pro, team, enterprise
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'canceled', 'past_due', 'trialing')),
    autumn_customer_id TEXT,
    current_period_start TIMESTAMP,
    current_period_end TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_org ON subscriptions(org_id);

-- Usage Logs (for billing and analytics)
CREATE TABLE IF NOT EXISTS usage_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL REFERENCES users(id),
    org_id TEXT REFERENCES organizations(id),
    session_id TEXT REFERENCES sessions(id),
    model TEXT NOT NULL,
    provider TEXT NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0.0,
    provider_key_id TEXT REFERENCES provider_keys(id),  -- NULL = service key used
    is_byok BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_usage_user ON usage_logs(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_usage_org ON usage_logs(org_id, created_at);
CREATE INDEX IF NOT EXISTS idx_usage_date ON usage_logs(created_at);

-- Daily Usage Aggregates (for faster quota checks)
CREATE TABLE IF NOT EXISTS usage_daily (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    org_id TEXT REFERENCES organizations(id) ON DELETE CASCADE,
    date TEXT NOT NULL,  -- YYYY-MM-DD
    messages INTEGER DEFAULT 0,
    tokens INTEGER DEFAULT 0,
    cost_usd REAL DEFAULT 0.0,
    PRIMARY KEY (user_id, COALESCE(org_id, ''), date)
);

CREATE INDEX IF NOT EXISTS idx_usage_daily_date ON usage_daily(date);

-- ============================================================================
-- WORKFLOWS (extending existing workflow system)
-- ============================================================================

-- Shared Workflows
CREATE TABLE IF NOT EXISTS workflows (
    id TEXT PRIMARY KEY,
    slug TEXT NOT NULL,
    user_id TEXT NOT NULL REFERENCES users(id),
    org_id TEXT REFERENCES organizations(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    content TEXT NOT NULL,
    version INTEGER DEFAULT 1,
    is_public BOOLEAN DEFAULT FALSE,
    use_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    UNIQUE(org_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_workflows_org ON workflows(org_id);
CREATE INDEX IF NOT EXISTS idx_workflows_slug ON workflows(slug);

-- ============================================================================
-- SYSTEM
-- ============================================================================

-- Audit Log (for compliance and debugging)
CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT REFERENCES users(id),
    action TEXT NOT NULL,
    resource_type TEXT,
    resource_id TEXT,
    ip_address TEXT,
    user_agent TEXT,
    details TEXT DEFAULT '{}',  -- JSON
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_log(action, created_at DESC);

-- Schema Migrations
CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert initial migration marker
INSERT OR IGNORE INTO schema_migrations (version) VALUES (1);

-- ============================================================================
-- THREADS & PROJECTS (v2 - Hierarchical Context)
-- ============================================================================

-- Projects (workspace containers)
CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    org_id TEXT REFERENCES organizations(id) ON DELETE CASCADE,
    owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    slug TEXT,
    name TEXT NOT NULL,
    description TEXT,
    settings TEXT DEFAULT '{}',  -- JSON: default_model, repo, root_dir, rules
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_archived BOOLEAN DEFAULT FALSE,
    UNIQUE(org_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_projects_org ON projects(org_id);
CREATE INDEX IF NOT EXISTS idx_projects_owner ON projects(owner_id);

-- Threads (user-facing conversation continuity)
CREATE TABLE IF NOT EXISTS threads (
    id TEXT PRIMARY KEY,  -- T-uuid format
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    org_id TEXT REFERENCES organizations(id) ON DELETE SET NULL,
    project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
    title TEXT,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'paused', 'done', 'archived')),
    summary TEXT,  -- Running summary for context continuity
    metadata TEXT DEFAULT '{}',  -- JSON: tags, labels, etc.
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_threads_user ON threads(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_threads_project ON threads(project_id, updated_at DESC);

-- Thread Relations (continues_from, child_of, relates_to)
CREATE TABLE IF NOT EXISTS thread_relations (
    id TEXT PRIMARY KEY,
    from_thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    to_thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    relation_type TEXT NOT NULL CHECK (relation_type IN ('continues_from', 'child_of', 'relates_to')),
    created_by TEXT NOT NULL REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_thread_rel_from ON thread_relations(from_thread_id);
CREATE INDEX IF NOT EXISTS idx_thread_rel_to ON thread_relations(to_thread_id);

-- Thread Context Nodes (hierarchical breakdown within a thread)
CREATE TABLE IF NOT EXISTS thread_contexts (
    id TEXT PRIMARY KEY,
    thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    parent_id TEXT REFERENCES thread_contexts(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    kind TEXT DEFAULT 'note' CHECK (kind IN ('note', 'task', 'area', 'file_group', 'plan')),
    body TEXT,  -- Markdown description/instructions
    metadata TEXT DEFAULT '{}',  -- JSON: paths, tags, status
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_thread_contexts_thread ON thread_contexts(thread_id);
CREATE INDEX IF NOT EXISTS idx_thread_contexts_parent ON thread_contexts(parent_id);

-- Link sessions to threads (sessions become hidden implementation detail)
-- Note: This is an ALTER for existing sessions table
-- Run separately if table exists: ALTER TABLE sessions ADD COLUMN thread_id TEXT REFERENCES threads(id) ON DELETE SET NULL;

INSERT OR IGNORE INTO schema_migrations (version) VALUES (2);
