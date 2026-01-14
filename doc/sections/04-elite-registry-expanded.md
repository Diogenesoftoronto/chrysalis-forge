# Elite Registry Expanded Details

## 4.5 Elite Selection Algorithm

### Qualification Criteria

An agent qualifies as "elite" when:

- `success_rate >= 0.80` (80% success threshold)
- `total_tasks >= 50` (minimum sample size for statistical significance)
- `recent_tasks >= 10` in last 7 days (still actively used)
- No critical failures in last 24 hours

### Ranking Formula

```
score = (success_rate * 0.6) + (recency_weight * 0.2) + (volume_weight * 0.2)

where:
  recency_weight = tasks_last_7d / total_tasks  (capped at 1.0)
  volume_weight = min(1.0, log10(total_tasks) / 3)  (log scale, caps at 1000 tasks)
```

### Confidence Adjustment

For low sample sizes, apply Wilson score interval:

```
adjusted_rate = (successes + z²/2) / (n + z²)
where z = 1.96 for 95% confidence
```

### Task-Type Specific Rankings

Maintain separate elite lists per task type:

- `elite-file-edit.json` - Best at file editing
- `elite-search.json` - Best at codebase search
- `elite-vcs.json` - Best at git/jj operations
- `elite-general.json` - Best overall

### Pseudocode

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

## 4.6 Agent ID Generation

### Fields Included in Hash

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

### Canonical JSON Serialization

1. Sort all object keys alphabetically (recursive)
2. Remove all whitespace
3. Use consistent number formatting (no trailing zeros)
4. UTF-8 encode

### Example

Input config → Canonical JSON → SHA-256 → agent_id

```
agent_id = sha256('{"demos_hash":"sha256:def456","module":"ChainOfThought",...}')
         = "a1b2c3d4e5f6..."
```

## 4.7 Manifest Signing Process

### Step-by-Step

1. **Construct unsigned manifest**

   ```json
   {
     "agent_id": "a1b2c3...",
     "owner_did": "did:key:z6Mk...",
     "metrics": {...},
     ...
   }
   ```

2. **Canonicalize** (sorted keys, no whitespace)

   ```
   {"agent_id":"a1b2c3...","metrics":{...},"owner_did":"did:key:z6Mk..."}
   ```

3. **Hash the canonical form**

   ```
   message_hash = sha256(canonical_json)
   ```

4. **Sign with Ed25519**

   ```racket
   (define sig (ed25519-sign private-key message-hash))
   ```

5. **Encode signature**

   ```
   signature_ed25519 = base64url-encode(sig)
   ```

6. **Add to manifest**

   ```json
   {
     ...,
     "signature_ed25519": "base64url..."
   }
   ```

### Racket Implementation

```racket
(define (sign-manifest manifest identity)
  (define unsigned (hash-remove manifest 'signature_ed25519))
  (define canonical (canonical-json unsigned))
  (define sig (sign-bytes (string->bytes/utf-8 canonical)))
  (hash-set manifest 'signature_ed25519 (base64-encode sig)))
```

## 4.8 Manifest Verification

### Verification Steps

1. **Extract signature**

   ```racket
   (define sig (base64-decode (hash-ref manifest 'signature_ed25519)))
   ```

2. **Reconstruct unsigned manifest**

   ```racket
   (define unsigned (hash-remove manifest 'signature_ed25519))
   ```

3. **Canonicalize**

   ```racket
   (define canonical (canonical-json unsigned))
   ```

4. **Extract public key from owner_did**

   ```racket
   (define pk (did->public-key (hash-ref manifest 'owner_did)))
   ```

5. **Verify signature**

   ```racket
   (ed25519-verify pk (string->bytes/utf-8 canonical) sig)
   ```

### Trust Model

**Direct Trust (Phase 1-2)**

- User maintains list of trusted DIDs in `~/.chrysalis/trusted-dids.json`
- Only import manifests signed by trusted DIDs

**Web of Trust (Phase 3+)**

- Trusted DIDs can endorse other DIDs
- Endorsement = signed statement: "did:A trusts did:B for task-type X"
- Transitive trust with configurable depth

**Reputation (Future)**

- Track successful imports per DID
- Weight trust by historical accuracy

## 4.9 Integration with eval-store.rkt

### Data Flow

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
~/.chrysalis/elite/*.json
```

### Existing eval-store.rkt Functions Used

- `(get-profile-stats)` - Retrieve aggregated stats per profile
- `(log-eval!)` - Source of raw eval data
- `(suggest-profile task-type)` - Already ranks profiles

### New elite-registry.rkt Functions

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
