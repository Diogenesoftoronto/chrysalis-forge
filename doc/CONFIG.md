# Configuration Reference

Chrysalis Forge configuration can be specified via TOML files or environment variables. Environment variables always take precedence over file values.

---

## Configuration Sources

Configuration is loaded in this order (later sources override earlier):

1. **Default values** — Sensible defaults built into the code
2. **`~/.chrysalis/config.toml`** — User-level configuration
3. **`chrysalis.toml`** — Project-level configuration (current directory)
4. **Custom path** — Via `--config` CLI flag or `init-config!` function
5. **Environment variables** — Always highest priority

---

## TOML Syntax

Chrysalis Forge supports a subset of TOML:

### Sections

```toml
[server]
port = 8080

[database]
url = "~/.chrysalis/chrysalis.db"
```

### Environment Variable References

Reference environment variables with `${VAR_NAME}`:

```toml
[auth]
secret_key = "${CHRYSALIS_SECRET_KEY}"
```

### Value Types

```toml
# Strings (quoted)
host = "127.0.0.1"

# Numbers
port = 8080
pool_size = 5

# Booleans
enable_registration = true
require_email_verify = false

# Arrays
allowed = ["gpt-5.2", "gpt-4o", "claude-3-opus"]

# Inline tables
free = { requests_per_minute = 10, requests_per_day = 100 }
```

---

## Configuration Sections

### [server]

Server binding configuration.

| Key | Environment Variable | Default | Description |
|-----|---------------------|---------|-------------|
| `port` | `CHRYSALIS_PORT` | `8080` | HTTP server port |
| `host` | `CHRYSALIS_HOST` | `"127.0.0.1"` | Bind address. Use `"0.0.0.0"` for all interfaces |

```toml
[server]
port = 8080
host = "0.0.0.0"
```

### [database]

Database connection settings.

| Key | Environment Variable | Default | Description |
|-----|---------------------|---------|-------------|
| `url` | `CHRYSALIS_DATABASE_URL` | `~/.chrysalis/chrysalis.db` | SQLite path or PostgreSQL URL |
| `pool_size` | `CHRYSALIS_DB_POOL_SIZE` | `5` | Connection pool size |

```toml
[database]
# SQLite (single server)
url = "~/.chrysalis/chrysalis.db"

# PostgreSQL (production)
# url = "postgresql://user:pass@localhost:5432/chrysalis"

pool_size = 5
```

### [auth]

Authentication and session settings.

| Key | Environment Variable | Default | Description |
|-----|---------------------|---------|-------------|
| `secret_key` | `CHRYSALIS_SECRET_KEY` | *(insecure default)* | JWT signing secret. **Generate with `openssl rand -hex 32`** |
| `session_lifetime` | `CHRYSALIS_SESSION_LIFETIME` | `86400` | Token lifetime in seconds (24 hours) |
| `enable_registration` | `CHRYSALIS_ENABLE_REGISTRATION` | `true` | Allow new user signups |
| `require_email_verify` | `CHRYSALIS_REQUIRE_EMAIL_VERIFY` | `false` | Require email verification before login |

```toml
[auth]
secret_key = "${CHRYSALIS_SECRET_KEY}"
session_lifetime = 86400
enable_registration = true
require_email_verify = false
```

> ⚠️ **Security Warning**: Always set a strong `secret_key` in production. The default is insecure and only suitable for development.

### [billing]

Autumn billing integration.

