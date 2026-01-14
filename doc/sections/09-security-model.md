## 9. Security Model

This section defines the comprehensive security model for Chrysalis Forge's decentralized architecture, covering threat analysis, cryptographic operations, trust relationships, and privacy guarantees.

---

### 9.1 Threat Model

#### 9.1.1 Actors

| Actor | Description | Capabilities |
|-------|-------------|--------------|
| **Honest Node** | Legitimate participant following protocol | Full protocol access, trusted operations |
| **Curious Node** | Follows protocol but attempts passive information gathering | Network observation, metadata analysis |
| **Malicious Node** | Actively attempts to subvert the system | Crafted messages, fake manifests, DoS attempts |
| **External Attacker** | No legitimate network access | Network interception, key theft attempts, phishing |

#### 9.1.2 Protected Assets

| Asset | Sensitivity | Location |
|-------|-------------|----------|
| **Private Keys** | Critical | `~/.chrysalis/identity.json` |
| **Agent Configs** | High | `~/.chrysalis/elite/*.json`, `.chrysalis/` project dirs |
| **Eval Data** | Medium-High | `~/.chrysalis/evals.jsonl`, `traces.jsonl` |
| **Model Weights** | Variable | Local cache, external providers |
| **Trust Lists** | High | `~/.chrysalis/trusted-dids.json` |
| **Audit Logs** | Medium | `~/.chrysalis/audit.jsonl` |

#### 9.1.3 Attack Vectors

| Vector | Description | Target Asset | Severity |
|--------|-------------|--------------|----------|
| **Key Theft** | Extracting private key from storage or memory | Private Keys | Critical |
| **Manifest Spoofing** | Publishing fake manifests with forged signatures | Agent Configs | High |
| **Sybil Attack** | Creating many identities to manipulate trust/reputation | Trust Model | High |
| **Data Poisoning** | Injecting malicious eval data to corrupt learning | Eval Data | Medium |
| **MITM** | Intercepting unencrypted transport | All network data | High |
| **Replay Attack** | Re-submitting valid signed messages | Agent Configs | Medium |
| **Metadata Leakage** | Inferring private info from access patterns | Privacy | Medium |

---

### 9.2 Key Management

#### 9.2.1 Key Generation

Keys are generated using Ed25519 via the `crypto/libcrypto` Racket library:

```racket
(require crypto crypto/libcrypto)

(define (generate-keypair)
  (generate-private-key 'eddsa '((curve ed25519))))
```

**Properties:**
- 256-bit security level
- Deterministic signatures (no random nonce required)
- Fast signing and verification
- Compact keys (32 bytes public, 64 bytes private)

#### 9.2.2 Key Storage

**Location:** `~/.chrysalis/identity.json`

**Permissions:** `0600` (owner read/write only)

```bash
chmod 600 ~/.chrysalis/identity.json
```

**Format:**
```json
{
  "did": "did:key:z6Mk...",
  "publicKeyBase58": "...",
  "secretKeyBase58": "...",
  "publicKeyMultibase": "z6Mk...",
  "createdAt": 1704067200,
  "alias": "my-node"
}
```

**Security measures:**
- Never log or display `secretKeyBase58`
- Clear from memory after use when possible
- Validate permissions on load

#### 9.2.3 Key Backup

**Recommended approach using age encryption:**

```bash
# Backup with passphrase
age -p ~/.chrysalis/identity.json > ~/.chrysalis/identity.json.age

# Backup with recipient public key
age -r age1... ~/.chrysalis/identity.json > ~/.chrysalis/identity.json.age
```

**Alternative with GPG:**

```bash
gpg --symmetric --cipher-algo AES256 ~/.chrysalis/identity.json
```

**Storage recommendations:**
1. Password manager (1Password, Bitwarden)
2. Encrypted USB drive (offline)
3. Paper backup of seed (if deterministic derivation implemented)
4. **Never** store unencrypted backups in cloud storage

#### 9.2.4 Key Rotation

**Trigger conditions:**
- Suspected compromise
- Scheduled rotation (recommended: annually)
- Identity migration

**Rotation procedure:**

1. **Generate new keypair:**
   ```bash
   cf-identity --rotate
   ```

2. **Create signed rotation statement:**
   ```json
   {
     "type": "key-rotation",
     "version": 1,
     "from": "did:key:z6MkOLD...",
     "to": "did:key:z6MkNEW...",
     "timestamp": 1704067200,
     "reason": "scheduled",
     "signature": "<signature-by-old-key>"
   }
   ```

