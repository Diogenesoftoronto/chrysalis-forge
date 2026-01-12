# Chrysalis Forge API Reference

This document provides the programming interface for developers who want to extend Chrysalis Forge or embed its components in other systems. Rather than a dry enumeration of function signatures, we'll walk through the API by explaining what problems each component solves and how to use it effectively.

---

## The DSPy Core: Typed LLM Interactions

The foundation of Chrysalis Forge's programming model lives in `src/llm/dspy-core.rkt`. This module provides the abstractions that turn ad-hoc LLM prompting into structured, typed function calls.

### Signatures: Declaring What Goes In and Out

A `Signature` declares the interface of an LLM task—what inputs it expects and what outputs it produces. This explicitness enables validation, composition, and optimization.

```racket
(struct SigField (name pred) #:transparent)
(struct Signature (name ins outs) #:transparent)
```

Each field has a `name` (a symbol) and a `pred` (a predicate function like `string?` or `number?`). The predicate isn't just documentation—it's used to validate responses.

Creating signatures by hand is tedious, so a macro provides cleaner syntax:

```racket
(define MySig 
  (signature MyTask 
    (in [query string?] [context string?]) 
    (out [answer string?] [confidence number?])))
```

This creates a signature named `MyTask` with two string inputs (`query` and `context`) and two outputs (`answer` as string, `confidence` as number).

The signature becomes the contract that the rest of the system relies on. When you run a module, the outputs are parsed and validated against the signature. If the LLM returns malformed output, you find out immediately rather than having corruption propagate through your system.

### Modules: Wrapping Signatures with Execution Strategy

A `Module` pairs a signature with instructions and execution strategy:

```racket
(struct Module (id sig strategy instructions demos params) #:transparent)
```

The `strategy` determines how the prompt is structured. Two strategies are available:

**Predict** (`'predict`) generates output directly. It's fast and works well for straightforward tasks.

**ChainOfThought** (`'cot`) instructs the model to reason step-by-step before producing output. This often improves accuracy on complex tasks at the cost of additional tokens.

Creating modules uses constructor functions:

```racket
;; Simple direct prediction
(define summarizer
  (Predict SummarizeSig
    #:instructions "Summarize the input text concisely."))

;; Chain-of-thought reasoning
(define analyzer
  (ChainOfThought AnalysisSig
    #:instructions "Analyze the code for potential issues. Think through each consideration."
    #:demos (list (hash 'input "example code" 
                        'thought "First I notice..."
                        'analysis "The code has..."))))
```

The `demos` parameter provides few-shot examples. Each demo is a hash mapping field names to values, showing the model what good input/output pairs look like. Including a few well-chosen demos often improves quality dramatically.

The `params` hash passes additional settings like temperature:

```racket
(define creative-module
  (Predict CreativeSig
    #:instructions "Generate creative variations."
    #:params (hash 'temperature 0.9)))
```

### Module Archives: Collections for Priority-Based Selection

When you compile a module (optimizing it via MAP-Elites), you get back a `ModuleArchive` containing multiple variants:

```racket
(struct ModuleArchive (id sig archive point-cloud default-id) #:transparent)
```

The `archive` hash maps bin keys to (score, module) pairs. Bin keys are lists like `'(cheap fast compact)` describing the phenotype bin. This enables fast lookup when someone asks for "the cheap one."

The `point-cloud` is a list of (phenotype, module) pairs for continuous KNN search. When someone asks for "something balanced between speed and accuracy," geometric search finds the best match.

You rarely create archives directly—they're produced by the `compile!` function. But you consume them by passing them to `run-module`:

```racket
;; Run with automatic selection based on context priority
(define result (run-module my-archive ctx inputs send!))
```

The `run-module` function examines the `priority` in the context and selects the appropriate variant.

### Contexts: Runtime State

The `Ctx` structure carries all runtime state for an agent:

```racket
(struct Ctx (system memory tool-hints mode priority history compacted-summary) #:transparent)
```

Each field serves a specific purpose:

**system** is the system prompt—the core instructions defining agent behavior. This is what GEPA evolves.

**memory** is a working scratchpad for temporary state within a task.

**tool-hints** provides guidance about tool usage that doesn't belong in the system prompt.

**mode** gates tool access (`'ask`, `'architect`, `'code`, `'semantic`).

**priority** specifies the performance profile—either a symbol (`'fast`, `'cheap`, `'best`) or a natural language string.

**history** contains the conversation so far as a list of messages.

**compacted-summary** holds a compressed summary of prior context when history grows too long.

