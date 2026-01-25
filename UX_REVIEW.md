# Chrysalis Forge UX Review & Improvement Plan

## Executive Summary

Tested Chrysalis Forge - a Racket-based LLM agent framework with DSPy-style optimization and self-improving capabilities. While the architecture is sophisticated and feature-rich, the user experience has significant friction points that make it difficult to get started.

**Overall Assessment**: Ambitious architecture with impressive feature set, but critical onboarding failures and configuration complexity create substantial barriers to entry.

---

## What Works Well

### 1. Installation & Packaging
- Racket package installation is smooth: `raco pkg install --auto` works flawlessly
- Binary installed to PATH automatically (`/home/diogenes/.local/share/racket/9.0/bin/chrysalis`)
- Dependency management handled correctly

### 2. CLI Design
- Flag-based configuration is clean and discoverable (`--model`, `--priority`, `--perms`, etc.)
- Comprehensive help system with multiple modes of entry (`-h`, `--help`)
- Natural language priority selection is a clever UX touch

### 3. Feature Breadth
- 25+ built-in tools covering file ops, git, jj, web search, and self-evolution
- MAP-Elites optimization and GEPA prompt evolution are technically impressive
- Multiple execution modes: CLI tasks, interactive REPL, ACP server, HTTP service, GUI, client
- Security levels with tiered sandboxing
- Session/thread management with persistence

### 4. Documentation Ecosystem
- Rich documentation structure (THEORY.md, ARCHITECTURE.md, USAGE.md, API.md, etc.)
- VHS recordings demonstrating expected behavior (`.vhs/*.gif`)
- Configuration examples (`.env.example`, `chrysalis.example.toml`)

### 5. Code Organization
- Modular architecture with clear separation of concerns (`core/`, `tools/`, `stores/`, `llm/`, `gui/`)
- Compiled artifacts to improve startup time
- Proper error handling and logging infrastructure

---

## Critical Problems

### 1. Default Model Does Not Exist 🔴
**Issue**: System defaults to `gpt-5.2`, which is not a real model
**Impact**: Immediate failure on first run - cannot do anything without manual configuration
**Evidence**:
```
[CONFIG INFO] Using default model: gpt-5.2
API request failed (HTTP/1.1 404 Not Found): {"detail":"Not Found"}
```

**Root Cause**: `main.rkt:52-58` sets default model to "gpt-5.2", and `src/llm/default-models.json` lists it but this model doesn't exist on any API endpoint.

### 2. API Endpoint Configuration Broken 🔴
**Issue**: Environment configuration points to non-functional API endpoint
**Impact**: Even with correct model names, API requests fail
**Evidence**:
```
OPENAI_API_BASE=https://api.z.ai/api/coding/paas/v4
```
This endpoint returns 404 for all model requests.

**Root Cause**: `.env` file contains API endpoint that doesn't exist or requires different authentication.

### 3. Missing First-Run Wizard 🔴
**Issue**: No interactive setup or configuration wizard
**Impact**: Users must read docs, understand API keys, know model names, manually configure env
**User Experience**: Immediate friction - "I installed it, now what?"

### 4. Vague Error Messages 🟡
**Issue**: API errors are cryptic and unhelpful
**Evidence**:
```
API request failed (HTTP/1.1 404 Not Found): {"detail":"Not Found"}
```

**Better**: "Model 'gpt-5.2' not found on API endpoint 'https://api.z.ai/api/coding/paas/v4'. Try setting a valid model: `export MODEL=gpt-4o`"

### 5. Interactive Mode Terminal Issues 🟡
**Issue**: Interactive REPL has stty errors in non-TTY contexts
**Evidence**:
```
[USER]> stty: 'standard input': Inappropriate ioctl for device
stty: 'standard input': Inappropriate ioctl for device
```

**Impact**: Pipes and scripts fail, makes automated testing difficult

### 6. Environment Variable Validation Noise 🟡
**Issue**: Verbose output even for successful startup
**Evidence**: Every run shows:
```
[CONFIG WARNING] No CHRYSALIS_SECRET_KEY set. Using insecure default for development.
[CONFIG INFO] No AUTUMN_SECRET_KEY set. Billing features disabled.
```