| Key | Environment Variable | Default | Description |
|-----|---------------------|---------|-------------|
| `autumn_secret_key` | `AUTUMN_SECRET_KEY` | *(none)* | Autumn API key from [useautumn.com](https://useautumn.com) |
| `stripe_webhook_secret` | `STRIPE_WEBHOOK_SECRET` | *(none)* | Stripe webhook signing secret |
| `free_tier_daily_limit` | `CHRYSALIS_FREE_DAILY_LIMIT` | `100` | Daily message limit for free tier |

```toml
[billing]
autumn_secret_key = "${AUTUMN_SECRET_KEY}"
stripe_webhook_secret = "${STRIPE_WEBHOOK_SECRET}"
free_tier_daily_limit = 100
```

If `autumn_secret_key` is not set, billing features are disabled and all users have unlimited access.

### [models]

LLM model configuration.

| Key | Environment Variable | Default | Description |
|-----|---------------------|---------|-------------|
| `default` | `CHRYSALIS_DEFAULT_MODEL` | `"gpt-5.2"` | Default model for new sessions |
| `allowed` | `CHRYSALIS_ALLOWED_MODELS` | *(list)* | Comma-separated list of allowed model IDs |

```toml
[models]
default = "gpt-5.2"
allowed = ["gpt-5.2", "gpt-4o", "gpt-4o-mini", "claude-3-opus", "claude-3-sonnet", "gemini-pro"]
```

For environment variable:
```bash
export CHRYSALIS_ALLOWED_MODELS="gpt-5.2,gpt-4o,claude-3-opus"
```

### [rate_limits]

Per-tier rate limiting. Use inline tables for each tier.

| Tier | Default RPM | Default RPD | Description |
|------|-------------|-------------|-------------|
| `free` | 10 | 100 | Free tier |
| `pro` | 60 | 1000 | Pro subscribers |
| `team` | 120 | -1 (unlimited) | Team plan |
| `enterprise` | 300 | -1 (unlimited) | Enterprise |

```toml
[rate_limits]
free = { requests_per_minute = 10, requests_per_day = 100 }
pro = { requests_per_minute = 60, requests_per_day = 1000 }
team = { requests_per_minute = 120, requests_per_day = -1 }
enterprise = { requests_per_minute = 300, requests_per_day = -1 }
```

### [security]

Security and CORS settings.

| Key | Environment Variable | Default | Description |
|-----|---------------------|---------|-------------|
| `allowed_origins` | `CHRYSALIS_ALLOWED_ORIGINS` | `["*"]` | CORS allowed origins |
| `trusted_proxies` | `CHRYSALIS_TRUSTED_PROXIES` | `["127.0.0.1"]` | Trusted proxy IPs for X-Forwarded-For |

```toml
[security]
allowed_origins = ["http://localhost:3000", "https://app.example.com"]
trusted_proxies = ["127.0.0.1", "10.0.0.0/8"]
```

### [logging]

Logging configuration (not yet fully implemented in config loader).

```toml
[logging]
level = "info"  # debug, info, warn, error
# file = "/var/log/chrysalis/service.log"
```

---

## Environment Variables Reference

Quick reference for all environment variables:

| Variable | Description |
|----------|-------------|
| `CHRYSALIS_PORT` | Server port |
| `CHRYSALIS_HOST` | Server bind address |
| `CHRYSALIS_DATABASE_URL` | Database connection URL |
| `CHRYSALIS_DB_POOL_SIZE` | Database pool size |
| `CHRYSALIS_SECRET_KEY` | JWT signing secret |
| `CHRYSALIS_SESSION_LIFETIME` | Token lifetime (seconds) |
| `CHRYSALIS_ENABLE_REGISTRATION` | Allow signups (true/false) |
| `CHRYSALIS_REQUIRE_EMAIL_VERIFY` | Require email verification |
| `CHRYSALIS_DEFAULT_MODEL` | Default LLM model |
| `CHRYSALIS_ALLOWED_MODELS` | Comma-separated model list |
| `CHRYSALIS_FREE_DAILY_LIMIT` | Free tier daily limit |
| `CHRYSALIS_ALLOWED_ORIGINS` | CORS origins (comma-separated) |
| `CHRYSALIS_TRUSTED_PROXIES` | Trusted proxies (comma-separated) |
| `AUTUMN_SECRET_KEY` | Autumn billing API key |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook secret |
| `OPENAI_API_KEY` | OpenAI API key (for service) |
| `ANTHROPIC_API_KEY` | Anthropic API key |
| `GOOGLE_API_KEY` | Google AI API key |
| `MISTRAL_API_KEY` | Mistral API key |
| `COHERE_API_KEY` | Cohere API key |
| `EXA_API_KEY` | Exa search API key |

---

## Example Configurations

### Minimal Development

```toml
# chrysalis.toml - Development
[server]
port = 8080

[auth]
secret_key = "dev-only-not-for-production"
```

### Production Single-Server

```toml
# chrysalis.toml - Production
[server]
port = 8080
host = "0.0.0.0"

[database]
url = "/var/lib/chrysalis/data.db"

[auth]
secret_key = "${CHRYSALIS_SECRET_KEY}"
session_lifetime = 86400
enable_registration = true

[billing]
autumn_secret_key = "${AUTUMN_SECRET_KEY}"
stripe_webhook_secret = "${STRIPE_WEBHOOK_SECRET}"

[security]
allowed_origins = ["https://app.chrysalis.example.com"]
trusted_proxies = ["127.0.0.1"]
```

### Self-Hosted (No Billing)

```toml
# chrysalis.toml - Self-hosted
[server]
port = 8080
host = "0.0.0.0"

[auth]
secret_key = "${CHRYSALIS_SECRET_KEY}"
enable_registration = false  # Invite-only

[models]
default = "gpt-4o"
allowed = ["gpt-4o", "gpt-4o-mini"]

# No [billing] section = unlimited access for all users
```

### Docker Environment

```bash
# docker-compose.yml environment
environment:
  - CHRYSALIS_PORT=8080
  - CHRYSALIS_HOST=0.0.0.0
  - CHRYSALIS_DATABASE_URL=/data/chrysalis.db
  - CHRYSALIS_SECRET_KEY=${SECRET_KEY}
  - AUTUMN_SECRET_KEY=${AUTUMN_KEY}
  - OPENAI_API_KEY=${OPENAI_KEY}
```

---

## Programmatic Access

```racket
(require "src/service/config.rkt")

;; Initialize configuration
(init-config! "path/to/chrysalis.toml")

;; Access configuration values
(config-port)           ; → 8080
(config-host)           ; → "127.0.0.1"
(config-database-url)   ; → "~/.chrysalis/chrysalis.db"
(config-secret-key)     ; → "..." or insecure default
(config-default-model)  ; → "gpt-5.2"
(config-allowed-models) ; → '("gpt-5.2" "gpt-4o" ...)
(config-autumn-key)     ; → "..." or #f
(config-free-daily-limit) ; → 100

;; Get rate limit for a tier
(config-rate-limit 'pro)
; → (RateLimitTier 60 1000)
```
