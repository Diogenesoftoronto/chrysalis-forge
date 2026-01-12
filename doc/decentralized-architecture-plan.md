# Decentralized Collaborative Architecture for Chrysalis Forge

## Executive Summary

This document outlines a design for enabling **decentralized collaborative features** in Chrysalis Forge, an evolvable AI agent system written in Racket. The architecture enables:

1. **Elite Agent Registry** - Share agent configurations that perform best across a network
2. **DID-based Identity** - W3C Decentralized Identifiers (preferred over blockchain wallets)
3. **Git-native Collaboration** - Leverage Radicle's P2P git for sharing agent code/configs
4. **Decentralized Compute** - Potential for finetuning/RL training via Akash, Tashi, or Prime Intellect

The design follows a **phased approach**, starting with local identity and Git-based sharing, progressing to Radicle P2P, and optionally advancing to more complex systems (Freenet, DWN, P2PFL) only when scale demands it.

---

## 1. Introduction

### 1.1 Vision

From the original conversation:

> "It would be cool to give the agent decentralized collaborative features, like you could also have it store its registry of elite agents across the network in a way that would let you discover what worked best across the whole network."

> "Radicle for collab stuff offers a lot of identity stuff and it already has some git support... the self-improving decentralized coding agent."

Key goals:
- Store registry of elite agents across the network
- Discover what worked best across the whole network
- Enable self-improving, decentralized coding agents
- Use Radicle for collaboration with identity support

### 1.2 Design Principles

1. **Prefer DIDs over blockchain wallets** - Web5-like approach, no token/chain dependency
2. **Git-native collaboration** - Radicle for P2P, works with existing workflows
3. **Local-first, incrementally decentralized** - Simple Git → Radicle → Advanced P2P
4. **Privacy-preserving** - Share metrics, not raw traces or prompts
5. **Separation of concerns** - Thin orchestrator for compute, Chrysalis for agent evolution

---

## 2. Research Overview

### 2.1 Technologies Evaluated