**Impact**: Clutters output, makes simple tasks feel complex

### 7. Model Registry Not Integrated 🟡
**Issue**: Sophisticated model registry (`src/llm/default-models.json`) with capabilities, costs, tiers - but not used for validation or auto-discovery
**Impact**: System doesn't warn about invalid model choices despite knowing about supported models

### 8. Diagnostic/Linter Noise 🟡
**Issue**: LSP reports 100+ warnings/errors across codebase
**Examples**:
- Missing `#lang` lines in `.md` and `.toml` files
- Unused variables and requires
- Diagnostic noise makes real issues hard to find

---

## Secondary Issues

### 9. No Connection Testing
`verify-env!` validates API keys but doesn't check connectivity or model availability until actual request.

### 10. Config Commands Inconsistent
`/config list` shows different output format than documented in USAGE.md. Documented command `/models` doesn't exist.

### 11. State Directory Not Created
`.chrysalis/` doesn't exist initially - unclear where data lives until first run.

### 12. No Quickstart Examples
Docs have examples but no "copy-paste this to get started" sequence.

### 13. Session Persistence Unclear
Where are sessions stored? How to backup? Migration path unclear.

### 14. GUI Mode Status Unclear
`--gui` option exists but testing it requires working API - unclear if it's production-ready.

### 15. Missing "Try Without API" Mode
No way to test tool operations without LLM calls for debugging configuration.

---

## UX Improvement Plan

### Priority 1: Fix Critical Onboarding Failures (Week 1)

#### 1.1 Fix Default Model
**Change**: Default to a working model or auto-detect
```racket
;; main.rkt
(define (get-default-model)
  (or (getenv "MODEL")
      (getenv "CHRYSALIS_DEFAULT_MODEL")
      "gpt-4o-mini"))  ; Changed from "gpt-5.2"
```

**Also**: Remove/validate `gpt-5.2` from default-models.json

#### 1.2 Implement API Connection Test
**File**: `src/llm/openai-client.rkt`

**Add**: Validation that checks model exists on configured endpoint
```racket
(define (validate-model-and-endpoint! [key #f] [base #f] [model #f])
  (let-values ([(ok? msg) (check-model-availability key base model)])
    (unless ok?
      (printf "[ERROR] ~a\n" msg)
      (printf "[HELP] Valid models for ~a:\n" base)
      (printf "  - gpt-4o-mini\n")
      (printf "  - gpt-4o\n")
      (printf "[HELP] Set with: export MODEL=<model>\n")
      (error 'configuration "Invalid model or endpoint"))))
```

**Call**: In `main.rkt`, add to `verify-env!` chain

#### 1.3 Interactive Setup Wizard
**File**: New file `src/core/setup-wizard.rkt`

**Features**:
- First-run detection (no `.chrysalis/config.json`)
- Prompt for API key (with masking)
- Test connection immediately
- Auto-select working model or offer choices
- Save `.chrysalis/config.json`
- Print success message with next steps

**Integration**: Detect in `main.rkt:48` (after `load-dotenv!`)

```racket
(define (first-run-setup!)
  (unless (file-exists? ".chrysalis/config.json")
    (displayln "=== Chrysalis Forge Setup ===")
    (displayln "Let's get you configured...")
    (run-setup-wizard!)))
```

#### 1.4 Improve Error Messages
**File**: `src/llm/openai-responses-stream.rkt:98-103`

**Enhance**:
```racket
(define helpful-msg
  (cond
    [(string-contains? (string-downcase error-msg) "model")
     (format "~a\n\n[HELP] The model '~a' is not available on ~a.\n       Supported models: gpt-4o-mini, gpt-4o, gpt-4o-mini-2024-07-18\n       Fix with: export MODEL=gpt-4o-mini\n       Or use /config model <name> in interactive mode"
             error-msg req-model base)]
    [(equal? (string-trim status-str) "HTTP/1.1 401")
     (format "Authentication failed for API endpoint ~a.\n       Check that OPENAI_API_KEY is correct.\n       Current key prefix: ~a..."
             base (substring k 0 (min 8 (string-length k))))]
    [else error-msg]))
```

