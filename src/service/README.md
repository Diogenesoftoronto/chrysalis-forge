# Chrysalis Forge Service Layer

Multi-user HTTP/WebSocket service for Chrysalis Forge with organizations, BYOK support, and payment integration.

## Quick Start

```bash
# Start the HTTP service
racket main.rkt --serve

# With custom port and host
racket main.rkt --serve --serve-port 3000 --serve-host 0.0.0.0

# As a daemon (background process)
racket main.rkt --serve --daemonize
```

## Configuration

### Environment Variables

Set these in your `.env` file or environment:

| Variable | Description | Default |
|----------|-------------|---------|
| `CHRYSALIS_SECRET_KEY` | JWT signing key (required for production) | `dev-insecure-key` |
| `CHRYSALIS_PORT` | HTTP server port | `8080` |
| `CHRYSALIS_HOST` | Bind address | `127.0.0.1` |
| `CHRYSALIS_DATABASE_URL` | SQLite or PostgreSQL URL | `~/.chrysalis/chrysalis.db` |
| `AUTUMN_SECRET_KEY` | Autumn billing API key | (optional) |

### Configuration File

Create `chrysalis.toml` (see `chrysalis.example.toml`):

```toml
[server]
port = 8080
host = "127.0.0.1"

[database]
url = "~/.chrysalis/chrysalis.db"

[auth]
secret_key = "${CHRYSALIS_SECRET_KEY}"
enable_registration = true

[models]
default = "gpt-5.2"
allowed = ["gpt-5.2", "gpt-4o", "claude-3-opus"]
```

## API Endpoints

### Authentication

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/auth/register` | Register new user |
| `POST` | `/auth/login` | Login (returns JWT) |
| `GET` | `/users/me` | Get current user |

### Organizations

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/orgs` | List user's organizations |
| `POST` | `/orgs` | Create organization |
| `GET` | `/orgs/{id}` | Get organization |
| `GET` | `/orgs/{id}/members` | List members |
| `POST` | `/orgs/{id}/invite` | Invite member |

### BYOK (Bring Your Own Key)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/provider-keys` | List provider keys |
| `POST` | `/provider-keys` | Add provider key |
| `DELETE` | `/provider-keys/{provider}` | Remove key |

### Sessions (Internal)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/sessions` | List sessions |
| `POST` | `/v1/sessions` | Create session |
| `GET` | `/v1/sessions/{id}` | Get session + messages |

### Threads (User-Facing)

Threads provide conversation continuity across sessions. Sessions are hidden implementation details that get rotated automatically.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/threads` | List threads |
| `POST` | `/v1/threads` | Create thread |
| `GET` | `/v1/threads/{id}` | Get thread + relations + contexts |
| `PATCH` | `/v1/threads/{id}` | Update thread title/status |
| `POST` | `/v1/threads/{id}/messages` | Chat on a thread |
| `POST` | `/v1/threads/{id}/relations` | Link threads |
| `GET` | `/v1/threads/{id}/contexts` | Get context hierarchy |
| `POST` | `/v1/threads/{id}/contexts` | Add context node |

#### Thread Relations

- `continues_from` - This thread continues from another
- `child_of` - Hierarchical child thread
- `relates_to` - Loose association

### Projects

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/projects` | List projects |
| `POST` | `/v1/projects` | Create project |
| `GET` | `/v1/projects/{id}` | Get project + threads |

### OpenAI-Compatible

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/chat/completions` | Chat completions |
| `GET` | `/v1/models` | List available models |

## Authentication

### Bearer Token

```bash
curl -H "Authorization: Bearer <jwt_token>" http://localhost:8080/users/me
```

### API Key

```bash
curl -H "X-API-Key: chs_xxxxxxxx" http://localhost:8080/v1/chat/completions
```

## Module Structure

```
src/service/
├── schema.sql         # Database schema
├── config.rkt         # Configuration loading
├── db.rkt             # Database operations
├── auth.rkt           # Authentication (JWT, API keys)
├── key-vault.rkt      # BYOK encryption
├── api-router.rkt     # REST API routes
├── service-server.rkt # HTTP server
├── rate-limiter.rkt   # Rate limiting
└── billing.rkt        # Autumn integration
```

## Database

The service uses SQLite by default (good for single-server deployments). For production with multiple servers, switch to PostgreSQL:

```bash
export CHRYSALIS_DATABASE_URL="postgresql://user:pass@localhost/chrysalis"
```

## Billing Integration

We use [Autumn](https://useautumn.com) for usage-based billing:

1. Create an Autumn account and configure plans
2. Set `AUTUMN_SECRET_KEY` in your environment
3. Configure webhook endpoint: `https://your-domain.com/billing/webhook`

Plans:
- **Free**: 100 messages/day, basic models
- **Pro** ($20/mo): 1000 messages/day, all models
- **Team** ($15/user/mo): Unlimited, organizations, shared threads
- **Enterprise**: Custom, self-host, SSO
