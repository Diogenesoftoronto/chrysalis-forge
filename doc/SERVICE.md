# Chrysalis Forge Service Layer

The service layer provides a hosted API backend with authentication, billing, rate limiting, and OpenAI-compatible endpoints. This enables Chrysalis Forge to run as a multi-user SaaS platform.

---

## Authentication System

The authentication system (`src/service/auth.rkt`) supports multiple authentication methods.

### Password Hashing

Passwords are hashed using PBKDF2-SHA256:

```racket
(define SALT-LENGTH 16)
(define ITERATIONS 100000)
(define KEY-LENGTH 32)

(hash-password "user-password")    ; → "salt$hash" format
(verify-password "password" stored) ; → #t or #f
```

### JWT Tokens

JWT tokens use HS256 signing and include standard claims:

```racket
(create-jwt (hash 'sub user-id 'email email)
            #:secret (config-secret-key)
            #:expires-in 86400)  ; 24 hours

(verify-jwt token #:secret (config-secret-key))
; → payload hash or #f
```

Token structure:
- `iat`: Issued-at timestamp
- `exp`: Expiration timestamp  
- `sub`: User ID
- Custom claims as needed

### API Keys

API keys provide programmatic access without JWT token management:

```racket
(define-values (full-key prefix hash) (generate-api-key))
; full-key: "chs_abc123..."
; prefix: "chs_abc12345" (first 12 chars for lookup)
; hash: SHA256 of full key for verification

(verify-api-key "chs_abc123...") ; → user-id or #f
```

### User Management

```racket
;; Registration
(register-user! "user@example.com" "password" #:display-name "Alice")

;; Login - returns user-id and JWT token
(define-values (user-id token) (login-user! "user@example.com" "password"))

;; Get user from token
(get-user-from-token token) ; → user hash or #f
```

### Authentication Middleware

```racket
;; Extract bearer token from headers
(extract-bearer-token headers) ; → token string or #f

;; Authenticate request (supports both JWT and API keys)
(authenticate request) ; → user hash or #f

;; Require authentication (raises error if not authenticated)
(require-auth request) ; → user hash
```

### Authorization Helpers

```racket
(user-can-access-org? user-id org-id 'read)   ; → #t/#f
(user-can-access-org? user-id org-id 'write)  ; → #t/#f
(user-can-access-org? user-id org-id 'admin)  ; → #t/#f
(user-can-access-session? user-id session-id) ; → #t/#f
```

---

## Billing Integration