A convenience macro creates contexts with sensible defaults:

```racket
(define my-ctx
  (ctx #:system "You are a helpful coding assistant."
       #:mode 'code
       #:priority 'best))
```

### Running Modules

The `run-module` function executes a module (or selects from an archive and executes):

```racket
(define (run-module m ctx inputs send! #:trace [tr #f] #:cache? [cache? #t]) → RunResult)
```

The `inputs` parameter is a hash mapping input field names to values. The `send!` parameter is a function that actually calls the LLM—this abstraction allows different backends.

The result is a `RunResult`:

```racket
(struct RunResult (ok? outputs raw prompt meta) #:transparent)
```

If `ok?` is true, `outputs` contains a hash of output field values. If false, something went wrong—the raw response is still available in `raw` for debugging.

The `meta` hash includes execution metadata: elapsed time, token counts, model used. This feeds into phenotype extraction for evolution.

---

## Geometric Selection: Finding the Right Variant

The `src/llm/dspy-selector.rkt` module handles priority-based selection from module archives.

### Phenotypes and Distance

A `Phenotype` represents position in a 4D performance space:

```racket
(struct Phenotype (accuracy latency cost usage) #:transparent)
```

Each dimension is continuous. Distance between phenotypes uses Euclidean metric:

```racket
(define (phenotype-distance p1 p2)
  (sqrt (+ (expt (- (Phenotype-accuracy p1) (Phenotype-accuracy p2)) 2)
           (expt (- (Phenotype-latency p1) (Phenotype-latency p2)) 2)
           (expt (- (Phenotype-cost p1) (Phenotype-cost p2)) 2)
           (expt (- (Phenotype-usage p1) (Phenotype-usage p2)) 2))))
```

Raw phenotypes have incompatible scales, so normalization is essential:

```racket
(define (normalize-phenotype pheno mins maxs) → Phenotype)
```

This maps each dimension to [0,1] based on the observed range in the point cloud.

### Selecting Elites

The `select-elite` function finds the closest module to a target phenotype:

```racket
(define (select-elite archive target) → Module)
```

It normalizes all phenotypes in the point cloud, normalizes the target, computes distances, and returns the nearest match.

### Mapping Natural Language to Phenotypes

The `text->vector` function interprets priority descriptions:

```racket
(define (text->vector text [send! #f]) → Phenotype)
```

For recognized keywords ("fast", "cheap", "accurate"), it returns hardcoded phenotypes. For novel descriptions, it calls the LLM to interpret the request, returning a phenotype that captures the user's preferences.

This enables natural language priority specification:

```racket
(define target (text->vector "I need accuracy but cost matters" send!))
(define best-module (select-elite archive target))
```

---

## Geometric Decomposition: Breaking Down Complex Tasks

The `src/core/geometric-decomposition.rkt` module implements MAKER-inspired task decomposition with self-regulation.

### The Decomposition Phenotype

Task decomposition has its own phenotype space:

```racket
(struct DecompositionPhenotype 
  (depth breadth accumulated-cost context-size success-rate) 
  #:transparent)
```

These five dimensions capture the shape of a decomposition:

- **depth**: levels of subtask nesting
- **breadth**: maximum parallel fan-out
- **accumulated-cost**: total $ spent so far
- **context-size**: peak context tokens
- **success-rate**: fraction of subtasks succeeding

### Limits and Explosion Detection

Limits constrain how far decomposition can go:

```racket
(struct DecompositionLimits 
  (max-depth max-breadth max-cost max-context min-success-rate) 
  #:transparent)
```

The `limits-for-priority` function returns appropriate limits based on task priority:

```racket
(define (limits-for-priority priority budget context-limit) → DecompositionLimits)
```

Critical tasks get generous limits; low-priority tasks are constrained.

Explosion detection checks all dimensions:

```racket
(define (detect-explosion phenotype limits) → (or/c symbol? #f))
```

Returns `'depth`, `'breadth`, `'cost`, `'context`, or `'low-success` if any limit is exceeded, `#f` otherwise.

### State Management

Decomposition state is mutable (for efficiency with large trees):

```racket
(struct DecompositionState 
  (root-task task-type priority tree phenotype limits checkpoints steps-taken meta) 
  #:transparent #:mutable)
```

Create initial state with:

```racket
(define (make-decomposition-state root-task task-type priority limits) → DecompositionState)
```

### Checkpoint and Rollback

Before risky operations, save a checkpoint:

```racket
(define (checkpoint! state reason) → DecompositionState)
```

If explosion is detected, roll back:

