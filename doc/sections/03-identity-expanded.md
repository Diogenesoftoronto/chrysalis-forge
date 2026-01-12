## 3.4 Identity Implementation (Expanded)

### 3.4.1 File Structure

```
~/.agentd/
  identity.json          # Node DID + keypair
  identity.json.backup   # Encrypted backup
  elite/
    <agent-id>.json      # Signed agent manifests
```

### 3.4.2 identity.json Format

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

### 3.4.3 DID Construction from Ed25519 Key

The `did:key` method encodes the public key directly in the identifier:

1. **Generate Ed25519 keypair** — produces 32-byte public key
2. **Prepend multicodec prefix** for ed25519-pub: `0xed01`
3. **Encode with multibase** using base58-btc (prefix `z`)
4. **Prepend "did:key:"** → `did:key:z6Mk...`

#### Byte-level Construction

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

### 3.4.4 Racket Implementation Skeleton

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

### 3.4.5 Interoperability

#### With Radicle

Radicle uses the same Ed25519 keys, enabling direct interop:

- **Import Chrysalis key to Radicle:**
  ```bash
  rad auth --alias "chrysalis" --key ~/.agentd/identity.json
  ```

- **Export Radicle key to Chrysalis format:**
  ```bash
  cf-identity --import-radicle ~/.radicle/keys/radicle.key
  ```

- **Radicle Node ID (NID)** = Base58-encoded public key
- **Radicle DID** = `did:key:z6Mk...` (same format we use)

This means a Chrysalis agent can sign commits and patches that Radicle nodes will recognize.

#### With Nostr

Nostr uses Ed25519 but with bech32 encoding:

| Format | Prefix | Encoding |
|--------|--------|----------|
| npub | `npub1` | bech32 of public key |
| nsec | `nsec1` | bech32 of private key |
| did:key | `did:key:z6Mk` | multibase of multicodec-prefixed key |

Conversion functions:

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

### 3.4.6 Key Backup and Recovery

#### Backup Procedure

1. **Encrypt identity.json with passphrase:**
   ```bash
   age -p ~/.agentd/identity.json > ~/.agentd/identity.json.backup
   # or
   gpg -c ~/.agentd/identity.json
   ```

2. **Store in secure location** (password manager, offline storage)

3. **Test recovery before relying on it**

#### Recovery

1. **Decrypt backup:**
   ```bash
   age -d ~/.agentd/identity.json.backup > ~/.agentd/identity.json
   ```

2. **Verify integrity:**
   ```bash
   cf-identity --verify
   ```

#### Key Rotation (When Compromised)

1. **Generate new identity:**
   ```bash
   cf-identity --rotate
   ```

2. **Sign rotation statement with old key:**
   ```json
   {
     "type": "key-rotation",
     "from": "did:key:z6MkOLD...",
     "to": "did:key:z6MkNEW...",
     "timestamp": 1704067200,
     "signature": "<old-key-signature>"
   }
   ```

3. **Publish rotation to known repos:**
   ```bash
   cf-identity --publish-rotation
   ```

4. Old manifests remain valid but are marked as from a rotated identity

### 3.4.7 Example DID Document

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

The DID document confirms that the key can be used for:
- **authentication** — proving control of the DID
- **assertionMethod** — signing claims and credentials