| Technology | Category | Key Features | Relevance |
|------------|----------|--------------|-----------|
| [Radicle](https://radicle.xyz/) | P2P Collaboration | Ed25519 DIDs, gossip protocol, COBs in Git | Primary collaboration layer |
| [Web5/DWN](https://identity.foundation/decentralized-web-node/spec/) | Identity + Storage | Mesh datastore with DIDs, protocols | Concepts useful, TBD sunset |
| [Freenet](https://freenet.org/) | Decentralized Apps | Small-world routing, WASM contracts | Future global state option |
| [Nostr](https://nostr.com/) | Messaging | Relay-based, Ed25519 keypairs | Optional announcement layer |
| [Akash](https://akash.network/) | Compute | Decentralized GPU marketplace | Training backend |
| [Tashi](https://tashi.network/) | Real-time Compute | DAG consensus (<50ms), DePIN | Low-latency RL |
| [Prime Intellect](https://www.primeintellect.ai/) | Distributed RL | Async RL, TOPLOC verification | Frontier RL training |
| [P2PFL](https://github.com/p2pfl/p2pfl) | Federated Learning | Gossip protocols, privacy-preserving | Cross-org training |

### 2.2 Key Research Citations

#### Identity & Collaboration
- [Radicle Protocol Guide](https://radicle.xyz/guides/protocol) - P2P git, Ed25519 DIDs, Collaborative Objects
- [Radicle User Guide](https://radicle.xyz/guides/user/) - CLI usage, node operation
- [DIF DWN Specification](https://identity.foundation/decentralized-web-node/spec/) - Mesh datastore with DIDs
- [Web5 Overview](https://www.identity.com/web5/) - TBD's vision (sunset Dec 2024)
- [Nostr Protocol Comparison](https://soapbox.pub/blog/comparing-protocols) - vs ActivityPub, Bluesky

#### Decentralized Compute
- [Akash Foundation Model Training](https://akash.network/blog/foundation-ai-model-training-on-akash/) - 32x A100 training demonstrated
- [Tashi Network](https://tashi.network/) - DAG consensus, DePIN model
- [Prime Intellect INTELLECT-2](https://www.primeintellect.ai/blog/intellect-2) - 32B distributed RL training
- [Prime Intellect Decentralized Training](https://www.primeintellect.ai/blog/our-approach-to-decentralized-training) - DiLoCo, SWARM parallelism

#### Federated/Distributed Learning
- [P2PFL Library](https://github.com/p2pfl/p2pfl) - Gossip-based federated learning
- [Federated RL for P2P Energy Trading](https://www.sciencedirect.com/science/article/pii/S2666546825000321) - Multi-agent RL

#### Alternative Architectures
- [Freenet Tutorial](https://freenet.org/resources/manual/tutorial/) - WASM contracts, small-world routing
- [Decentralized AI Networks](https://coingeek.com/decentralized-ai-networks-merging-web3-and-machine-learning/) - Sahara, CARV

---

## 3. Identity Layer Design

### 3.1 Chosen Approach: `did:key` with Ed25519

We use the W3C DID standard with the `did:key` method:

- **Ed25519 keypairs** - Same as Radicle and Nostr use
- **No blockchain required** - Self-contained, purely local
- **Keys stored at** `~/.agentd/identity.json`

### 3.2 Why DIDs Over Blockchain Wallets

| Aspect | DID-based (chosen) | Blockchain Wallet |
|--------|-------------------|-------------------|
| Infrastructure | None required | Requires chain |
| Interoperability | Radicle, Nostr compatible | Chain-specific |
| Privacy | Self-sovereign | Public ledger |
| Complexity | Low | High |
| Cost | Free | Gas fees |
| Key format | Ed25519 (standard) | Varies by chain |

### 3.3 Alternatives Considered

#### Web5 / Decentralized Web Nodes
- **Pros**: Full DWN spec, mesh sync, protocols for data types
- **Cons**: TBD sunset (Dec 2024), uncertain future
- **Decision**: Monitor DIF's continued DWN work, don't depend on it initially
- **Citation**: [DWN Spec](https://identity.foundation/decentralized-web-node/spec/)

#### Nostr Identity
- **Pros**: Same Ed25519 keys, relay-based messaging, active ecosystem
- **Cons**: Primarily social media focused, no native git integration
- **Decision**: Use as optional announcement layer (Phase 3+)
- **Citation**: [Nostr Comparison](https://soapbox.pub/blog/comparing-protocols)

#### Radicle DID
- **Pros**: Already uses Ed25519 DIDs, git-native, COBs for social artifacts
- **Cons**: Still maturing, limited ecosystem
- **Decision**: Primary collaboration layer for Phase 3
- **Citation**: [Radicle Protocol Guide](https://radicle.xyz/guides/protocol)

### 3.4 Identity Implementation (Expanded)

#### 3.4.1 File Structure

```
~/.agentd/
  identity.json          # Node DID + keypair
  identity.json.backup   # Encrypted backup
  elite/
    <agent-id>.json      # Signed agent manifests
```

#### 3.4.2 identity.json Format

Full JSON schema with all fields explained:

| Field | Type | Description |
|-------|------|-------------|
| `did` | string | The did:key identifier (e.g., `did:key:z6Mk...`) |
| `publicKeyBase58` | string | Base58-encoded Ed25519 public key (32 bytes) |
| `secretKeyBase58` | string | Base58-encoded Ed25519 private key (64 bytes) — **NEVER share** |
| `publicKeyMultibase` | string | Multibase-encoded public key for did:key construction |
| `createdAt` | integer | Unix timestamp of key creation |
| `alias` | string? | Optional human-readable name for this identity |

Example:

```json
{
  "did": "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK",
  "publicKeyBase58": "B12NYF8RrR3h41TDCTJojY59usg3mbtbjnFs7Eud1Y6u",
  "secretKeyBase58": "2rABDfZqT8SyfHxBy...[REDACTED]",
  "publicKeyMultibase": "z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK",
  "createdAt": 1704067200,
  "alias": "chrysalis-dev"
}
```

#### 3.4.3 DID Construction from Ed25519 Key

The `did:key` method encodes the public key directly in the identifier:

1. **Generate Ed25519 keypair** — produces 32-byte public key
2. **Prepend multicodec prefix** for ed25519-pub: `0xed01`
3. **Encode with multibase** using base58-btc (prefix `z`)
4. **Prepend "did:key:"** → `did:key:z6Mk...`

**Byte-level Construction:**

```
Raw Ed25519 public key (32 bytes):
  B12NYF8RrR3h41TDCTJojY59usg3mbtbjnFs7Eud1Y6u (Base58)

With multicodec prefix (34 bytes):
  [0xed, 0x01] ++ [32 public key bytes]

Multibase encode (base58-btc, prefix 'z'):
  z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK

Final DID:
  did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK
```

The multicodec prefix `0xed01` is a varint encoding:
- `0xed` = 237 in unsigned LEB128 → indicates ed25519-pub
- `0x01` = continuation byte

#### 3.4.4 Racket Implementation Skeleton

```racket
#lang racket/base
(require crypto
         crypto/libcrypto
         json
         file/sha1
         net/base64)

(provide load-or-create-identity
         sign-bytes
         verify-signature
         did->public-key
         current-identity)

;; Current identity parameter
(define current-identity (make-parameter #f))

;; Load existing or create new identity
(define (load-or-create-identity [path "~/.agentd/identity.json"])
  (define expanded (expand-user-path path))
  (if (file-exists? expanded)
      (with-input-from-file expanded
        (λ () (current-identity (read-json))))
      (let ([id (generate-identity)])
        (make-parent-directory* expanded)
        (with-output-to-file expanded
          (λ () (write-json id)))
        (current-identity id)))
  (current-identity))

;; Generate new Ed25519 keypair and DID
(define (generate-identity)
  (define kp (generate-private-key 'eddsa '((curve ed25519))))
  (define pk-bytes (pk-key->datum kp 'rkt-public))
  (define sk-bytes (pk-key->datum kp 'rkt-private))
  (define did (public-key->did pk-bytes))
  (hasheq 'did did
          'publicKeyBase58 (bytes->base58 pk-bytes)
          'secretKeyBase58 (bytes->base58 sk-bytes)
          'publicKeyMultibase (bytes->multibase pk-bytes)
          'createdAt (current-seconds)
          'alias #f))

;; Construct did:key from public key bytes
(define (public-key->did pk-bytes)
  (string-append "did:key:" (bytes->multibase pk-bytes)))

;; Multibase encode with ed25519 multicodec prefix
(define (bytes->multibase pk-bytes)
  (define prefixed (bytes-append #"\xed\x01" pk-bytes))
  (string-append "z" (bytes->base58 prefixed)))

;; Sign arbitrary bytes with identity's private key
(define (sign-bytes data)
  (define id (current-identity))
  (unless id (error 'sign-bytes "No identity loaded"))
  (define sk (base58->bytes (hash-ref id 'secretKeyBase58)))
  (define kp (datum->pk-key sk 'rkt-private))
  (pk-sign kp data))

;; Verify signature against a DID
(define (verify-signature did data signature)
  (define pk-bytes (did->public-key did))
  (define pk (datum->pk-key pk-bytes 'rkt-public))
  (pk-verify pk data signature))

;; Extract public key from did:key
(define (did->public-key did)
  (unless (string-prefix? did "did:key:z")
    (error 'did->public-key "Invalid did:key format"))
  (define multibase (substring did 8)) ; after "did:key:"
  (define decoded (base58->bytes (substring multibase 1))) ; remove 'z'
  (subbytes decoded 2)) ; remove 0xed01 prefix
```

#### 3.4.5 Interoperability

**With Radicle:**

Radicle uses the same Ed25519 keys, enabling direct interop:

```bash
# Import Chrysalis key to Radicle
rad auth --alias "chrysalis" --key ~/.agentd/identity.json

# Export Radicle key to Chrysalis format
cf-identity --import-radicle ~/.radicle/keys/radicle.key
```

- **Radicle Node ID (NID)** = Base58-encoded public key
- **Radicle DID** = `did:key:z6Mk...` (same format we use)

**With Nostr:**

Nostr uses Ed25519 but with bech32 encoding:

| Format | Prefix | Encoding |
|--------|--------|----------|
| npub | `npub1` | bech32 of public key |
| nsec | `nsec1` | bech32 of private key |
| did:key | `did:key:z6Mk` | multibase of multicodec-prefixed key |

```racket
;; Convert did:key to Nostr npub
(define (did->npub did)
  (define pk-bytes (did->public-key did))
  (bech32-encode "npub" pk-bytes))

;; Convert Nostr npub to did:key
(define (npub->did npub)
  (define pk-bytes (bech32-decode "npub" npub))
  (public-key->did pk-bytes))
```

#### 3.4.6 Key Backup and Recovery

**Backup Procedure:**

```bash
# Encrypt identity.json with passphrase
age -p ~/.agentd/identity.json > ~/.agentd/identity.json.backup
# or
gpg -c ~/.agentd/identity.json
```

**Recovery:**

```bash
# Decrypt backup
age -d ~/.agentd/identity.json.backup > ~/.agentd/identity.json

# Verify integrity
cf-identity --verify
```

**Key Rotation (When Compromised):**

```bash
# Generate new identity
cf-identity --rotate
```

Sign rotation statement with old key:
```json
{
  "type": "key-rotation",
  "from": "did:key:z6MkOLD...",
  "to": "did:key:z6MkNEW...",
  "timestamp": 1704067200,
  "signature": "<old-key-signature>"
}
```

#### 3.4.7 Example DID Document

For `did:key`, the DID document is implicit but resolves to:

```json
{
  "@context": [
    "https://www.w3.org/ns/did/v1",
    "https://w3id.org/security/suites/ed25519-2020/v1"
  ],
  "id": "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK",
  "verificationMethod": [{
    "id": "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK#z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK",
    "type": "Ed25519VerificationKey2020",
    "controller": "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK",
    "publicKeyMultibase": "z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"
  }],
  "authentication": [
    "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK#z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"
  ],
  "assertionMethod": [
    "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK#z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK"
  ]
}
```

---

## 4. Elite Agent Registry

### 4.1 Concept

The Elite Agent Registry transforms local performance data from `evals.jsonl` into shareable, DID-signed manifests that can be discovered across the network.

**Key insight**: Share **aggregate metrics**, not raw traces (privacy-preserving).

### 4.2 Agent Manifest Schema

```json
{
  "agent_id": "sha256-hash-of-config",
  "owner_did": "did:key:z6Mkw...",
  "repo_ref": {
    "type": "git",
    "url": "...",
    "commit": "...",
    "path": "agents/<id>/manifest.json"
  },
  "signature": "OptSig",
  "module": "ChainOfThought",
  "profile": "editor",
  "system_prompt_fingerprint": "sha256(...)",
  "demos_fingerprint": "sha256(...)",
  "metrics": {
    "success_rate": 0.91,
    "total_tasks": 143,
    "avg_duration_ms": 5320
  },
  "task_type_stats": {
    "file-edit": { "success_rate": 0.94, "count": 92 },
    "search": { "success_rate": 0.87, "count": 51 }
  },
  "provenance": {
    "chrysalis_version": "0.3.0",
    "gepa_version": "1.0.0",
    "model": "gpt-4.1"
  },
  "created_at": 1712345678,
  "eval_window": {
    "from_ts": 1712000000,
    "to_ts": 1712345678
  },
  "signature_ed25519": "base64(sig(owner_did, canonical-json(manifest)))"
}
```

### 4.3 Integration with Existing Components

Links to existing Chrysalis Forge modules:
- [`src/stores/eval-store.rkt`](../src/stores/eval-store.rkt) - Source of performance metrics
- [`src/llm/optimizer-gepa.rkt`](../src/llm/optimizer-gepa.rkt) - Prompt evolution feedback
- [`src/stores/context-store.rkt`](../src/stores/context-store.rkt) - Agent context/configuration

New module: `src/stores/elite-registry.rkt`
- `(update-elite-registry!)` - Generate manifests from eval data
- `(generate-agent-manifests)` - Export to `~/.agentd/elite/`

### 4.4 Privacy Considerations

| Data Type | Shared? | Notes |
|-----------|---------|-------|
| Success metrics | ✅ Yes | Aggregate only |
| Task type stats | ✅ Yes | Categories, not content |
| Prompt fingerprint | ✅ Yes | Hash only, not full text |
| Raw prompts | ❌ No | Never without explicit opt-in |
| User traces | ❌ No | Never |
| Demo content | ❌ No | Fingerprint only |

### 4.5 Elite Selection Algorithm

#### Qualification Criteria

An agent qualifies as "elite" when:

- `success_rate >= 0.80` (80% success threshold)
- `total_tasks >= 50` (minimum sample size for statistical significance)
- `recent_tasks >= 10` in last 7 days (still actively used)
- No critical failures in last 24 hours

#### Ranking Formula

```
score = (success_rate * 0.6) + (recency_weight * 0.2) + (volume_weight * 0.2)

where:
  recency_weight = tasks_last_7d / total_tasks  (capped at 1.0)
  volume_weight = min(1.0, log10(total_tasks) / 3)  (log scale, caps at 1000 tasks)
```

#### Confidence Adjustment

For low sample sizes, apply Wilson score interval:

```
adjusted_rate = (successes + z²/2) / (n + z²)
where z = 1.96 for 95% confidence
```

#### Task-Type Specific Rankings

Maintain separate elite lists per task type:

- `elite-file-edit.json` - Best at file editing
- `elite-search.json` - Best at codebase search
- `elite-vcs.json` - Best at git/jj operations
- `elite-general.json` - Best overall

#### Pseudocode

```racket
(define (select-elites evals)
  (define grouped (group-by agent-config-hash evals))
  (for/list ([agent-evals (in-hash-values grouped)]
             #:when (elite-qualified? agent-evals))
    (make-manifest agent-evals)))

(define (elite-qualified? evals)
  (and (>= (length evals) 50)
       (>= (success-rate evals) 0.80)
       (>= (recent-count evals 7) 10)
       (no-critical-failures? evals 1)))
```

### 4.6 Agent ID Generation

#### Fields Included in Hash

The agent_id is a SHA-256 hash of the canonical agent configuration:

```json
{
  "signature": "OptSig",
  "signature_schema": {
    "inputs": ["inst", "fails"],
    "outputs": ["thought", "new_inst"]
  },
  "module": "ChainOfThought",
  "profile": "editor",
  "system_prompt_hash": "sha256:abc123...",
  "demos_hash": "sha256:def456...",
  "tools_enabled": ["read_file", "write_file", "patch_file"]
}
```

#### Canonical JSON Serialization

1. Sort all object keys alphabetically (recursive)
2. Remove all whitespace
3. Use consistent number formatting (no trailing zeros)
4. UTF-8 encode

#### Example

```
agent_id = sha256('{"demos_hash":"sha256:def456","module":"ChainOfThought",...}')
         = "a1b2c3d4e5f6..."
```

### 4.7 Manifest Signing Process

1. **Construct unsigned manifest**
2. **Canonicalize** (sorted keys, no whitespace)
3. **Hash the canonical form**: `message_hash = sha256(canonical_json)`
4. **Sign with Ed25519**: `sig = ed25519-sign(private-key, message-hash)`
5. **Encode signature**: `signature_ed25519 = base64url-encode(sig)`
6. **Add to manifest**

```racket
(define (sign-manifest manifest identity)
  (define unsigned (hash-remove manifest 'signature_ed25519))
  (define canonical (canonical-json unsigned))
  (define sig (sign-bytes (string->bytes/utf-8 canonical)))
  (hash-set manifest 'signature_ed25519 (base64-encode sig)))
```

### 4.8 Manifest Verification

```racket
(define (verify-manifest manifest)
  (define sig (base64-decode (hash-ref manifest 'signature_ed25519)))
  (define unsigned (hash-remove manifest 'signature_ed25519))
  (define canonical (canonical-json unsigned))
  (define pk (did->public-key (hash-ref manifest 'owner_did)))
  (ed25519-verify pk (string->bytes/utf-8 canonical) sig))
```

#### Trust Model

**Direct Trust (Phase 1-2)**
- User maintains list of trusted DIDs in `~/.agentd/trusted-dids.json`
- Only import manifests signed by trusted DIDs

**Web of Trust (Phase 3+)**
- Trusted DIDs can endorse other DIDs
- Endorsement = signed statement: "did:A trusts did:B for task-type X"
- Transitive trust with configurable depth

### 4.9 Integration with eval-store.rkt

#### Data Flow

```
evals.jsonl
    │
    ▼
┌─────────────────────┐
│ parse-evals         │ Read and parse eval entries
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ group-by-agent      │ Group by agent config hash
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ compute-metrics     │ Calculate success rates, counts
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ filter-elites       │ Apply qualification criteria
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│ generate-manifests  │ Create and sign manifests
└─────────────────────┘
    │
    ▼
~/.agentd/elite/*.json
```

#### New elite-registry.rkt Functions

```racket
;; Main entry point - regenerate all elite manifests
(define (update-elite-registry!)
  (define evals (load-all-evals))
  (define grouped (group-evals-by-agent evals))
  (define elites (filter elite-qualified? (hash-values grouped)))
  (for ([elite elites])
    (define manifest (generate-manifest elite))
    (define signed (sign-manifest manifest (current-identity)))
    (save-manifest! signed)))

;; Triggered automatically after N evals or manually via CLI
(define (maybe-update-registry!)
  (when (> (pending-eval-count) 100)
    (update-elite-registry!)))
```

---

## 5. Data Synchronization

### 5.1 Git-Native Approach (Phase 1-2)

Standard repository layout for `chrysalis-elites`:

```
chrysalis-elites/
  agents/
    <agent-id>/
      manifest.json
      prompt.md          # Optional, opt-in
      demos.json         # Optional, opt-in  
      profile.json
  INDEX.json             # Global index
  IDENTITY.json          # Repo owner DID (signed)
  README.md
```

### 5.2 Radicle P2P Layer (Expanded)

#### 5.2.1 Why Radicle for Chrysalis Forge

| Requirement | Radicle Capability |
|-------------|-------------------|
| DID-based identity | Ed25519 keypairs, did:key format |
| Git-native workflow | Built on Git, no new data model |
| P2P without servers | Gossip protocol, no central point |
| Social artifacts | COBs for issues, patches, discussions |
| Offline-first | Local-first, sync when connected |
| Jujutsu support | [Radicle 1.5+ supports jj](https://radicle.xyz/2025/08/14/jujutsu-with-radicle.html) |

Citation: [Radicle Protocol Guide](https://radicle.xyz/guides/protocol)

#### 5.2.2 Radicle Architecture Overview

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

#### 5.2.3 Key Radicle Concepts

**Repository ID (RID)**
- Unique identifier derived from identity document
- Format: `rad:z3gqcJUoA1n9HaHKufZs5FCSGazv5`

**Node ID (NID)**
- Ed25519 public key, Base58 encoded
- Same key we use for did:key

**Collaborative Objects (COBs)**
- Social artifacts stored as Git objects
- Types: Issues, Patches, Identities
- Cryptographically signed by author
- CRDT-like: merge by unioning commit graphs

#### 5.2.4 CLI Integration Examples

```bash
# Initialize Chrysalis Identity with Radicle
rad auth --alias "chrysalis-node"
cf-identity --import-radicle ~/.radicle/keys/radicle.key

# Create Elite Repository
mkdir chrysalis-elites && cd chrysalis-elites
git init
rad init --name "chrysalis-elites" --description "Elite agent configurations"

# Publish Elite Agents
cf-generate-elites
cf-export-elites --to ./agents/
git add agents/
git commit -m "Publish elites from did:key:z6Mk..."
git push rad
rad sync

# Discover Elite Agents
rad clone rad:z4V1sjrXqjvFdnCUbxPFqd5p4DtH5
cf-discover-elites --repo ./chrysalis-elites
cf-import-elite --agent-id a1b2c3...
```

#### 5.2.5 Radicle HTTPD API Integration

```bash
radicle-httpd --listen 127.0.0.1:8080
```

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/projects` | GET | List all projects |
| `/api/v1/projects/:rid` | GET | Get project info |
| `/api/v1/projects/:rid/tree/:commit/:path` | GET | Get file content |
| `/api/v1/projects/:rid/commits` | GET | List commits |

```racket
(require net/http-easy json)

(define (list-radicle-projects)
  (define resp (get "http://127.0.0.1:8080/api/v1/projects"))
  (response-json resp))

(define (get-elite-manifest rid agent-id)
  (define path (format "agents/~a/manifest.json" agent-id))
  (define url (format "http://127.0.0.1:8080/api/v1/projects/~a/tree/HEAD/~a" rid path))
  (response-json (get url)))
```

#### 5.2.6 Chrysalis-Radicle Tool Mapping

| Chrysalis Tool | Radicle Equivalent | Notes |
|----------------|-------------------|-------|
| `git_status` | `rad inspect` | Project status |
| `git_commit` | `git commit` + `rad sync` | Commit and propagate |
| `git_push` | `git push rad` | Push to rad remote |
| `export_elite_agents` | N/A (new) | Export + commit + push |
| `import_elite_agent` | `rad clone` + parse | Clone and import |
| `discover_elites` | `rad ls` + filter | List and filter projects |

### 5.3 Alternative: Freenet Contracts (Phase 5)

For global "top 100 elites" state when scale demands:
- Small-world routing for efficient discovery
- WASM contracts for state validation
- Key-value store with cryptographic verification

Citation: [Freenet Tutorial](https://freenet.org/resources/manual/tutorial/)

**Decision**: Defer until Git/Radicle proves insufficient (>100s nodes, real-time needs).

---

## 6. Decentralized Compute Integration

### 6.1 Use Cases (Detailed)

#### 6.1.1 Finetuning Base Models
**Goal**: Customize foundation models on Chrysalis-specific task distributions

**Data sources**:
- Sanitized traces from evals.jsonl (user opt-in)
- Synthetic data generated from elite agent demos
- Public coding datasets (e.g., The Stack)

#### 6.1.2 Reinforcement Learning from Feedback
**Goal**: Train policies via GEPA-style iterative improvement

**RL Signal sources**:
- Binary success/failure from eval-store
- User corrections (implicit negative signal)
- GEPA feedback loops
- Automated test suite results

**Approach**: 
- GRPO (Group Relative Policy Optimization) as used by DeepSeek
- Async RL as demonstrated by Prime Intellect INTELLECT-2

#### 6.1.3 Distributed Evaluation
**Goal**: Evaluate agent configs across diverse environments (OS, project types, model backends)

### 6.2 Platform Deep Dives

#### 6.2.1 Akash Network

**Proven Capabilities** (from Akash blog):
- Foundation model training with 32x A100 80GB GPUs
- 1024 vCPUs, 4096GB RAM, 32TB NVMe storage
- ~60-80% cheaper than AWS/GCP for GPU workloads

**SDL Example**:
```yaml
version: "2.0"
services:
  trainer:
    image: chrysalis/trainer:latest
    env:
      - JOB_ID=${JOB_ID}
      - MODEL=llama3-8b
profiles:
  compute:
    trainer:
      resources:
        cpu: { units: 8 }
        memory: { size: 64Gi }
        gpu:
          units: 1
          attributes:
            vendor: { nvidia: [{ model: a100 }] }
        storage: { size: 100Gi }
```

Citation: [Akash Foundation Model Training](https://akash.network/blog/foundation-ai-model-training-on-akash/)

#### 6.2.2 Tashi Network

**Key Innovation**: Leaderless DAG consensus with <50ms finality

**Best For Chrysalis**:
- Real-time RL update coordination
- Multi-agent session synchronization
- Low-latency model update propagation

Citation: [Tashi Network](https://tashi.network/)

#### 6.2.3 Prime Intellect

**INTELLECT-2 Breakthrough**:
- First 32B parameter model trained via distributed RL
- Async RL with 4-step delay tolerance
- TOPLOC verification for trustless inference

**Key Components**:
1. **prime-rl**: Open-source async distributed RL library
2. **Shardcast**: HTTP-based tree-topology model distribution
3. **TOPLOC**: Efficient verifiable inference

Citation: [INTELLECT-2](https://www.primeintellect.ai/blog/intellect-2)

#### 6.2.4 P2PFL (Peer-to-Peer Federated Learning)

**How It Works**:
1. Each node trains on local data
2. Model updates shared via gossip
3. Aggregation happens peer-to-peer
4. No node sees another's raw data

Citation: [P2PFL GitHub](https://github.com/p2pfl/p2pfl)

### 6.3 Orchestrator Architecture

#### Design Principles
1. **Backend agnostic**: Easy to add new compute providers
2. **Job-centric**: Everything is a job with defined lifecycle
3. **Verifiable**: All results cryptographically signed
4. **Fault-tolerant**: Jobs can be retried on different backends

```
┌─────────────────────────────────────────────────────────────┐
│                     Chrysalis Forge                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ cf-submit-  │  │ cf-check-   │  │ cf-fetch-   │         │
│  │ training    │  │ training    │  │ artifacts   │         │
└─────────┼────────────────┼────────────────┼─────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────┐
│                    Orchestrator (HTTP API)                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Job Queue   │  │ Backend     │  │ Artifact    │         │
│  │             │  │ Adapters    │  │ Manager     │         │
└──────────────────────────┼──────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    ┌──────────┐     ┌──────────┐     ┌──────────┐
    │  Akash   │     │  Tashi   │     │  Prime   │
    │  Adapter │     │  Adapter │     │ Intellect│
    └──────────┘     └──────────┘     └──────────┘
```

#### Job Lifecycle

```
CREATED → QUEUED → SUBMITTED → RUNNING → COMPLETED
                                    ↓
                               [on failure]
                                    ↓
                                 FAILED → RETRY → SUBMITTED
```

#### Orchestrator API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/jobs` | POST | Submit new training job |
| `/jobs/:id` | GET | Get job status |
| `/jobs/:id/logs` | GET | Stream job logs |
| `/jobs/:id/artifacts` | GET | List artifacts |
| `/jobs/:id/cancel` | POST | Cancel running job |
| `/backends` | GET | List available backends |

### 6.4 Training Job Spec (Full Schema)

```json
{
  "$schema": "https://chrysalis-forge.dev/schemas/training-job-v1.json",
  "job_id": "uuid-v4",
  "owner_did": "did:key:z6Mk...",
  "created_at": 1712345678,
  "job_type": "finetune | rl | eval",
  "base_model": {
    "name": "llama3-8b-instruct",
    "source": "huggingface",
    "revision": "main"
  },
  "objective": {
    "optimize_for": "success_rate",
    "task_types": ["file-edit", "vcs"],
    "target_metric": 0.90,
    "max_steps": 10000
  },
  "data": {
    "source": "git",
    "repo": "git@github.com:user/chrysalis-traces.git",
    "path": "datasets/file-edit/",
    "format": "jsonl"
  },
  "hyperparameters": {
    "learning_rate": 1e-5,
    "batch_size": 4,
    "gradient_accumulation_steps": 8
  },
  "resources": {
    "gpus": 1,
    "gpu_type": "a100",
    "gpu_mem_gb": 80,
    "max_hours": 8
  },
  "backend": {
    "provider": "akash",
    "max_cost_usd": 50.00
  },
  "artifacts": {
    "output_repo": "git@github.com:user/chrysalis-models.git",
    "save_checkpoints": true
  },
  "notifications": {
    "on_complete": "nostr:npub1..."
  },
  "signature_ed25519": "base64url..."
}
```

### 6.5 Result Integration Pipeline

```
1. Orchestrator commits artifacts to output_repo
   └── models/job-<id>/
       ├── model.safetensors
       ├── config.json
       └── metrics.json

2. Chrysalis node pulls output_repo
   └── cf-fetch-artifacts --job-id <id>

3. Run standardized eval suite
   └── cf-eval --model ./models/job-<id>/ --tasks all
   └── Results written to evals.jsonl

4. If metrics beat existing agents:
   └── update-elite-registry! generates new manifest
   └── New agent marked as "finetuned derivative"

5. Optionally auto-publish
   └── cf-export-elites --auto-publish
```

---

## 7. Implementation Roadmap

### Phase 0: Baseline (S: <1 day)
- [ ] Stabilize `evals.jsonl` schema
- [ ] Document "agent config" definition (signature + module + prompt + demos + profile)
- [ ] Audit existing eval-store.rkt

### Phase 1: Local Identity & Elite Extraction (S-M: 1-2 days)
- [ ] Implement `src/core/identity.rkt`
  - `load-or-create-identity`
  - `sign!` / `verify!`
- [ ] Implement `src/stores/elite-registry.rkt`
  - `generate-agent-manifests`
  - `update-elite-registry!`
- [ ] CLI: `cf-generate-elites`

### Phase 2: Git-Native Sharing (M: 2-3 days)
- [ ] Define `chrysalis-elites` repo schema
- [ ] Implement `export_elite_agents` tool
- [ ] Implement `import_elite_agent` tool
- [ ] Config: known elite repos list
- [ ] CLI: `cf-discover-elites`
- [ ] DID-sign all manifests

### Phase 3: Radicle P2P (M: 2-3 days)
- [ ] Bridge Ed25519 keypair to Radicle identity
- [ ] Add `--rad` flag to export/import tools
- [ ] Document Radicle URN sharing
- [ ] Optional: Nostr announcement events

### Phase 4: Compute Integration (M-L: 1-2 weeks)
- [ ] Define `training-job.json` schema
- [ ] Build thin orchestrator (Python/Go)
- [ ] Akash backend adapter
- [ ] Result → eval → elite pipeline
- [ ] CLI: `cf-submit-training`

### Phase 5: Advanced P2P (L: 2+ weeks, only if needed)
- [ ] Evaluate DWN-like mesh storage
- [ ] Evaluate Freenet contracts for global state
- [ ] P2PFL integration for federated learning
- [ ] Tashi/Prime Intellect for real-time RL

---

## 8. Decision Log

| Decision | Chosen | Alternatives Considered | Rationale |
|----------|--------|------------------------|-----------|
| Identity | `did:key` Ed25519 | Blockchain wallet, Ethereum DID | No infra, Radicle/Nostr compatible |
| Sync Phase 1-2 | Git repos | IPFS, DWN | Simple, existing tooling |
| Sync Phase 3 | Radicle | Nostr-only, Freenet | Git-native, same keypair |
| Compute | Thin orchestrator | Embedded Racket | Flexibility, separation of concerns |
| Privacy | Metrics-only sharing | Full trace sharing | User data protection |

---

## 9. Risks and Mitigations

### 9.1 Security Risks

| Risk | Mitigation |
|------|------------|
| Sybil attacks (spam agents) | Minimum task threshold, volume+recency ranking |
| Key compromise | Backup guidance, key rotation with signed statement |
| Malicious manifests | DID signature verification, trust sets |

### 9.2 Privacy Risks

| Risk | Mitigation |
|------|------------|
| Prompt leakage | Only fingerprints shared, never raw content |
| User data exposure | Aggregate metrics only, no trace content |
| Inference attacks | Configurable metric granularity |

### 9.3 Operational Risks

| Risk | Mitigation |
|------|------------|
| Key loss | Encrypted backup, recovery documentation |
| Repo unavailability | Multiple known repos, local cache |
| Compute backend changes | Thin orchestrator abstraction |

---

## 10. When to Advance to Complex P2P

Move beyond Git/Radicle + did:key only when:

1. **Scale** - >100s nodes where pull/push is too slow
2. **Real-time** - Need seconds-level propagation of new elites
3. **Privacy** - Cross-org training without raw data sharing
4. **Coordination** - Complex multi-backend scheduling needs reputation system

Until then, the simple architecture provides:
- ✅ DID-based identity
- ✅ Signed manifests
- ✅ Git-native sharing
- ✅ Radicle P2P discovery
- ✅ Compute orchestration

---

## 11. Future Considerations

### 11.1 Potential Enhancements

- **Endorsements**: Other DIDs can co-sign manifests to attest performance
- **Reputation scores**: Network-wide agent rankings
- **Verifiable eval suites**: Cryptographic proofs of evaluation runs
- **Cross-agent composition**: Combine elite agents for complex tasks

### 11.2 Emerging Technologies to Watch

- **DIF DWN spec evolution** - May become viable alternative to Radicle
- **Nostr NIP extensions** - Could add structured data support
- **Freenet production network** - Currently in development
- **Prime Intellect protocol** - Could enable trustless RL coordination

---

## Appendix A: Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     IDENTITY LAYER                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ did:key     │  │ identity.   │  │ sign!/      │             │
│  │ z6Mkw...    │◄─┤ json        │──┤ verify!     │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     LOCAL AGENT EVOLUTION                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ eval-store  │  │ elite-      │  │ optimizer-  │             │
│  │ .rkt        │──┤ registry.rkt│◄─┤ gepa.rkt    │             │
│  │ evals.jsonl │  │ elite/*.json│  │             │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     GIT-NATIVE SYNC                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Git/        │  │ Radicle P2P │  │ chrysalis-  │             │
│  │ Jujutsu     │──┤ (Phase 3)   │──┤ elites repo │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     DECENTRALIZED COMPUTE (Phase 4)              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ training-   │  │ Thin        │  │ Akash/Tashi │             │
│  │ job.json    │──┤ Orchestrator│──┤ /Prime Int. │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     ADVANCED P2P (Phase 5, if needed)            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Nostr       │  │ Freenet     │  │ P2PFL       │             │
│  │ (announce)  │  │ (contracts) │  │ (fed. learn)│             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| DID | Decentralized Identifier - W3C standard for self-sovereign identity |
| did:key | DID method where the identifier is derived directly from a public key |
| COB | Collaborative Object - Radicle's social artifacts (issues, patches) stored in Git |
| DWN | Decentralized Web Node - mesh-like datastore from DIF spec |
| GEPA | General Evolvable Prompting Architecture - Chrysalis Forge's prompt optimizer |
| Elite Agent | Agent configuration that exceeds performance thresholds |
| Manifest | Signed JSON document describing an agent's config and metrics |
| DePIN | Decentralized Physical Infrastructure Network |
| DAG | Directed Acyclic Graph - used by Tashi for consensus |
| TOPLOC | Prime Intellect's verification for distributed inference |
| P2PFL | Peer-to-Peer Federated Learning |
| SDL | Stack Definition Language - Akash deployment format |
| RID | Repository ID - Radicle's unique project identifier |
| NID | Node ID - Radicle's Ed25519 public key identifier |
| GRPO | Group Relative Policy Optimization - RL algorithm used by DeepSeek |

---

*Document generated: January 2026*  
*Chrysalis Forge: https://github.com/Diogenesoftoronto/chrysalis-forge*  
*Amp Thread: https://ampcode.com/threads/T-019bb071-663e-710f-be42-2c99f56ac8bc*
