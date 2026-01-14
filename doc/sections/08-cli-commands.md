# 8. CLI Commands Reference

This section specifies all CLI commands for the Chrysalis Forge decentralized architecture, organized by implementation phase.

---

## Phase 1: Identity & Local Elite Generation

### 8.1 `cf-identity` — Identity Management

Manage your cryptographic identity (DID, Ed25519 keypair) for signing agent manifests and interacting with decentralized networks.

#### Synopsis

```bash
cf-identity <subcommand> [options]
```

#### Subcommands

##### `cf-identity init`

Create a new identity (Ed25519 keypair and did:key).

```bash
cf-identity init [--alias NAME]
```

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--alias` | string | none | Human-readable name for this identity |

**Example:**

```bash
cf-identity init --alias "my-dev-node"
# Created identity: did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK
# Saved to: ~/.chrysalis/identity.json
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | Identity created successfully |
| 1 | Identity already exists (use `--force` to overwrite) |
| 2 | Filesystem error (permissions, disk full) |

---

##### `cf-identity show`

Display the current identity's DID and alias.

```bash
cf-identity show
```

**Example:**

```bash
cf-identity show
# DID:   did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK
# Alias: my-dev-node
# Created: 2024-01-01T00:00:00Z
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | Identity displayed |
| 1 | No identity found |

---

##### `cf-identity export`

Export the identity key in various formats for interoperability.

```bash
cf-identity export [--format json|radicle|nostr]
```

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--format` | enum | `json` | Output format: `json` (native), `radicle` (rad-compatible), `nostr` (npub/nsec) |

**Example:**

```bash
cf-identity export --format nostr
# npub: npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqef0xyz
# nsec: [REDACTED - use --show-secret to display]

cf-identity export --format radicle > ~/.radicle/keys/chrysalis.key
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | Export successful |
| 1 | No identity found |
| 2 | Invalid format specified |

---

##### `cf-identity import`

Import an existing key from another system.

```bash
cf-identity import --radicle PATH
```

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--radicle` | path | required | Path to Radicle key file |

**Example:**

```bash
cf-identity import --radicle ~/.radicle/keys/radicle.key
# Imported identity: did:key:z6Mk...
# Saved to: ~/.chrysalis/identity.json
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | Import successful |
| 1 | Key file not found |
| 2 | Invalid key format |
| 3 | Identity already exists (use `--force`) |

---

##### `cf-identity rotate`

Rotate to a new keypair with a signed transition statement.

```bash
cf-identity rotate
```

**Description:**

1. Generates a new Ed25519 keypair
2. Creates a signed rotation statement linking old DID → new DID
3. Saves rotation proof to `~/.chrysalis/rotations/<timestamp>.json`
4. Updates `identity.json` with new keypair

**Example:**

```bash
cf-identity rotate
# ⚠ WARNING: This will rotate your identity key.
# Old DID: did:key:z6MkOLD...
# New DID: did:key:z6MkNEW...
# Rotation proof saved to: ~/.chrysalis/rotations/1704067200.json
# Proceed? [y/N]: y
# Identity rotated successfully.
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | Rotation successful |
| 1 | No identity to rotate |
| 2 | User cancelled |

---

##### `cf-identity verify`

Verify the integrity of the current identity.

```bash
cf-identity verify
```

**Description:**

- Checks that public key derives correctly from private key
- Verifies DID construction matches public key
- Tests sign/verify round-trip

**Example:**

```bash
cf-identity verify
# ✓ Keypair valid
# ✓ DID matches public key
# ✓ Sign/verify round-trip successful
# Identity integrity verified.
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | Identity valid |
| 1 | No identity found |
| 2 | Integrity check failed |

---

##### `cf-identity backup`

Create an encrypted backup of the identity.

```bash
cf-identity backup --encrypt
```

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--encrypt` | flag | false | Encrypt backup with passphrase (uses `age`) |
| `--output` | path | `~/.chrysalis/identity.json.backup` | Output path |

**Example:**

```bash
cf-identity backup --encrypt
# Enter passphrase: ********
# Confirm passphrase: ********
# Backup saved to: ~/.chrysalis/identity.json.backup
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | Backup created |
| 1 | No identity found |
| 2 | Encryption failed |
| 3 | Passphrase mismatch |

---

### 8.2 `cf-generate-elites` — Generate Elite Manifests

Analyze local evaluation data and generate signed manifests for elite-qualified agents.

#### Synopsis

```bash
cf-generate-elites [options]
```

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--threshold` | float | `0.80` | Minimum success rate to qualify as elite |
| `--min-tasks` | integer | `50` | Minimum completed tasks for statistical significance |
| `--task-type` | string | all | Filter to specific task type (e.g., `file-edit`, `search`, `vcs`) |
| `--force` | flag | false | Regenerate all manifests, even if unchanged |
| `--dry-run` | flag | false | Show what would be generated without writing files |