### Priority 2: Improve Configuration Experience (Week 2)

#### 2.1 Add Config Validation Command
**New**: `/config validate` command that checks:
- API key format and connectivity
- Model availability on endpoint
- Required directories writable
- Optional API keys (EXA, etc.)

**File**: `src/core/commands.rkt`

#### 2.2 Fix `/config list` and Add `/models`
**File**: `src/core/commands.rkt`

**Implementation**:
```rkt
(define (handle-config-list)
  (printf "Current Configuration:\n")
  (printf "  Model: ~a\n" (model-param))
  (printf "  Base URL: ~a\n" (base-url-param))
  (printf "  Vision Model: ~a\n" (vision-model-param))
  (printf "  Priority: ~a\n" (priority-param))
  (printf "  Security Level: ~a\n" (current-security-level))
  (printf "  Budget: $~a\n" (budget-param))
  (printf "  Timeout: ~a seconds\n" (timeout-param)))

(define (handle-models-list)
  (define models (load-model-registry))
  (printf "Available Models:\n")
  (for ([m models])
    (printf "  - ~a (~a) - ~a\n"
            (hash-ref m 'id)
            (hash-ref m 'cost_tier)
            (hash-ref m 'description))))
```

#### 2.3 Model Registry Integration
**File**: `src/llm/model-selector.rkt`

**Enhance**: Use default-models.json for:
- Auto-completion of model names
- Validation against endpoint
- Cost estimation before run
- Capability checking (tools, vision)

#### 2.4 Quiet Mode for Non-Interactive
**File**: `main.rkt`

**Change**: Only show config warnings in interactive mode
```racket
(define (show-config-warnings?)
  (interactive-param))

(when (show-config-warnings?)
  (unless env-api-key
    (displayln "[WARNING] OPENAI_API_KEY not found.")))
```

### Priority 3: Documentation & Examples (Week 2-3)

#### 3.1 Quickstart Guide
**Create**: `QUICKSTART.md` with 5-minute path to first working session

```bash
# 1. Install (already done)
# 2. Configure (interactive)
chrysalis --setup

# 3. Test
chrysalis "What files are in this directory?"

# 4. Interactive
chrysalis -i
```

#### 3.2 Working Configuration Examples
**Update**: `.env.example` with working examples

```bash
# Option 1: OpenAI (requires paid account)
OPENAI_API_KEY=sk-proj-...
OPENAI_API_BASE=https://api.openai.com/v1
MODEL=gpt-4o-mini

# Option 2: Ollama (free, local)
OPENAI_API_BASE=http://localhost:11434/v1
MODEL=llama3.2

# Option 3: Groq (free tier available)
OPENAI_API_KEY=gsk_...
OPENAI_API_BASE=https://api.groq.com/openai/v1
MODEL=llama-3.3-70b-versatile
```

#### 3.3 Troubleshooting Guide
**Create**: `TROUBLESHOOTING.md`

Sections:
- "404 Not Found" errors
- "401 Unauthorized" errors
- Model selection issues
- Permission denied errors
- Network connectivity
- API rate limits

### Priority 4: Developer Experience (Week 3-4)

#### 4.1 Fix LSP Diagnostics
**Actions**:
- Add `.editorconfig` to declare `.md` and `.toml` as non-Racket
- Remove unused variables and requires
- Fix actual code issues

#### 4.2 Add Test Mode
**Feature**: `--test-mode` flag that uses mock LLM responses

**Use Case**: Test tool operations, session management, configuration without API calls

**File**: `src/core/test-mode.rkt`

```racket
(define (mock-run-turn sid prompt-blocks emit! tool-emit! cancelled?)
  (emit! "[MOCK] Processing your request...")
  (tool-emit! (hash 'name 'read_file 'args (hash 'path ".")))
  (emit! "[MOCK] Here are the files..."))
```