3. **Propagate to known repos:**
   ```bash
   cf-identity --publish-rotation
   ```

4. **Update trusted-dids on peers** (out-of-band notification recommended)

#### 9.2.5 Compromise Response

**Immediate actions:**
1. Generate new identity: `cf-identity --rotate --emergency`
2. Create revocation statement signed by old key (if still available)
3. Broadcast revocation to all known peers
4. Notify trusted contacts out-of-band
5. Audit recent activity in `~/.chrysalis/audit.jsonl`

**Revocation statement:**
```json
{
  "type": "key-revocation",
  "did": "did:key:z6MkCOMPROMISED...",
  "timestamp": 1704067200,
  "reason": "compromise",
  "successor": "did:key:z6MkNEW...",
  "signature": "<signature-by-compromised-key-if-available>"
}
```

---

### 9.3 Signature Verification

#### 9.3.1 Canonical JSON Construction

To ensure deterministic serialization for signature verification:

1. **Sort object keys** lexicographically (Unicode code point order)
2. **No whitespace** between tokens
3. **UTF-8 encoding** for all strings
4. **No trailing commas**
5. **Numbers** as JSON numbers (no leading zeros, no +)

```racket
(require json)

(define (canonical-json obj)
  (define (sort-hash h)
    (for/hasheq ([(k v) (in-hash h)])
      (values k (canonicalize v))))
  (define (canonicalize v)
    (cond
      [(hash? v) (sort-hash v)]
      [(list? v) (map canonicalize v)]
      [else v]))
  (jsexpr->string (canonicalize obj) #:indent #f))
```

#### 9.3.2 Signature Creation

**Hash-then-sign approach** (for large manifests):

```racket
(require crypto crypto/libcrypto file/sha1)

(define (sign-manifest manifest private-key)
  (define canonical (canonical-json manifest))
  (define hash (sha256 (string->bytes/utf-8 canonical)))
  (define signature (pk-sign private-key hash))
  (bytes->hex-string signature))
```

**Why hash-then-sign:**
- Constant-time signing regardless of manifest size
- Prevents oracle attacks on message content
- Standard practice for Ed25519 with large messages

#### 9.3.3 Signature Verification

```racket
(define (verify-manifest manifest signature-hex signer-did)
  (define canonical (canonical-json (hash-remove manifest 'signature)))
  (define hash (sha256 (string->bytes/utf-8 canonical)))
  (define signature (hex-string->bytes signature-hex))
  (define public-key (did->public-key signer-did))
  (pk-verify public-key hash signature))
```

**Verification checklist:**
1. Extract signer DID from manifest
2. Remove signature field before hashing
3. Reconstruct canonical JSON
4. Verify signature against hash
5. Check signer is in trusted set

---

### 9.4 Trust Model

#### 9.4.1 Phase 1-2: Direct Trust

**Explicit trust list:** `~/.chrysalis/trusted-dids.json`

```json
{
  "version": 1,
  "trusted": [
    {
      "did": "did:key:z6MkTRUSTED...",
      "alias": "alice",
      "addedAt": 1704067200,
      "scopes": ["*"],
      "notes": "Verified in person"
    }
  ]
}
```

**Trust-on-first-use (TOFU):**

```
$ cf-agent import rad:z3abc...
⚠ Unknown signer: did:key:z6MkNEW...
  Fingerprint: z6Mk-NEWX-YYYY-ZZZZ
  
  Trust this identity? [y/N/v(erify)]
```

**Manual verification:**
- Compare fingerprints out-of-band (video call, in person)
- Check signer's published identity on known platforms
- Verify against published key in personal website/.well-known

#### 9.4.2 Phase 3+: Web of Trust

**Endorsement schema:**

```json
{
  "type": "endorsement",
  "version": 1,
  "endorser": "did:key:z6MkALICE...",
  "endorsed": "did:key:z6MkBOB...",
  "scopes": ["file-edit", "vcs", "eval-share"],
  "expires": 1735689600,
  "created": 1704067200,
  "notes": "Collaborated on chrysalis-forge",
  "signature": "<endorser-signature>"
}
```

**Transitive trust:**

```
Alice (trusted, depth 0)
  └─ endorses → Bob (depth 1)
       └─ endorses → Charlie (depth 2)
            └─ endorses → Dave (depth 3, UNTRUSTED if max_depth=2)
```

**Configuration:**
```toml
# chrysalis.toml
[trust]
max_depth = 2
require_scope_match = true
endorsement_ttl_days = 365
```

**Scope definitions:**

