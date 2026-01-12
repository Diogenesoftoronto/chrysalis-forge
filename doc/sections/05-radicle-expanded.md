## 5.2 Radicle P2P Layer (Expanded)

### 5.2.1 Why Radicle for Chrysalis Forge

| Requirement | Radicle Capability |
|-------------|-------------------|
| DID-based identity | Ed25519 keypairs, did:key format |
| Git-native workflow | Built on Git, no new data model |
| P2P without servers | Gossip protocol, no central point |
| Social artifacts | COBs for issues, patches, discussions |
| Offline-first | Local-first, sync when connected |
| Jujutsu support | [Radicle 1.5+ supports jj](https://radicle.xyz/2025/08/14/jujutsu-with-radicle.html) |

Citation: [Radicle Protocol Guide](https://radicle.xyz/guides/protocol)

### 5.2.2 Radicle Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Radicle Stack                        │
├─────────────────────────────────────────────────────────┤
│  rad CLI          │  Radicle Web    │  Radicle Desktop  │
├─────────────────────────────────────────────────────────┤
│              Radicle Repository                         │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐             │
│  │   code   │  │  issues  │  │  patches  │  (COBs)     │
│  └──────────┘  └──────────┘  └───────────┘             │
├─────────────────────────────────────────────────────────┤
│              Radicle Storage (Git)                      │
├───────────────────────┬─────────────────────────────────┤
│    Radicle Node       │      Radicle HTTPD              │
│    (NoiseXK P2P)      │      (HTTP + JSON API)          │
└───────────────────────┴─────────────────────────────────┘
```

### 5.2.3 Key Radicle Concepts

**Repository ID (RID)**
- Unique identifier derived from identity document
- Format: `rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5`
- Used in URLs: `rad://z3gqcJUoA1n9HaHKufZs5FCSGazv5`

**Node ID (NID)**
- Ed25519 public key, Base58 encoded
- Same key we use for did:key
- Example: `z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK`

**Collaborative Objects (COBs)**
- Social artifacts stored as Git objects
- Types: Issues, Patches, Identities
- Cryptographically signed by author
- CRDT-like: merge by unioning commit graphs

### 5.2.4 CLI Integration Examples

#### Initialize Chrysalis Identity with Radicle
```bash
# If starting fresh with Radicle
rad auth --alias "chrysalis-node"

# Radicle creates ~/.radicle/keys/radicle.key
# This is an Ed25519 keypair

# Export to Chrysalis format
cf-identity --import-radicle ~/.radicle/keys/radicle.key

# Or import Chrysalis identity to Radicle
cf-identity --export-radicle | rad auth --stdin
```

#### Create Elite Repository
```bash
# Initialize git repo for elites
mkdir chrysalis-elites && cd chrysalis-elites
git init

# Initialize as Radicle project
rad init --name "chrysalis-elites" --description "Elite agent configurations"

# Output: Repository rad:z4V1sjrXqjvFdnCUbxPFqd5p4DtH5 created

# Add remote for seeding
rad remote add seed.radicle.xyz
```

#### Publish Elite Agents
```bash
# Generate and export elites
cf-generate-elites
cf-export-elites --to ./agents/

# Commit and push
git add agents/
git commit -m "Publish elites from did:key:z6Mk..."
git push rad

# Sync with network
rad sync
```

#### Discover Elite Agents
```bash
# Clone someone else's elite repo
rad clone rad:z4V1sjrXqjvFdnCUbxPFqd5p4DtH5

# Or seed it (replicate without cloning)
rad seed rad:z4V1sjrXqjvFdnCUbxPFqd5p4DtH5

# List available agents
cf-discover-elites --repo ./chrysalis-elites

# Import specific agent
cf-import-elite --agent-id a1b2c3...
```

### 5.2.5 Radicle HTTPD API Integration

For programmatic access, use `radicle-httpd`:

```bash
# Start HTTP daemon
radicle-httpd --listen 127.0.0.1:8080
```

**API Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/projects` | GET | List all projects |
| `/api/v1/projects/:rid` | GET | Get project info |
| `/api/v1/projects/:rid/tree/:commit/:path` | GET | Get file content |
| `/api/v1/projects/:rid/commits` | GET | List commits |

**Racket HTTP Client Example:**
```racket
(require net/http-easy
         json)

(define (list-radicle-projects)
  (define resp (get "http://127.0.0.1:8080/api/v1/projects"))
  (response-json resp))

(define (get-elite-manifest rid agent-id)
  (define path (format "agents/~a/manifest.json" agent-id))
  (define url (format "http://127.0.0.1:8080/api/v1/projects/~a/tree/HEAD/~a" rid path))
  (response-json (get url)))
```

### 5.2.6 Seed Node Configuration

For reliable discovery, configure seed nodes:

**~/.radicle/config.json:**
```json
{
  "node": {
    "alias": "chrysalis-node",
    "listen": ["0.0.0.0:8776"],
    "peers": {
      "type": "static",
      "peers": [
        "z6Mkg...@seed.radicle.xyz:8776",
        "z6Mkf...@seed.radicle.garden:8776"
      ]
    }
  }
}
```

### 5.2.7 Webhooks for CI/Automation

Radicle supports webhooks via CI Broker:

```yaml
# .radicle/webhooks.yaml
webhooks:
  - url: "https://your-server.com/elite-update"
    events: ["push"]
    secret: "${WEBHOOK_SECRET}"
```

When elites are pushed, trigger:
1. Pull latest manifests
2. Verify signatures
3. Update local elite cache
4. Notify users of new agents

Citation: [Radicle CI Integration](https://kraken.ci/blog/integration-with-radicle/)

### 5.2.8 Chrysalis-Radicle Tool Mapping

| Chrysalis Tool | Radicle Equivalent | Notes |
|----------------|-------------------|-------|
| `git_status` | `rad inspect` | Project status |
| `git_commit` | `git commit` + `rad sync` | Commit and propagate |
| `git_push` | `git push rad` | Push to rad remote |
| `export_elite_agents` | N/A (new) | Export + commit + push |
| `import_elite_agent` | `rad clone` + parse | Clone and import |
| `discover_elites` | `rad ls` + filter | List and filter projects |