#### Description

Reads evaluation data from `~/.chrysalis/evals.jsonl`, identifies agents meeting elite criteria, and generates signed manifests in `~/.chrysalis/elite/`.

#### Example

```bash
cf-generate-elites --threshold 0.85 --min-tasks 100 --dry-run
# Scanning evals.jsonl... 2,847 evaluations found.
# 
# Agents qualifying as elite:
#   agent:a1b2c3d4 (editor profile)
#     Success rate: 92.3% (478/518 tasks)
#     Task types: file-edit, patch
#     Would generate: ~/.chrysalis/elite/a1b2c3d4.json
#   
#   agent:e5f6g7h8 (researcher profile)
#     Success rate: 87.1% (203/233 tasks)
#     Task types: search, analysis
#     Would generate: ~/.chrysalis/elite/e5f6g7h8.json
# 
# Dry run complete. 2 manifests would be generated.

cf-generate-elites --force
# Generated 2 elite manifests in ~/.chrysalis/elite/
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Manifests generated (or dry-run complete) |
| 1 | No identity found (run `cf-identity init` first) |
| 2 | No evaluations found |
| 3 | No agents qualified as elite |
| 4 | Write error |

---

## Phase 2: Import/Export Elite Agents

### 8.3 `cf-export-elites` — Export Elite Agents

Export elite agent manifests for sharing with other users or publishing to repositories.

#### Synopsis

```bash
cf-export-elites [options]
```

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--to` | path | `./.chrysalis-export/` | Output directory for exported manifests |
| `--agent-id` | string | all | Export only a specific agent (by ID prefix) |
| `--include-prompts` | flag | false | Include full system prompt content (opt-in, may contain sensitive info) |
| `--include-demos` | flag | false | Include few-shot demo examples (opt-in) |

#### Description

Exports elite manifests in a portable format suitable for sharing. By default, only exports metadata and metrics—prompt content and demos are opt-in to protect potentially proprietary information.

#### Example

```bash
cf-export-elites --to ./shared-elites/ --include-demos
# Exporting elite agents...
#   ✓ agent:a1b2c3d4 → ./shared-elites/a1b2c3d4.json
#   ✓ agent:e5f6g7h8 → ./shared-elites/e5f6g7h8.json
# Exported 2 agents (demos included, prompts excluded).

cf-export-elites --agent-id a1b2 --include-prompts --include-demos
# Exporting elite agents...
#   ✓ agent:a1b2c3d4 → ./.chrysalis-export/a1b2c3d4.json
# Exported 1 agent (full content included).
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Export successful |
| 1 | No elite manifests found |
| 2 | Agent ID not found |
| 3 | Output directory error |

---

### 8.4 `cf-discover-elites` — Discover Elite Agents

Scan a repository for elite agent manifests.

#### Synopsis

```bash
cf-discover-elites [options]
```

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--repo` | path or URL | `.` | Repository to scan (local path or git URL) |
| `--task-type` | string | all | Filter by task type capability |
| `--min-rate` | float | `0.80` | Minimum success rate to show |
| `--verify` | flag | false | Verify all manifest signatures |

#### Description

Discovers `.chrysalis/elite/*.json` manifests in a repository. Can scan local directories or clone remote repositories temporarily for scanning.

#### Example

```bash
cf-discover-elites --repo https://github.com/user/my-agents --verify
# Cloning repository...
# Scanning for elite manifests...
# 
# Found 3 elite agents:
# 
#   agent:a1b2c3d4
#     Owner: did:key:z6Mk...
#     Profile: editor
#     Success rate: 92.3%
#     Task types: file-edit, patch
#     Signature: ✓ valid
# 
#   agent:e5f6g7h8
#     Owner: did:key:z6Mk...
#     Profile: researcher
#     Success rate: 87.1%
#     Task types: search
#     Signature: ✓ valid
# 
#   agent:i9j0k1l2
#     Owner: did:key:z6Mk...
#     Profile: vcs
#     Success rate: 81.5%
#     Task types: git, jj
#     Signature: ✗ INVALID (owner DID mismatch)

cf-discover-elites --task-type file-edit --min-rate 0.90
# Found 1 elite agent matching criteria.
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Discovery complete |
| 1 | Repository not found or inaccessible |
| 2 | No manifests found |
| 3 | Clone/fetch error |

---

### 8.5 `cf-import-elite` — Import an Elite Agent

Import an elite agent manifest into your local registry.

#### Synopsis

```bash
cf-import-elite [options]
```

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--agent-id` | string | required | Agent ID to import (prefix match allowed) |
| `--from` | path or URL | required | Source repository or directory |
| `--trust-did` | string | none | Add the owner's DID to trusted list |