#### 4.3 Session Management CLI
**Enhance**: Add dedicated session commands

```bash
chrysalis session list
chrysalis session delete <id>
chrysalis session export <id> > backup.json
chrysalis session import < backup.json
```

#### 4.4 Tool Operations Without LLM
**Feature**: Direct tool invocation mode

```bash
chrysalis tool list_files /path/to/dir
chrysalis tool read_file /path/to/file
chrysalis tool search_code "pattern" /path
```

**Use Case**: Scripted workflows, debugging tools, CI integration

### Priority 5: Polish & Refinement (Ongoing)

#### 5.1 Terminal Compatibility
**Fix**: Handle non-TTY environments gracefully

**File**: `src/core/repl.rkt`

**Change**: Detect TTY and adjust behavior
```racket
(define (tty-available?)
  (port? (current-input-port)))

(unless (tty-available?)
  (set! read-multiline-input read-line))
```

#### 5.2 Progress Indicators
**Enhance**: Better feedback for long operations

- Connection progress
- Model loading
- Tool execution status
- File operation progress

#### 5.3 Color Scheme Options
**Feature**: Theme configuration

```bash
export CHRYSALIS_THEME=dark
export CHRYSALIS_THEME=light
export CHRYSALIS_THEME=none
```

#### 5.4 Shell Completion
**Add**: Bash/zsh completion scripts

**File**: `completions/chrysalis.bash`

**Commands**: `chrysalis`, `/config`, `/session`, `/thread`, tools

#### 5.5 Update VHS Recordings
**Refresh**: All `.vhs/*.gif` with working commands

**Ensure**: Model names, paths, and outputs are accurate

---

## Success Metrics

### Week 1 (Critical Fixes)
- ✅ New users can run `chrysalis "test"` and get a working response
- ✅ Setup wizard completes in <2 minutes
- ✅ Error messages are actionable (include suggested fixes)

### Week 2 (Configuration)
- ✅ `/config validate` catches 90% of configuration issues
- ✅ All documented commands work as shown
- ✅ Quickstart guide has <50% error rate for new users

### Week 3-4 (Developer Experience)
- ✅ LSP shows <10 warnings (down from 100+)
- ✅ Test mode enables CI testing
- ✅ Bash completion reduces typing by 30%

---

## Technical Debt Notes

### Code Quality
- Many unused requires and variables
- Inconsistent error handling patterns
- Some code duplication (main.rkt vs commands.rkt)

### Architecture
- Model registry exists but not integrated
- Config system scattered (env vars, TOML, runtime params)
- No configuration schema validation

### Testing
- No automated tests for CLI interactions
- No integration tests with real APIs
- VHS recordings are the only "tests"

### Documentation
- API.md incomplete (many functions undocumented)
- THEORY.md mentions features not yet implemented
- Code examples don't match current CLI behavior

---

## Risk Assessment

### High Risk
- **Default model failure**: Blocks all new users immediately
- **No setup wizard**: High drop-off during onboarding
- **API endpoint issues**: Even configured users fail

### Medium Risk
- **Poor error messages**: Users can't self-diagnose
- **Config complexity**: Misconfiguration likely
- **LSP noise**: Hard to maintain code

### Low Risk
- **Terminal compatibility**: Affects power users, not core flow
- **Missing features**: Can be added incrementally

---

## Conclusion

Chrysalis Forge is an impressively engineered system with cutting-edge features (GEPA, MAP-Elites, self-evolution) and solid Racket architecture. However, the user experience is currently blocked by fundamental configuration issues that prevent any actual use.

**The good news**: All problems are fixable without architectural changes. The code is well-organized, and the feature set is sound. Focused work on onboarding, configuration, and documentation will transform this from "unusable" to "delightful."

**Recommended approach**: Start with Priority 1 (critical fixes) to make the system work at all, then progress through priorities to polish the experience. Each priority builds on the last, so success compounds.

With these improvements, Chrysalis Forge could become the go-to Racket-based LLM agent framework for researchers and developers who want sophisticated optimization and self-improvement capabilities.