| Scope | Meaning |
|-------|---------|
| `*` | Full trust for all operations |
| `file-edit` | Trust for file modification agents |
| `vcs` | Trust for version control operations |
| `eval-share` | Trust for shared evaluation data |
| `compute` | Trust for compute task delegation |

#### 9.4.3 Future: Reputation System

**Metrics tracked per DID:**
- Import success rate (manifests that worked)
- Endorsement accuracy (endorsed DIDs that remained trustworthy)
- Activity recency (last seen timestamp)
- Community endorsement count

**Trust scoring:**
```
trust_score = base_trust 
            × success_rate^2 
            × endorsement_weight 
            × recency_decay(days_since_active)
```

**Reputation decay:**
- DIDs inactive >180 days: trust score halved
- DIDs inactive >365 days: require re-verification

---

### 9.5 Privacy Protections

#### 9.5.1 Data Sharing Policy

| Data Type | Shared? | Granularity | Notes |
|-----------|---------|-------------|-------|
| Aggregate eval metrics | Optional | Configurable | Success rates, latency distributions |
| Config fingerprints | Yes | Hash only | For deduplication |
| Raw prompts | **Never** | N/A | Contains user data |
| Traces | **Never** | N/A | Contains execution details |
| User data | **Never** | N/A | PII protection |
| Model responses | **Never** | N/A | May contain sensitive info |

#### 9.5.2 Configurable Metric Granularity

```toml
# chrysalis.toml
[privacy]
share_metrics = true
metric_granularity = "coarse"  # "none", "coarse", "fine"

[privacy.coarse_metrics]
# Binned success rates (e.g., "80-90%")
# Rounded latencies (nearest 100ms)
# Daily aggregates only
```

#### 9.5.3 Differential Privacy

For aggregate statistics shared with orchestrators:

```racket
(define (add-laplace-noise value epsilon sensitivity)
  (define scale (/ sensitivity epsilon))
  (+ value (sample-laplace 0 scale)))

(define (private-mean values epsilon)
  (define raw-mean (/ (apply + values) (length values)))
  (add-laplace-noise raw-mean epsilon 1.0))
```

**Default parameters:**
- ε (epsilon) = 1.0 for moderate privacy
- Sensitivity calibrated per metric type

---

### 9.6 Transport Security

#### 9.6.1 Radicle Protocol

**NoiseXK handshake** (Noise Protocol Framework):

| Property | Description |
|----------|-------------|
| **Forward secrecy** | Session keys deleted after use |
| **Mutual authentication** | Both peers prove identity |
| **Identity hiding** | Initiator identity encrypted |
| **Replay protection** | Nonces prevent replay |

**Cipher suite:** `Noise_XK_25519_ChaChaPoly_BLAKE2b`

```
Initiator                          Responder
    |                                   |
    |  → e, es                          |  (ephemeral key, DH)
    |                                   |
    |  ← e, ee                          |  (ephemeral key, DH)
    |                                   |
    |  → s, se                          |  (static key, DH)
    |                                   |
    |  ← encrypted messages →           |  (authenticated channel)
```

#### 9.6.2 Git over SSH

Standard SSH key-based authentication:

```bash
# Use Chrysalis key for Git operations
GIT_SSH_COMMAND="ssh -i ~/.chrysalis/ssh_key" git push
```

**Key derivation from Ed25519:**
```bash
cf-identity --export-ssh > ~/.chrysalis/ssh_key
```

#### 9.6.3 Orchestrator API

**HTTPS + DID-signed requests:**

```http
POST /api/v1/tasks HTTP/1.1
Host: orchestrator.example.com
Content-Type: application/json
X-DID: did:key:z6MkMYDID...
X-Signature: <base64-signature>
X-Timestamp: 1704067200

{"task": "..."}
```

**Signature covers:**
- HTTP method
- Request path
- Timestamp (within 5 minute window)
- Request body hash

---

### 9.7 Audit Trail

#### 9.7.1 Audit Log Format

**Location:** `~/.chrysalis/audit.jsonl`

```json
{"ts":1704067200,"event":"identity_created","did":"did:key:z6Mk..."}
{"ts":1704067201,"event":"manifest_signed","agent_id":"editor-v1","hash":"abc123"}
{"ts":1704067202,"event":"manifest_imported","from":"did:key:z6MkOTHER...","agent_id":"helper"}
{"ts":1704067203,"event":"trust_added","did":"did:key:z6MkTRUSTED...","method":"tofu"}
{"ts":1704067204,"event":"key_rotation","from":"did:key:z6MkOLD...","to":"did:key:z6MkNEW..."}
```