#### Description

Imports an elite agent manifest after signature verification. If the owner's DID is not already trusted, requires explicit `--trust-did` to proceed.

#### Example

```bash
cf-import-elite --agent-id a1b2c3d4 --from https://github.com/user/agents
# Fetching manifest...
# Verifying signature...
# 
# Agent: a1b2c3d4
# Owner: did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK
# Signature: ✓ valid
# 
# ⚠ Owner DID is not in your trusted list.
# Use --trust-did to add and proceed.

cf-import-elite --agent-id a1b2c3d4 --from ./shared-elites/ \
  --trust-did did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK
# ✓ Added DID to trusted list
# ✓ Imported agent:a1b2c3d4 to ~/.chrysalis/imported/a1b2c3d4.json
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Import successful |
| 1 | Agent not found |
| 2 | Signature verification failed |
| 3 | DID not trusted (and --trust-did not provided) |
| 4 | Filesystem error |

---

## Phase 3: Radicle Integration

### 8.6 `cf-rad-publish` — Publish to Radicle

Publish elite manifests to a Radicle project for decentralized distribution.

#### Synopsis

```bash
cf-rad-publish [options]
```

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--project` | string | auto-detect | Radicle project ID (RID) |
| `--sync` | flag | false | Sync with network after publish |

#### Description

Commits elite manifests to the `.chrysalis/elite/` directory in a Radicle-tracked repository and optionally syncs with the network.

**Prerequisites:**

- `rad` CLI installed and authenticated
- Repository initialized with Radicle (`rad init`)
- Valid Chrysalis identity (automatically exports to Radicle format)

#### Example

```bash
cf-rad-publish --sync
# Detected Radicle project: rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5
# 
# Publishing elite manifests...
#   ✓ Staged .chrysalis/elite/a1b2c3d4.json
#   ✓ Staged .chrysalis/elite/e5f6g7h8.json
# 
# Creating commit...
#   ✓ Committed: "chore: update elite manifests"
# 
# Syncing with network...
#   ✓ Pushed to 3 seeds
# 
# Published successfully.

cf-rad-publish --project rad:z3abc123
# Publishing to explicit project rad:z3abc123...
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Publish successful |
| 1 | Not a Radicle repository |
| 2 | No elite manifests to publish |
| 3 | Radicle authentication error |
| 4 | Sync failed (publish still succeeded locally) |

---

### 8.7 `cf-rad-clone` — Clone from Radicle

Clone a repository from the Radicle network and discover elite agents.

#### Synopsis

```bash
cf-rad-clone <rad:RID> [options]
```

#### Arguments

| Argument | Type | Description |
|----------|------|-------------|
| `rad:RID` | string | Radicle project identifier |

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--path` | path | `./<project-name>` | Local path for clone |
| `--discover` | flag | false | Run `cf-discover-elites` after clone |

#### Description

Clones a Radicle repository and optionally discovers elite agents within it.

#### Example

```bash
cf-rad-clone rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5 --discover
# Cloning from Radicle network...
#   ✓ Connected to seed node
#   ✓ Fetching repository...
#   ✓ Cloned to ./chrysalis-community-agents/
# 
# Discovering elite agents...
#   Found 5 elite agents in .chrysalis/elite/
#   Run `cf-discover-elites` for details.
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Clone successful |
| 1 | Invalid RID format |
| 2 | Project not found on network |
| 3 | Clone failed |

---

## Phase 4: Decentralized Compute Integration

### 8.8 `cf-submit-training` — Submit Training Job

Submit a distributed training job to decentralized compute providers.

#### Synopsis

```bash
cf-submit-training [options]
```

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--job-spec` | path | required | Path to `training-job.json` specification |
| `--backend` | enum | `akash` | Compute backend: `akash`, `tashi`, or `prime` |
| `--budget` | float | none | Maximum cost in USD (job fails if exceeded) |
| `--dry-run` | flag | false | Validate job spec without submitting |

#### Description

Submits a training job to a decentralized compute network. The job specification includes dataset references, model parameters, and resource requirements.

**Job Spec Format (`training-job.json`):**