```racket
(define (rollback! state) → DecompositionState)
```

Check if rollback is possible:

```racket
(define (has-checkpoints? state) → boolean?)
```

This checkpoint/rollback mechanism is what enables exploration of multiple decomposition strategies without committing irrevocably.

### Tree Operations

The decomposition tree uses `DecompNode` structures:

```racket
(struct DecompNode (id task status children result profile) #:transparent #:mutable)
```

Operations for tree manipulation:

```racket
(define (make-root-node task) → DecompNode)
(define (add-child! parent-node child-node) → void?)
(define (node-depth node tree) → integer?)
(define (count-leaves tree) → integer?)
(define (compute-breadth tree) → integer?)
(define (mark-node-status! node status) → void?)
(define (prune-node! node) → void?)
```

These enable building the task tree as decomposition proceeds, computing phenotype dimensions, and pruning failed branches.

---

## Evolution: Improving Over Time

The `src/core/optimizer-gepa.rkt` module implements reflective prompt evolution.

### GEPA Evolution

```racket
(define (gepa-evolve! feedback [model "gpt-5.2"]) → string?)
```

Takes natural language feedback about what's wrong, loads the current context, asks an LLM to produce an improved prompt, and saves the result. Returns "Context Evolved." on success.

Example:

```racket
(gepa-evolve! "The agent produces overly verbose explanations. It should be more concise.")
```

### Meta-Evolution

```racket
(define (gepa-meta-evolve! feedback [model "gpt-5.2"]) → string?)
```

Evolves the optimizer's own instructions. This is the recursive self-improvement loop—when the optimization process itself can be improved, meta-evolution handles it.

---

## Sub-Agent Management

The `src/core/sub-agent.rkt` module enables parallel task execution.

### Tool Profiles

Four profiles restrict tool access for sub-agents:

```racket
(define PROFILE-EDITOR
  '("read_file" "write_file" "patch_file" "preview_diff" "list_dir"))

(define PROFILE-RESEARCHER
  '("read_file" "list_dir" "grep_code" "web_search" "web_fetch" "web_search_news"))

(define PROFILE-VCS
  '("git_status" "git_diff" "git_log" "git_commit" "git_checkout"
    "jj_status" "jj_log" "jj_diff" "jj_undo" "jj_op_log" "jj_op_restore"
    "jj_workspace_add" "jj_workspace_list" "jj_describe" "jj_new"))

(define PROFILE-ALL #f)  ; No filtering
```

Get a profile by name:

```racket
(define (get-tool-profile name) → (or/c list? #f))
```

Filter tools:

```racket
(define (filter-tools-by-names all-tools allowed-names) → list?)
```

### Spawning and Awaiting

Spawn a sub-agent:

```racket
(define (spawn-sub-agent! prompt run-fn 
                          #:context [context ""] 
                          #:profile [profile 'all]) → string?)
```

Returns a task ID. The `run-fn` is a function `(prompt context tools-filter) -> result` that executes the task.

Wait for completion:

```racket
(define (await-sub-agent! id) → any/c)
```

Blocks until the sub-agent finishes, returns its result.

Check status without blocking:

```racket
(define (sub-agent-status id) → hash?)
```

Returns a hash with `'status` (`'running`, `'done`, or `'error`), `'profile`, and optionally `'result`.

---

## Extending with Custom Tools

Tools are defined in `src/tools/acp-tools.rkt`. Adding a new tool involves two steps.

### Step 1: Define the Schema

Add to the list returned by `make-acp-tools`:

```racket
(hash 'type "function"
      'function (hash 'name "my_custom_tool"
                      'description "Does something useful with the input"
                      'parameters (hash 'type "object"
                                        'properties 
                                        (hash 'input (hash 'type "string" 
                                                           'description "The input to process")
                                              'verbose (hash 'type "boolean"
                                                             'description "Enable verbose output"))
                                        'required '("input"))))
```

The schema uses JSON Schema format. Required parameters go in the `required` list.

### Step 2: Implement the Handler

Add a case to the `execute-acp-tool` match expression:

```racket
["my_custom_tool"
 (if (>= security-level 1)  ; Require at least level 1
     (my-tool-implementation (hash-ref args 'input)
                             (hash-ref args 'verbose #f))
     "Permission Denied: Requires Level 1.")]
```

The security check is important—decide what level your tool requires and enforce it.

### Example: A Code Metrics Tool

Here's a complete example adding a tool that counts lines of code:

```racket
;; Schema (in make-acp-tools)
(hash 'type "function"
      'function (hash 'name "count_lines"
                      'description "Count lines of code in a file"
                      'parameters (hash 'type "object"
                                        'properties 
                                        (hash 'path (hash 'type "string" 
                                                          'description "Path to file"))
                                        'required '("path"))))

;; Handler (in execute-acp-tool)
["count_lines"
 (if (>= security-level 1)
     (let ([content (file->string (hash-ref args 'path))])
       (define lines (length (string-split content "\n")))
       (define non-blank (length (filter (λ (s) (not (string=? (string-trim s) "")))
                                         (string-split content "\n"))))
       (format "Total lines: ~a\nNon-blank lines: ~a" lines non-blank))
     "Permission Denied")]
```

---

## Creating Custom Modules

Beyond using the built-in modules, you can create specialized ones for your domain.

### Basic Custom Module

```racket
(require "src/llm/dspy-core.rkt")

;; Define the signature
(define CodeReviewSig
  (signature CodeReview
    (in [code string?] [language string?])
    (out [issues string?] [severity string?] [suggestions string?])))

;; Create the module
(define code-reviewer
  (ChainOfThought CodeReviewSig
    #:instructions "Review the provided code for bugs, security issues, and style problems.
Think through each aspect systematically before providing your assessment."
    #:demos (list 
             (hash 'code "def foo(x): return x+1"
                   'language "python"
                   'issues "No input validation, no docstring"
                   'severity "low"
                   'suggestions "Add type hints and docstring"))))
```

### Using Custom Modules

```racket
(define ctx (ctx #:system "You are a code review expert." #:priority 'best))

(define result 
  (run-module code-reviewer ctx 
              (hash 'code "function add(a,b) { return a + b }"
                    'language "javascript")
              send!))

(when (RunResult-ok? result)
  (displayln (hash-ref (RunResult-outputs result) 'issues)))
```

### Compiling Custom Modules

To create an archive with optimized variants:

```racket
(require "src/llm/dspy-compile.rkt")

(define trainset
  (list (hash 'inputs (hash 'code "..." 'language "python")
              'expected (hash 'issues "..." 'severity "..." 'suggestions "..."))
        ;; more examples...
        ))

(define reviewer-archive
  (compile! code-reviewer ctx trainset send!
            #:k-demos 3    ; few-shot examples
            #:n-inst 5     ; instruction mutations per generation
            #:iters 3))    ; evolution generations

;; Now use the archive for priority-aware execution
(define result (run-module reviewer-archive ctx inputs send!))
```

---

## Integration Patterns

### Embedding in Larger Systems

To use Chrysalis Forge as a library:

```racket
#lang racket

(require chrysalis-forge/llm/dspy-core
         chrysalis-forge/llm/openai-client
         chrysalis-forge/stores/context-store)

;; Create a sender function
(define send! (make-openai-sender #:model "gpt-5.2"))

;; Load or create context
(define ctx (or (ctx-get-active)
                (ctx #:system "You are a helpful assistant.")))

;; Define and run a module
(define result (run-module my-module ctx inputs send!))
```

### Custom Scoring Functions

The default scoring balances accuracy, latency, and cost. For domain-specific needs, implement custom scoring:

```racket
(define (domain-score expected rr)
  (define outputs (RunResult-outputs rr))
  (define meta (RunResult-meta rr))
  
  ;; Domain-specific accuracy (e.g., medical diagnosis)
  (define accuracy 
    (if (critical-match? expected outputs) 10.0
        (if (partial-match? expected outputs) 5.0 0.0)))
  
  ;; Heavy penalty for false positives in critical domains
  (define fp-penalty
    (if (false-positive? expected outputs) 5.0 0.0))
  
  ;; Light weight on cost for critical applications
  (define cost-factor 0.1)
  (define cost-penalty (* cost-factor (hash-ref meta 'cost 0)))
  
  (max 0.0 (- accuracy fp-penalty cost-penalty)))
```

### Programmatic Evolution

Trigger evolution programmatically based on automated feedback:

```racket
(define (auto-evolve-from-failures failed-cases)
  (define feedback 
    (format "The system failed on these cases:\n~a\nPlease improve handling of these patterns."
            (string-join (map describe-failure failed-cases) "\n")))
  (gepa-evolve! feedback))

;; In a test harness:
(define failures (filter (λ (tc) (not (RunResult-ok? (run-test tc)))) test-cases))
(when (> (length failures) 5)
  (auto-evolve-from-failures failures))
```

This pattern enables continuous improvement: as failures accumulate, the system evolves to address them.
