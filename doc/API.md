# Chrysalis Forge API Reference & Extension Guide

This document provides a comprehensive API reference for developers who want to extend Chrysalis Forge or use its components programmatically.

## Table of Contents

1. [Core Data Structures](#1-core-data-structures)
2. [Core Functions](#2-core-functions)
3. [Geometric Decomposition API](#3-geometric-decomposition-api)
4. [Evolution API](#4-evolution-api)
5. [Context Store API](#5-context-store-api)
6. [Eval Store API](#6-eval-store-api)
7. [Adding Custom Tools](#7-adding-custom-tools)
8. [Creating Custom Modules](#8-creating-custom-modules)
9. [Custom Optimization Strategies](#9-custom-optimization-strategies)
10. [Integration Examples](#10-integration-examples)

---

## 1. Core Data Structures

All core structures are defined in `src/llm/dspy-core.rkt` and exported via `(provide (all-defined-out))`.

### Signatures and Fields

```racket
(struct SigField (name pred) #:transparent)
(struct Signature (name ins outs) #:transparent)
```

**SigField** represents a single input or output field:
- `name`: Symbol identifying the field
- `pred`: Predicate function for validation (e.g., `string?`, `number?`)

**Signature** defines the interface of a task:
- `name`: Symbol name for the signature
- `ins`: List of `SigField` for inputs
- `outs`: List of `SigField` for outputs

#### Creating Signatures with the `signature` Macro

```racket
(define MySig 
  (signature MyTask 
    (in [query string?] [context string?]) 
    (out [answer string?] [confidence number?])))
```

The macro automatically wraps field definitions into `SigField` structs.

### Modules

```racket
(struct Module (id sig strategy instructions demos params) #:transparent)
```

- `id`: Unique string identifier (auto-generated if not provided)
- `sig`: The `Signature` this module implements
- `strategy`: Either `'predict` or `'cot` (chain-of-thought)
- `instructions`: String prompt instructions
- `demos`: List of few-shot example hashes
- `params`: Hash of additional parameters (e.g., `'temperature`)

#### Module Constructors

```racket
;; Direct prediction - fastest, simplest
(define (Predict sig 
                 #:id [id #f] 
                 #:instructions [inst ""] 
                 #:demos [demos '()] 
                 #:params [p (hash)]) → Module)

;; Chain-of-Thought - structured reasoning before output
(define (ChainOfThought sig 
                        #:id [id #f] 
                        #:instructions [inst ""] 
                        #:demos [demos '()] 
                        #:params [p (hash)]) → Module)
```

#### Module Modifiers

```racket
(define (module-set-instructions m s) → Module)
(define (module-set-demos m d) → Module)
```

### Module Archives

```racket
(struct ModuleArchive (id sig archive point-cloud default-id) #:transparent)
```

A `ModuleArchive` stores multiple evolved variants of a module for priority-based selection:

- `id`: Base module identifier
- `sig`: The signature all variants implement
- `archive`: Hash of `bin-key → (cons score module)` for discrete bins
- `point-cloud`: List of `(cons Phenotype Module)` for KNN geometric search
- `default-id`: Key of the best-performing variant

**Bin keys** are lists like `'(cheap fast compact)` or `'(premium slow verbose)`.

### Phenotypes

```racket
(struct Phenotype (accuracy latency cost usage) #:transparent)
```

Phenotypes represent modules in a 4D continuous space:
- `accuracy`: Score from 0-10 (higher is better)
- `latency`: Response time in milliseconds
- `cost`: API cost in dollars
- `usage`: Total token count

### Context

```racket
(struct Ctx (system memory tool-hints mode priority history compacted-summary) #:transparent)
```

- `system`: System prompt string
- `memory`: Working memory/scratchpad string
- `tool-hints`: Guidance on tool usage
- `mode`: Operational mode symbol (`'ask`, `'architect`, `'code`, `'semantic`)
- `priority`: Symbol (`'fast`, `'cheap`, `'best`) or natural language string
- `history`: List of conversation messages
- `compacted-summary`: Summarized older conversation turns

#### Context Macro

```racket
(ctx)  ; Default context
(ctx #:system "Custom system prompt")
(ctx #:system s #:memory m #:tool-hints t #:mode mo #:priority p #:history h #:compacted c)
```

### Run Results

```racket
(struct RunResult (ok? outputs raw prompt meta) #:transparent)
```

- `ok?`: Boolean success indicator
- `outputs`: Hash of parsed output fields
- `raw`: Raw response string from LLM
- `prompt`: The rendered prompt sent to the LLM
- `meta`: Hash with `'elapsed_ms`, `'model`, `'prompt_tokens`, `'completion_tokens`

---

## 2. Core Functions

### Module Execution

```racket
(define (run-module m ctx inputs send! 
                    #:trace [tr #f] 
                    #:cache? [cache? #t]) → RunResult)
```

Executes a module or module archive:
- `m`: `Module` or `ModuleArchive`
- `ctx`: Execution context
- `inputs`: Hash of input field values
- `send!`: Function `(prompt) → (values ok? raw meta)`
- `tr`: Optional trace callback
- `cache?`: Whether to cache results

**Priority-based selection** for `ModuleArchive`:
- Symbol priorities (`'fast`, `'cheap`, `'compact`, `'verbose`): Uses bin matching
- `'best`: Uses the default (highest scoring) variant
- String priorities: Uses geometric KNN selection

**Vision support**: If inputs contain image URLs (starting with `data:image` or ending in `.png`/`.jpg`), the prompt is formatted with image content blocks.

### Elite Selection (from `src/llm/dspy-selector.rkt`)

```racket
(define (select-elite archive target) → Module)
```

Selects the module closest to `target` phenotype using KNN (k=1) in normalized phenotype space.

```racket
(define (text->vector text [send!]) → Phenotype)
```

Converts natural language priority to a target phenotype:
- First tries keyword matching (fast, cheap, accurate, concise, etc.)
- Falls back to LLM interpretation if no keywords match

```racket
(define (phenotype-distance p1 p2) → number?)
```

Euclidean distance between two phenotypes.

```racket
(define (normalize-phenotype pheno mins maxs) → Phenotype)
```

Normalizes a phenotype to [0,1] range for fair distance comparison.

### Scoring

```racket
(define (score-result expected rr) → number?)
```

Computes a composite score:
```
score = accuracy - latency_penalty - cost_penalty
```
- `accuracy`: 10.0 if outputs match expected, 0.0 otherwise
- `latency_penalty`: Up to 2.0 for responses taking 10+ seconds
- `cost_penalty`: $0.001 → 1.0 penalty

---

## 3. Geometric Decomposition API

Defined in `src/core/geometric-decomposition.rkt`. Provides task decomposition with explosion detection and checkpoint/rollback.

### Phenotype Operations

```racket
(struct DecompositionPhenotype (depth breadth accumulated-cost context-size success-rate) #:transparent)

(define (make-initial-phenotype) → DecompositionPhenotype)
;; Returns: (DecompositionPhenotype 0 0 0 0 1.0)

(define (update-phenotype pheno
                          #:depth [d #f]
                          #:breadth [b #f]
                          #:cost [c #f]
                          #:context [ctx #f]
                          #:success [sr #f]) → DecompositionPhenotype)

(define (phenotype+ p1 p2) → DecompositionPhenotype)
;; Combines phenotypes: max depth/breadth, sum costs/context, average success-rate
```

### Limits and Explosion Detection

```racket
(struct DecompositionLimits (max-depth max-breadth max-cost max-context min-success-rate) #:transparent)

(define (limits-for-priority priority budget context-limit) → DecompositionLimits)
```

Priority-based limit presets:
| Priority | max-depth | max-breadth | max-cost | max-context | min-success |
|----------|-----------|-------------|----------|-------------|-------------|
| `'critical` | 10 | 20 | budget×2 | limit×1.5 | 0.6 |
| `'high` | 8 | 15 | budget×1.5 | limit | 0.7 |
| `'normal` | 6 | 10 | budget | limit×0.8 | 0.75 |
| `'low` | 4 | 6 | budget×0.5 | limit×0.5 | 0.8 |

```racket
(define (detect-explosion phenotype limits) → (or/c 'depth 'breadth 'cost 'context 'low-success #f))
```

Returns the type of explosion detected, or `#f` if within limits.

### Tree Operations

```racket
(struct DecompNode (id task status children result profile) #:transparent #:mutable)

(define (make-root-node task) → DecompNode)
(define (add-child! parent-node child-node) → void?)
(define (node-depth node tree) → integer?)
(define (count-leaves tree) → integer?)
(define (compute-breadth tree) → integer?)
(define (mark-node-status! node status) → void?)
(define (prune-node! node) → void?)
```

### Checkpoint/Rollback

```racket
(struct DecompositionCheckpoint (tree-snapshot phenotype step-index reason) #:transparent)

(define (checkpoint! state reason) → DecompositionState)
(define (rollback! state) → DecompositionState)
(define (has-checkpoints? state) → boolean?)
```

### State Management

```racket
(struct DecompositionState (root-task task-type priority tree phenotype limits checkpoints steps-taken meta) 
  #:transparent #:mutable)

(define (make-decomposition-state root-task task-type priority limits) → DecompositionState)
```

---

## 4. Evolution API

### GEPA Evolution (from `src/core/optimizer-gepa.rkt`)

```racket
(define (gepa-evolve! feedback [model "gpt-5.2"]) → string?)
```

Evolves the active context's system prompt based on feedback:
1. Loads the current active context
2. Sends current system prompt + feedback to meta-optimizer
3. Creates a new context variant with the evolved prompt
4. Returns `"Context Evolved."` or `"Evolution Failed."`

```racket
(define (gepa-meta-evolve! feedback [model "gpt-5.2"]) → string?)
```

Evolves the optimizer itself by rewriting the meta-prompt stored at `~/.agentd/meta_prompt.txt`.

### Meta-Optimization (from `src/core/optimizer-meta.rkt`)

```racket
(define OptSig 
  (signature Opt 
    (in [inst string?] [fails string?]) 
    (out [thought string?] [new_inst string?])))

(define (make-meta-optimizer) → Module)
;; Creates a ChainOfThought module for instruction optimization

(define (meta-optimize-module target ctx trainset send!) → (values Module string?))
```

The meta-optimizer:
1. Identifies failing examples (score < 9.0)
2. Sends current instructions + failures to the optimizer module
3. Returns the improved module and status message

---

## 5. Context Store API

Defined in `src/stores/context-store.rkt`. Manages persistent context sessions.

### Loading and Saving

```racket
(define (load-ctx) → hash?)
;; Returns: (hash 'active symbol? 'items (hash symbol? Ctx?))

(define (save-ctx! db) → void?)
```

Contexts are stored at `~/.agentd/context.json`.

### Active Context

```racket
(define (ctx-get-active) → Ctx?)
```

Returns the active context with project rules appended if `.agentd/rules.md` exists in the current directory.

### Session Management

```racket
(define (session-list) → (values list? symbol?))
;; Returns: (values session-names active-session)

(define (session-create! name [mode 'code]) → void?)
(define (session-switch! name) → void?)
(define (session-delete! name) → void?)
```

---

## 6. Eval Store API

Defined in `src/stores/eval-store.rkt`. Tracks sub-agent performance for learning.

### Logging Evaluations

```racket
(define (log-eval! #:task-id task-id 
                   #:success? success? 
                   #:profile profile
                   #:task-type [task-type "unknown"]
                   #:tools-used [tools-used '()]
                   #:duration-ms [duration-ms 0]
                   #:feedback [feedback ""]) → void?)
```

Appends to `~/.agentd/evals.jsonl` and updates aggregate stats.

### Querying Statistics

```racket
(define (get-profile-stats [profile #f]) → hash?)
;; Returns stats for one profile or all profiles
;; Each profile has: 'total, 'success, 'success_rate, 'task_types, 'tool_freq

(define (get-tool-stats) → hash?)
;; Returns aggregated tool usage frequency across all profiles
```

### Profile Recommendation

```racket
(define (suggest-profile task-type) → (values symbol? number?))
;; Returns: (values best-profile success-rate)
```

Suggests the optimal profile based on historical success rates for the given task type.

### Profile Evolution

```racket
(define (evolve-profile! profile-name #:threshold [threshold 0.7]) → hash?)
;; Returns analysis with:
;; - 'profile: the profile name
;; - 'success_rate: current rate
;; - 'recommended_tools: top 5 most-used tools
;; - 'evaluation: "stable" or "needs_improvement"
```

---

## 7. Adding Custom Tools

Tools are defined in `src/tools/acp-tools.rkt`.

### Tool Definition Structure

Each tool is a hash with:
```racket
(hash 'type "function"
      'function (hash 'name "tool_name"
                      'description "What the tool does"
                      'parameters (hash 'type "object"
                                        'properties (hash 'param1 (hash 'type "string" 
                                                                        'description "param description")
                                                          ...)
                                        'required '("param1" ...))))
```

### Mode Gating

Tools can be restricted by security level in `execute-acp-tool`:
```racket
(if (>= security-level 2)
    (do-the-thing ...)
    "Permission Denied: Requires security level 2.")
```

Security levels:
- Level 1 (`'ask` mode): Read-only operations
- Level 2 (`'code` mode): File writes, git commits, system changes

### Example: Adding a New Tool

**Step 1: Define the tool metadata** in `make-acp-tools`:

```racket
(hash 'type "function"
      'function (hash 'name "my_custom_tool"
                      'description "Does something useful"
                      'parameters (hash 'type "object"
                                        'properties (hash 'input (hash 'type "string" 
                                                                       'description "Input data")
                                                          'flag (hash 'type "boolean" 
                                                                      'description "Optional flag"))
                                        'required '("input"))))
```

**Step 2: Implement the handler** in `execute-acp-tool`:

```racket
["my_custom_tool"
 (define input (hash-ref args 'input))
 (define flag (hash-ref args 'flag #f))
 (if flag
     (process-with-flag input)
     (process-without-flag input))]
```

**Step 3: Add mode permissions** if needed:

```racket
["my_custom_tool"
 (if (>= security-level 2)
     (begin
       (define input (hash-ref args 'input))
       (do-something-destructive input))
     "Permission Denied: Requires security level 2.")]
```

### MCP Server Integration

Connect external tool servers via MCP:

```racket
(register-mcp-server! "server-name" "npx" '("@modelcontextprotocol/server-package"))
```

This dynamically adds all tools from the MCP server.

---

## 8. Creating Custom Modules

### Basic Module

```racket
(require chrysalis-forge/llm/dspy-core)

(define MySig 
  (signature MyTask 
    (in [query string?]) 
    (out [answer string?])))

(define my-module 
  (ChainOfThought MySig 
    #:instructions "Be concise and accurate."))
```

### Module with Demos (Few-Shot Learning)

```racket
(define my-module 
  (ChainOfThought MySig 
    #:instructions "Analyze the query carefully."
    #:demos (list 
              (hash 'query "What is 2+2?" 'answer "4")
              (hash 'query "Capital of France?" 'answer "Paris"))))
```

### Module with Custom Parameters

```racket
(define creative-module
  (ChainOfThought MySig
    #:instructions "Be creative and exploratory."
    #:params (hash 'temperature 0.9)))
```

### Creating Module Archives

To enable priority-based selection, compile a module into an archive:

```racket
(require chrysalis-forge/llm/dspy-compile)

(define trainset
  (list (hash 'inputs (hash 'query "test1") 'expected (hash 'answer "result1"))
        (hash 'inputs (hash 'query "test2") 'expected (hash 'answer "result2"))))

(define my-archive
  (compile! my-module my-ctx trainset send!
    #:k-demos 3      ; Number of demos to bootstrap
    #:n-inst 5       ; Instruction mutations per generation
    #:iters 3))      ; Evolution iterations
```

The resulting `ModuleArchive` contains:
- Multiple variants binned by `(cost, latency, usage)`
- A point-cloud for geometric KNN selection
- The best-performing variant as default

---

## 9. Custom Optimization Strategies

### Understanding the Compile Pipeline

The `compile!` function in `src/llm/dspy-compile.rkt` implements MAP-Elites optimization:

1. **Bootstrap**: Sample few-shot demos from training set
2. **Initialize**: Create seed population via instruction mutations
3. **Establish Baselines**: Calculate median cost/latency/usage thresholds
4. **Evolve**: For each generation:
   - Select random elite from archive
   - Meta-optimize to create child variants
   - Evaluate and update archive

### Implementing a Custom Optimizer

Create a new optimizer following this interface:

```racket
(define (my-custom-compile! m ctx trainset send! #:options [opts (hash)])
  ;; 1. Evaluate the base module
  (define base-results 
    (for/list ([ex trainset])
      (run-module m ctx (hash-ref ex 'inputs) send!)))
  
  ;; 2. Apply your optimization strategy
  (define optimized-m (my-optimization-logic m base-results))
  
  ;; 3. Return a ModuleArchive or optimized Module
  optimized-m)
```

### Custom Mutation Strategies

Replace the default mutations:

```racket
(define (my-instruction-mutations base)
  (list base
        (string-append "IMPORTANT: " base)
        (string-append base "\n\nFormat your response as a numbered list.")
        (string-append "Step by step:\n" base)))
```

### Custom Scoring Functions

Implement domain-specific evaluation:

```racket
(define (my-score-result expected rr)
  (define actual (RunResult-outputs rr))
  (define meta (RunResult-meta rr))
  
  ;; Custom accuracy: partial credit for similar answers
  (define accuracy 
    (cond
      [(equal? expected actual) 10.0]
      [(similar? expected actual) 7.0]
      [else 0.0]))
  
  ;; Domain-specific latency requirements
  (define elapsed (hash-ref meta 'elapsed_ms 0))
  (define latency-penalty (if (> elapsed 2000) 3.0 0.0))
  
  (max 0.1 (- accuracy latency-penalty)))
```

---

## 10. Integration Examples

### Using as a Library

```racket
#lang racket
(require chrysalis-forge/llm/dspy-core
         chrysalis-forge/llm/openai-client)

;; Create a sender function
(define send! (make-openai-sender #:model "gpt-4o"))

;; Define and run a module
(define QASig (signature QA (in [question string?]) (out [answer string?])))
(define qa-module (ChainOfThought QASig #:instructions "Answer concisely."))

(define ctx (ctx #:system "You are a helpful assistant." #:mode 'code #:priority 'fast))
(define result (run-module qa-module ctx (hash 'question "What is Racket?") send!))

(when (RunResult-ok? result)
  (printf "Answer: ~a\n" (hash-ref (RunResult-outputs result) 'answer)))
```

### Programmatic Agent Creation

```racket
(require chrysalis-forge/core/sub-agent
         chrysalis-forge/tools/acp-tools)

;; Define a task runner
(define (run-task prompt context tools-filter)
  (define tools (filter-tools-by-names (make-acp-tools) tools-filter))
  ;; Your agent loop implementation here
  (format "Completed: ~a" prompt))

;; Spawn parallel sub-agents
(define task1 (spawn-sub-agent! "Analyze code" run-task #:profile 'researcher))
(define task2 (spawn-sub-agent! "Fix bugs" run-task #:profile 'editor))

;; Wait for results
(define result1 (await-sub-agent! task1))
(define result2 (await-sub-agent! task2))
```

### Custom Context with Project Rules

```racket
(require chrysalis-forge/stores/context-store
         chrysalis-forge/llm/dspy-core)

;; Create a specialized context
(define my-ctx
  (Ctx "You are a Racket expert."           ; system
       "Current task: refactor module"       ; memory
       "Prefer patch_file over write_file"   ; tool-hints
       'code                                  ; mode
       "accurate but concise"                 ; priority (NL string)
       '()                                    ; history
       ""))                                   ; compacted-summary

;; Save as a named session
(define db (load-ctx))
(save-ctx! (hash-set db 'items 
                     (hash-set (hash-ref db 'items) 
                               'racket-expert my-ctx)))
```

### Geometric Priority Selection

```racket
(require chrysalis-forge/llm/dspy-selector
         chrysalis-forge/llm/dspy-core)

;; After compiling a module archive:
(define archive (compile! base-module ctx trainset send!))

;; Select variant for specific requirements
(define fast-variant 
  (select-elite archive (Phenotype 5.0 0.0 0.5 0.5)))  ; Low latency

(define cheap-variant
  (select-elite archive (Phenotype 5.0 0.5 0.0 0.5)))  ; Low cost

;; Or use natural language priority in context
(define nl-ctx (struct-copy Ctx ctx [priority "I need accurate results but cost must be minimal"]))
(define result (run-module archive nl-ctx inputs send!))  ; Auto-selects via KNN
```

### Full Training Loop with Eval Logging

```racket
(require chrysalis-forge/stores/eval-store
         chrysalis-forge/llm/dspy-compile
         chrysalis-forge/core/sub-agent)

;; Train a module
(define archive (compile! my-module my-ctx trainset send! #:iters 5))

;; Use in production with eval logging
(define (run-with-logging task-prompt)
  (define task-id (spawn-sub-agent! task-prompt my-runner #:profile 'editor))
  (define result (await-sub-agent! task-id))
  
  ;; Log for learning
  (log-eval! #:task-id task-id
             #:success? (not (string-prefix? result "Error"))
             #:profile 'editor
             #:task-type "code-edit"
             #:tools-used '("read_file" "patch_file"))
  
  result)

;; Check what's working
(define stats (get-profile-stats 'editor))
(printf "Editor profile success rate: ~a%\n" 
        (* 100 (hash-ref stats 'success_rate 0)))

;; Evolve if needed
(when (< (hash-ref stats 'success_rate 0) 0.7)
  (gepa-evolve! "Editor tasks are failing too often. Focus on smaller, targeted edits."))
```

---

## Appendix: Quick Reference

### Module Strategies
| Constructor | Strategy | Use Case |
|-------------|----------|----------|
| `Predict` | `'predict` | Fast, simple completions |
| `ChainOfThought` | `'cot` | Complex reasoning tasks |

### Context Modes
| Mode | Description | Tool Access |
|------|-------------|-------------|
| `'ask` | Basic interaction | Read-only |
| `'architect` | Analysis mode | Read files |
| `'code` | Full capabilities | All tools |
| `'semantic` | RDF Knowledge Graph | Specialized |

### Sub-Agent Profiles
| Profile | Tools Included |
|---------|----------------|
| `'editor` | read_file, write_file, patch_file, preview_diff, list_dir |
| `'researcher` | read_file, list_dir, grep_code, web_search, web_fetch |
| `'vcs` | git_*, jj_* |
| `'all` | All available tools |

### File Locations
| Purpose | Path |
|---------|------|
| Context store | `~/.agentd/context.json` |
| Eval log | `~/.agentd/evals.jsonl` |
| Profile stats | `~/.agentd/profile_stats.json` |
| Meta-optimizer prompt | `~/.agentd/meta_prompt.txt` |
| Project rules | `./.agentd/rules.md` |