```json
{
  "name": "elite-finetuning-v1",
  "base_model": "meta-llama/Llama-3.1-8B",
  "dataset": {
    "type": "elite-traces",
    "agents": ["a1b2c3d4", "e5f6g7h8"],
    "min_success_rate": 0.90
  },
  "training": {
    "method": "lora",
    "epochs": 3,
    "batch_size": 4
  },
  "resources": {
    "gpu": "A100",
    "gpu_count": 1,
    "max_hours": 8
  }
}
```

#### Example

```bash
cf-submit-training --job-spec ./training-job.json --backend akash --budget 50
# Validating job specification...
#   ✓ Base model available
#   ✓ Dataset: 2 elite agents, 1,247 traces
#   ✓ Resource requirements: 1x A100, max 8 hours
# 
# Estimating cost...
#   Estimated: $23.50 - $31.00
#   Budget: $50.00 ✓
# 
# Submitting to Akash network...
#   ✓ Deployment created
#   ✓ Job ID: akash-train-a1b2c3d4e5f6
# 
# Monitor with: cf-check-training --job-id akash-train-a1b2c3d4e5f6

cf-submit-training --job-spec ./job.json --dry-run
# [Validates without submitting]
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Job submitted successfully |
| 1 | Invalid job specification |
| 2 | Budget exceeded estimate |
| 3 | Backend authentication error |
| 4 | Submission failed |

---

### 8.9 `cf-check-training` — Check Training Status

Check the status of a submitted training job.

#### Synopsis

```bash
cf-check-training [options]
```

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--job-id` | string | required | Job ID returned by `cf-submit-training` |
| `--watch` | flag | false | Continuously poll status until completion |
| `--logs` | flag | false | Stream training logs |

#### Description

Queries the compute backend for job status, progress, and any errors.

#### Example

```bash
cf-check-training --job-id akash-train-a1b2c3d4e5f6
# Job: akash-train-a1b2c3d4e5f6
# Status: RUNNING
# Progress: Epoch 2/3 (67%)
# Runtime: 2h 15m
# Cost so far: $12.30
# 
# Estimated completion: 1h 10m

cf-check-training --job-id akash-train-a1b2c3d4e5f6 --logs
# [2024-01-15 10:23:45] Starting epoch 2...
# [2024-01-15 10:23:46] Batch 1/312: loss=0.234
# [2024-01-15 10:23:47] Batch 2/312: loss=0.228
# ...
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Status retrieved (or job completed if `--watch`) |
| 1 | Job ID not found |
| 2 | Backend connection error |
| 3 | Job failed |

---

### 8.10 `cf-fetch-artifacts` — Fetch Training Results

Download artifacts (model weights, logs, metrics) from a completed training job.

#### Synopsis

```bash
cf-fetch-artifacts [options]
```

#### Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--job-id` | string | required | Job ID to fetch artifacts from |
| `--output` | path | `./training-output/` | Output directory |
| `--artifacts` | string | `all` | Comma-separated list: `model`, `logs`, `metrics`, or `all` |

#### Description

Downloads training artifacts from the compute provider. For large models, uses chunked download with resume support.

#### Example

```bash
cf-fetch-artifacts --job-id akash-train-a1b2c3d4e5f6
# Fetching artifacts...
#   ✓ metrics.json (2.3 KB)
#   ✓ training.log (156 KB)
#   ✓ model.safetensors (4.2 GB) [=====>    ] 52%
#   ✓ adapter_config.json (1.1 KB)
# 
# All artifacts saved to ./training-output/

cf-fetch-artifacts --job-id akash-train-a1b2c3d4e5f6 --artifacts metrics,logs
# Fetching selected artifacts...
#   ✓ metrics.json (2.3 KB)
#   ✓ training.log (156 KB)
# 
# Saved to ./training-output/
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Artifacts downloaded successfully |
| 1 | Job ID not found |
| 2 | Job not complete (still running or failed) |
| 3 | Download failed (partial artifacts may exist) |
| 4 | Verification failed (checksum mismatch) |

---

## Environment Variables

All commands respect these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `CHRYSALIS_HOME` | Base directory for Chrysalis data | `~/.chrysalis` |
| `CHRYSALIS_IDENTITY` | Path to identity file | `$CHRYSALIS_HOME/identity.json` |
| `CF_RAD_SEED` | Preferred Radicle seed node | auto-discover |
| `CF_COMPUTE_BACKEND` | Default compute backend | `akash` |

---

## Global Flags

All commands support these global flags:

| Flag | Description |
|------|-------------|
| `--help`, `-h` | Show command help |
| `--version`, `-v` | Show version |
| `--verbose` | Enable verbose output |
| `--quiet`, `-q` | Suppress non-error output |
| `--json` | Output in JSON format (for scripting) |
| `--color` | Force color output (auto-detected by default) |
| `--no-color` | Disable color output |