**Event types:**
- `identity_created`, `identity_loaded`
- `manifest_signed`, `manifest_imported`, `manifest_verified`
- `trust_added`, `trust_removed`, `endorsement_created`
- `key_rotation`, `key_revocation`
- `task_delegated`, `task_completed`
- `verification_failed`, `signature_invalid`

#### 9.7.2 Manifest Version History

All manifest changes tracked in Git:

```bash
git log --oneline -- .chrysalis/*.json
```

**Commit message format:**
```
[chrysalis] Update agent manifest: editor-v1

Signer: did:key:z6Mk...
Hash: abc123...
```

#### 9.7.3 Key Rotation Events

Published to known repos as signed announcements:

```
~/.chrysalis/rotations/
  1704067200-z6MkOLD-to-z6MkNEW.json
```

---

### 9.8 Security Properties by Phase

| Property | Phase 1 | Phase 2 | Phase 3 | Phase 4+ |
|----------|---------|---------|---------|----------|
| **Key Management** | Local Ed25519 | + Backup/rotation | + Hardware key support | + Threshold signatures |
| **Signature Verification** | Basic Ed25519 | + Canonical JSON | + Batch verification | + ZK proofs |
| **Trust Model** | Manual DID list | + TOFU | + Web of trust | + Reputation |
| **Privacy** | Local only | + Opt-in metrics | + Differential privacy | + MPC aggregation |
| **Transport** | Git SSH | + Radicle NoiseXK | + Tor support | + Mixnet |
| **Audit** | Local logs | + Git history | + Distributed audit | + Blockchain anchoring |

---

### 9.9 Threat-to-Mitigation Mapping

| Threat | Mitigation(s) | Phase |
|--------|---------------|-------|
| **Key Theft** | File permissions (0600), encryption at rest, hardware keys | 1, 3 |
| **Manifest Spoofing** | Ed25519 signatures, trust verification | 1 |
| **Sybil Attack** | Web of trust, reputation system, endorsement costs | 3, 4 |
| **Data Poisoning** | Signature verification, source tracking, outlier detection | 2, 3 |
| **MITM** | NoiseXK transport, SSH, HTTPS with DID auth | 1, 2 |
| **Replay Attack** | Timestamps in signed requests, nonces | 2 |
| **Metadata Leakage** | Coarse metrics, differential privacy, Tor | 2, 3 |
| **Key Compromise** | Rotation protocol, revocation broadcast | 1 |
| **Curious Node** | Minimal data sharing, encryption | 2 |
| **Malicious Orchestrator** | Local verification, audit logs, multi-orchestrator | 3, 4 |

---

### 9.10 Trust Level Definitions

| Level | Name | Requirements | Capabilities |
|-------|------|--------------|--------------|
| **0** | Untrusted | No verification | View public manifests only |
| **1** | TOFU | First-use acceptance | Import agents with confirmation |
| **2** | Verified | Out-of-band verification | Import agents, receive endorsements |
| **3** | Endorsed | Trusted by verified peer (depth 1) | All above + reduced prompts |
| **4** | Core | Multiple endorsements + history | All above + auto-import |
| **5** | Self | Local identity | Full capabilities |

**Trust inheritance:**

```
Level 5 (Self)
  │
  ├─ Direct endorsement → Level 4 (Core, if criteria met) or Level 3
  │
  └─ Transitive (depth 1) → Level 3 (Endorsed)
       │
       └─ Transitive (depth 2) → Level 2 (if max_depth allows)
            │
            └─ Beyond max_depth → Level 0 (Untrusted)
```

---

### 9.11 Implementation Checklist

**Phase 1 (MVP):**
- [ ] Ed25519 key generation and storage
- [ ] File permission enforcement
- [ ] Basic signature creation/verification
- [ ] Manual trusted-dids.json management
- [ ] Local audit logging

**Phase 2:**
- [ ] Canonical JSON serialization
- [ ] TOFU with fingerprint display
- [ ] Key rotation with signed statements
- [ ] Configurable metric sharing
- [ ] Timestamp validation for signed requests

**Phase 3:**
- [ ] Endorsement creation and verification
- [ ] Transitive trust calculation
- [ ] Differential privacy for metrics
- [ ] Web of trust visualization

**Phase 4+:**
- [ ] Reputation scoring
- [ ] Hardware key support (FIDO2/WebAuthn)
- [ ] Threshold signatures for high-value operations
- [ ] Decentralized audit anchoring