The billing system (`src/service/billing.rkt`) integrates with [Autumn](https://useautumn.com) for usage-based billing.

### Plan Tiers

| Plan | Messages/Day | Price | Features |
|------|-------------|-------|----------|
| **Free** | 100 | $0 | Basic models |
| **Pro** | 1,000 | $20/mo | Advanced models, priority support |
| **Team** | Unlimited | $15/user/mo | Organizations, shared threads, admin controls |
| **Enterprise** | Unlimited | Custom | SSO, audit logs, dedicated support, self-host |

### Feature Access Control

```racket
;; Check if user can access a feature
(define-values (allowed? remaining) 
  (check-feature-access user-id "advanced_models"))

;; Simple boolean check
(can-use-feature? user-id "advanced_models") ; → #t/#f

;; Check plan features
(plan-includes? 'pro 'priority_support) ; → #t
```

### Usage Tracking

```racket
;; Track usage of a metered feature
(track-usage! user-id "messages" #:amount 1)

;; Get usage summary
(get-usage-summary user-id #:period "current")
; → (hash 'messages N 'tokens M ...)
```

### Subscription Management

```racket
;; Get user's current plan
(get-user-plan user-id) ; → 'free, 'pro, 'team, or 'enterprise

;; Get active products
(get-customer-products user-id) ; → list of subscriptions

;; Get checkout URL for upgrading
(get-checkout-url user-id "pro_monthly" 
                  #:success-url "/billing/success"
                  #:cancel-url "/billing")

;; Get billing portal URL for managing subscription
(get-billing-portal-url user-id)
```

### Billing Middleware

```racket
;; Wrap handler with feature access check
(with-billing-check handler "advanced_models")
; Returns 402 Payment Required if quota exceeded
```

---

## Rate Limiting

The rate limiter (`src/service/rate-limiter.rkt`) implements token bucket / sliding window rate limiting.

### Tier Limits

| Tier | Requests/Minute | Requests/Day |
|------|-----------------|--------------|
| Free | 10 | 100 |
| Pro | 60 | 1,000 |
| Team | 120 | Unlimited |
| Enterprise | 300 | Unlimited |

### Checking Rate Limits

```racket
(define-values (allowed? limit remaining reset-seconds)
  (check-rate-limit user-id))

;; Record a request
(record-request! user-id)
```

### Rate Limit Headers

Responses include standard rate limit headers:

```racket
(rate-limit-headers user-id)
; → '((x-ratelimit-limit . "60")
;     (x-ratelimit-remaining . "45")
;     (x-ratelimit-reset . "1234567890"))
```

### Rate Limit Middleware

```racket
(with-rate-limit handler)
; Automatically checks limits and returns 429 Too Many Requests if exceeded
; Includes Retry-After header
```

---

## BYOK Key Vault

The key vault (`src/service/key-vault.rkt`) provides secure storage for user-provided API keys (Bring Your Own Key).

### Supported Providers

- `openai` - OpenAI API
- `anthropic` - Anthropic Claude
- `google` - Google AI / Gemini
- `mistral` - Mistral AI
- `cohere` - Cohere
- `ollama` - Local Ollama server
- `vllm` - vLLM server
- `custom` - Custom OpenAI-compatible endpoint

### Key Management

```racket
;; Add a provider key (encrypted before storage)
(add-user-key! user-id "openai" "sk-abc123..."
               #:base-url "https://api.openai.com/v1")

;; Get decrypted key
(define-values (key base-url) (get-user-key user-id "openai"))

;; Remove a key
(remove-user-key! user-id "openai")

;; List all keys (without decrypting)
(list-user-keys user-id)
; → list of (hash 'provider "openai" 'key_hint "...xyz" ...)
```

### Key Resolution

When making API calls, keys are resolved in order:

1. User's personal key for the provider
2. Organization's shared key (if in org context)
3. Service default key (from environment)

```racket
(define-values (key base-url is-byok?)
  (resolve-provider-key user-id "openai" 
                        #:org-id org-id
                        #:prefer-byok #t))
```

### Key Validation

```racket
(define-values (valid? message)
  (validate-provider-key "openai" "sk-abc123..."))
; Validates key format (actual API test not yet implemented)
```

---

## API Router

The API router (`src/service/api-router.rkt`) provides RESTful endpoints with OpenAI compatibility.

### Authentication Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/register` | Register new user |
| POST | `/auth/login` | Login, returns JWT |
| GET | `/users/me` | Get current user |

### Organization Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/orgs` | List user's organizations |
| POST | `/orgs` | Create organization |
| GET | `/orgs/:id` | Get organization details |
| GET | `/orgs/:id/members` | List members |
| POST | `/orgs/:id/invite` | Invite member |

### API Key Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api-keys` | List API keys |
| POST | `/api-keys` | Create API key |
| DELETE | `/api-keys/:id` | Delete API key |

### Provider Key (BYOK) Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/provider-keys` | List provider keys |
| POST | `/provider-keys` | Add provider key |
| DELETE | `/provider-keys/:provider` | Remove provider key |

### Session Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/sessions` | List sessions |
| POST | `/v1/sessions` | Create session |
| GET | `/v1/sessions/:id` | Get session |

These session endpoints are primarily **internal plumbing**. End-user and client applications should prefer the higher-level **thread** and **project** APIs described below—sessions are rotated automatically behind the scenes.

### Thread Endpoints (User-Facing)

Threads provide conversation continuity across rotated sessions. A thread can be linked to a project and organized into a hierarchy of related threads and context nodes.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/threads` | List threads for the authenticated user (optionally filtered by project or status) |
| POST | `/v1/threads` | Create a new thread (optionally as a child or continuation of another) |
| GET | `/v1/threads/:id` | Get thread details plus relations and context tree |
| PATCH | `/v1/threads/:id` | Update thread title, status, or summary |
| POST | `/v1/threads/:id/messages` | Post a chat message on a thread (LLM integration pending in the router) |
| POST | `/v1/threads/:id/relations` | Create a relation to another thread (`continues_from`, `child_of`, `relates_to`) |
| GET | `/v1/threads/:id/contexts` | Fetch the hierarchical context nodes for a thread |
| POST | `/v1/threads/:id/contexts` | Add a context node to a thread |

#### Thread Relations

- **`continues_from`** — Linear continuation from an earlier thread  
- **`child_of`** — Hierarchical child thread for subtopics or decomposed work  
- **`relates_to`** — Loose association without strict hierarchy

### Project Endpoints

Projects act as workspaces that group related threads. A project can capture configuration, repository metadata, or other settings in a JSON `settings` field.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/projects` | List projects for the authenticated user (or organization) |
| POST | `/v1/projects` | Create a new project |
| GET | `/v1/projects/:id` | Get project details, including associated threads |

### OpenAI-Compatible Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/v1/chat/completions` | Chat completion |
| GET | `/v1/models` | List available models |
| GET | `/api/models/:model_name` | Get model details |

### Health Check

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |

### Response Helpers

```racket
(json-response data #:status 200)
(error-response "message" #:status 400 #:code "error_code")
(not-found-response)
(unauthorized-response)
(forbidden-response)
```

### Request Parsing

```racket
(parse-json-body request)      ; → hash
(get-path-param request 'id)   ; → string or #f
(get-query-param request 'page "1") ; → string
```
