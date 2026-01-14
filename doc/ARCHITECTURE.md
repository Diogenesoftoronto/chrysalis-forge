# Chrysalis Forge Architecture

The architecture of Chrysalis Forge reflects a fundamental conviction: that intelligent systems should be built from composable, evolvable components rather than monolithic black boxes. Every layer of the system is designed with three properties in mind—observability (you can see what's happening), evolvability (the system improves from experience), and safety (mistakes are bounded and recoverable).

This document walks through the architecture from the ground up, starting with the data layer and building toward the orchestration systems that tie everything together. Along the way, we'll examine actual code from the implementation, explaining not just what it does but why it's structured the way it is.

---

## The Layered Design

Chrysalis Forge is organized into four distinct layers, each with a clear responsibility:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              main.rkt                                   │
│                        Entry Point & REPL                               │
├─────────────────────────────────────────────────────────────────────────┤
│                            src/core/                                    │
│         Orchestration: decomposition, optimization, sub-agents          │
├─────────────────────────────────────────────────────────────────────────┤
│                            src/llm/                                     │
│          DSPy abstractions, model selection, pricing, client            │
├─────────────────────────────────────────────────────────────────────────┤
│                           src/stores/                                   │
│           Persistence: context, traces, evals, cache, vectors           │
├─────────────────────────────────────────────────────────────────────────┤
│                           src/tools/                                    │
│              25 built-in tools (file, git, jj, web, etc.)               │
└─────────────────────────────────────────────────────────────────────────┘
```

This layering isn't arbitrary. Dependencies flow downward: the core layer depends on LLM and stores, but not vice versa. Tools depend on nothing except external systems. This constraint makes the system easier to reason about and test—you can verify the LLM layer without involving orchestration, or test tools in isolation.

---

## The Stores Layer: Memory That Persists and Learns

At the foundation sits the stores layer, responsible for all persistent state. Unlike typical applications where persistence is an afterthought, Chrysalis treats storage as a first-class concern because learning requires memory.

### Context Store

The context store (`src/stores/context-store.rkt`) manages agent sessions. A `Ctx` structure captures everything about an agent's current state:

```racket
(struct Ctx (system memory tool-hints mode priority history compacted-summary) 
  #:transparent)
```

The **system** field holds the system prompt—the instructions that define the agent's behavior. This is the primary target of GEPA evolution. When the system evolves a better prompt, it gets stored here.

The **memory** field serves as a working scratchpad. Unlike history, which is append-only, memory can be freely overwritten. It's where the agent stores intermediate thoughts, extracted facts, or task-specific context that shouldn't pollute the main conversation.

The **tool-hints** field contains guidance about tool usage. Rather than relying on the LLM to rediscover how to use tools effectively, explicit hints encode best practices: "When searching code, use narrow path filters to avoid timeout."

The **mode** field gates tool access. Chrysalis defines four operational modes—`ask` (no filesystem access), `architect` (read-only analysis), `code` (full capabilities), and `semantic` (RDF knowledge graph operations). The mode determines which tools are available, implementing the principle of least privilege.

The **priority** field specifies the performance profile. This can be a symbol (`'fast`, `'cheap`, `'best`) or a natural language string ("I need accuracy but I'm on a budget"). The priority propagates through the entire execution stack, influencing model selection, decomposition limits, and module choice.

Contexts are versioned with timestamps when evolved, enabling historical analysis. You can ask: "How has this agent's system prompt changed over the past week? What feedback drove those changes?"

### Eval Store

The eval store (`src/stores/eval-store.rkt`) tracks task outcomes by profile. Every time a sub-agent completes a task, the result is logged:

```racket
(log-eval! profile-name task-type success? duration-ms cost)
```

This data feeds the learning loop. The `suggest-profile` function examines historical performance to recommend which profile suits a given task type:

```racket
(define (suggest-profile task-type)
  (define stats (get-profile-stats))
  ;; Find profile with highest success rate for this task type
  ...)
```

Over time, the system learns that "researcher" profiles excel at code exploration while "editor" profiles are better for modifications. This learning is organic—it emerges from usage rather than explicit training.

### Trace Store

The trace store (`src/stores/trace-store.rkt`) logs every operation to `~/.chrysalis/traces.jsonl`. Each entry captures:

- Timestamp
- Operation type (tool call, LLM invocation, decomposition step)
- Inputs and outputs
- Duration and cost
- Success or failure

This audit trail serves multiple purposes. Debugging becomes tractable—when something goes wrong, you can reconstruct exactly what happened. Performance analysis reveals bottlenecks. And the traces themselves become training data for future optimization.

### Decomposition Archive

The decomposition archive (`src/stores/decomp-archive.rkt`) stores successful decomposition patterns. When a complex task is decomposed effectively—completing under budget with high success rate—the decomposition strategy is archived.

Future similar tasks can retrieve proven strategies via KNN search, bootstrapping from past success rather than reasoning from scratch. This is MAP-Elites applied to decomposition: maintain diverse high-performing patterns, select based on task phenotype.

---

## The LLM Layer: Typed Interactions with Language Models

Above the stores sits the LLM layer, which provides typed abstractions for language model interaction. The key insight, borrowed from Stanford's DSPy, is that LLM calls should be treated as function calls with explicit signatures.

### Signatures and Modules

A `Signature` declares input and output fields with type predicates:

```racket
(struct SigField (name pred) #:transparent)
(struct Signature (name ins outs) #:transparent)

;; Example: An optimizer that takes instructions and failures, produces new instructions
(define OptSig 
  (signature Opt 
    (in [inst string?] [fails string?]) 
    (out [thought string?] [new_inst string?])))
```

The predicates (`string?`, `number?`, etc.) enable validation. If a response doesn't parse correctly or violates type expectations, that's detected immediately rather than propagating as subtle corruption.

A `Module` wraps a signature with execution strategy:

```racket
(struct Module (id sig strategy instructions demos params) #:transparent)
```

The **strategy** is either `'predict` (direct completion) or `'cot` (chain-of-thought reasoning). Chain-of-thought modules are instructed to reason step-by-step before producing output, which often improves accuracy on complex tasks at the cost of additional tokens.

The **instructions** field contains the core prompt text. This is what GEPA evolves.

The **demos** field holds few-shot examples. Each demo is a hash mapping field names to values, showing the model what good input-output pairs look like.

The **params** hash contains model parameters—temperature, max tokens, and similar settings.

### Module Archives

A `ModuleArchive` collects multiple module variants indexed by phenotype:

```racket
(struct ModuleArchive (id sig archive point-cloud default-id) #:transparent)
```

The **archive** is a hash from bin keys to (score, module) pairs. Bin keys are lists like `'(cheap fast compact)` describing which phenotype bins the module occupies. This discrete structure enables fast lookup for keyword priorities.

The **point-cloud** is a list of (phenotype, module) pairs for geometric search. When the user specifies a natural language priority, KNN search finds the nearest module in continuous phenotype space.

This dual representation—discrete bins and continuous cloud—bridges two usage patterns. Simple cases ("give me the cheap one") hit the fast path. Complex cases ("balance cost and accuracy, slightly favor speed") use geometric interpolation.

### The Compilation Process

The `compile!` function in `dspy-compile.rkt` implements the MAP-Elites optimization loop:

```racket
(define (compile! m ctx trainset send! 
                 #:k-demos [k 3] 
                 #:n-inst [n 5] 
                 #:iters [iters 3]
                 #:use-meta-optimizer? [use-meta? #t])
  ;; 1. Bootstrap few-shot examples
  (define demos (bootstrap-fewshot trainset #:k k))
  (define m0 (module-set-demos m demos))
  
  ;; 2. Initialize archive and point cloud
  (define archive (make-hash))
  (define point-cloud '())
  
  ;; 3. Seed with instruction mutations
  (define seeds (default-instruction-mutations (Module-instructions m0)))
  ;; ... evaluate seeds, establish relative thresholds ...
  
  ;; 4. Evolutionary loop
  (for ([i (range iters)] #:when use-meta?)
    ;; Select random elite as parent
    (define parent-key (list-ref elite-keys (random (length elite-keys))))
    (define parent-mod (cdr (hash-ref archive parent-key)))
    
    ;; Generate children via meta-optimization
    (for ([j (range n)])
      (let-values ([(child-mod thought) (meta-optimize-module parent-mod ctx trainset send!)])
        (let-values ([(score p-key res-list) (evaluate-module child-mod)])
          (update-archive! child-mod score p-key res-list)))))
  
  ;; 5. Return ModuleArchive
  (ModuleArchive (Module-id m0) (Module-sig m0) archive point-cloud best-key))
```

The process begins by bootstrapping few-shot examples from the training set. These examples anchor the module's behavior before optimization begins.

Next, instruction mutations create initial diversity: the base instructions plus variations ("Be concise", "Think step-by-step", "Output STRICT JSON"). These seeds are evaluated and archived.

The evolutionary loop then iterates. Each generation selects a random elite as parent, applies meta-optimization to generate children, evaluates them, and updates the archive. The meta-optimizer uses natural language reflection—examining the parent's failures and proposing improvements.

The result is a `ModuleArchive` containing diverse, high-performing module variants ready for priority-based selection.

### Phenotype Extraction and Binning

A key detail is how phenotypes are extracted from execution results:

```racket
(define (extract-phenotype rr score)
  (define meta (RunResult-meta rr))
  (define model (hash-ref meta 'model "unknown"))
  (define p-tokens (hash-ref meta 'prompt_tokens 0))
  (define c-tokens (hash-ref meta 'completion_tokens 0))
  (define cost (calculate-cost model p-tokens c-tokens))
  (define lat (hash-ref meta 'elapsed_ms 0))
  (define total-tokens (+ p-tokens c-tokens))
  (Phenotype score lat cost total-tokens))
```

The phenotype captures not just the score (accuracy) but the resource consumption—latency, cost, total tokens. These dimensions are what enable trade-off selection.

Binning uses relative thresholds established from the seed population:

```racket
(define (get-phenotype-key rr [t-cost 0.0] [t-lat 0.0] [t-usage 0.0])
  ;; ... extract metrics ...
  (list (if (< cost t-cost) 'cheap 'premium)
        (if (< lat t-lat) 'fast 'slow)
        (if (< total-tokens t-usage) 'compact 'verbose)))
```

Thresholds are set to medians, so bins represent "below median" vs "above median" on each dimension. This relative binning adapts to the specific task and model—what counts as "cheap" depends on context.

---

## The Core Layer: Orchestration and Intelligence

The core layer contains the high-level orchestration systems: geometric decomposition, prompt evolution, and sub-agent management.

### Geometric Decomposition

The decomposition system in `geometric-decomposition.rkt` implements MAKER-inspired task breakdown with self-regulation. The central data structures capture decomposition state:

```racket
(struct DecompositionPhenotype 
  (depth breadth accumulated-cost context-size success-rate) 
  #:transparent)

(struct DecompositionState 
  (root-task task-type priority tree phenotype limits checkpoints steps-taken meta) 
  #:transparent #:mutable)
```

The phenotype tracks five dimensions as decomposition proceeds:

**Depth** measures how many levels of subtasks exist. Deeper decomposition provides finer granularity but increases overhead.

**Breadth** measures maximum parallel fan-out. Wide decomposition enables parallelism but strains resources.

**Accumulated-cost** tracks total expenditure across all LLM calls. Each decomposition step and subtask execution adds to this.

**Context-size** monitors peak context tokens. Large contexts slow execution and degrade quality.

**Success-rate** tracks the fraction of subtasks that complete successfully. A falling success rate suggests the decomposition strategy is producing subtasks the model can't handle.

Limits are set based on priority:

```racket
(define (limits-for-priority priority budget context-limit)
  (match priority
    ['critical
     (DecompositionLimits 10 20 (* budget 2.0) (* context-limit 1.5) 0.6)]
    ['high
     (DecompositionLimits 8 15 (* budget 1.5) context-limit 0.7)]
    ['normal
     (DecompositionLimits 6 10 budget (* context-limit 0.8) 0.75)]
    ['low
     (DecompositionLimits 4 6 (* budget 0.5) (* context-limit 0.5) 0.8)]
    [_ (DecompositionLimits 6 10 budget context-limit 0.75)]))
```

Critical tasks get generous limits—deep decomposition, wide parallelism, extra budget. Low-priority tasks are constrained to be cheap and fast.

The explosion detector monitors all dimensions:

```racket
(define (detect-explosion phenotype limits)
  (cond
    [(> (DecompositionPhenotype-depth phenotype)
        (DecompositionLimits-max-depth limits))
     'depth]
    [(> (DecompositionPhenotype-breadth phenotype)
        (DecompositionLimits-max-breadth limits))
     'breadth]
    [(> (DecompositionPhenotype-accumulated-cost phenotype)
        (DecompositionLimits-max-cost limits))
     'cost]
    [(> (DecompositionPhenotype-context-size phenotype)
        (DecompositionLimits-max-context limits))
     'context]
    [(< (DecompositionPhenotype-success-rate phenotype)
        (DecompositionLimits-min-success-rate limits))
     'low-success]
    [else #f]))
```

When any dimension exceeds its limit, an explosion is detected. The system doesn't simply fail—it rolls back to a checkpoint and tries an alternative approach.

The checkpoint mechanism captures tree structure and phenotype at key points:

```racket
(define (checkpoint! state reason)
  (define snap (snapshot-tree (DecompositionState-tree state)))
  (define cp (DecompositionCheckpoint snap
                                       (DecompositionState-phenotype state)
                                       (DecompositionState-steps-taken state)
                                       reason))
  (set-DecompositionState-checkpoints! state 
                                        (cons cp (DecompositionState-checkpoints state)))
  state)
```

Checkpoints are created before risky operations—branching into subtasks, attempting expensive LLM calls. If the operation leads to explosion, `rollback!` restores the previous state and the system can try a different path.

### Sub-Agent Management

The sub-agent system in `sub-agent.rkt` enables parallel execution with focused tool profiles. The key insight is that not every subtask needs access to all tools—in fact, restricting tools improves focus and safety.

Four profiles are defined:

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

The **editor** profile focuses on file modification. A sub-agent with this profile can read, write, and patch files but can't search the web or run git commands.

The **researcher** profile focuses on information gathering. It can read files and search but can't modify anything.

The **vcs** profile focuses on version control. It has access to both git and Jujutsu (jj) commands, enabling sophisticated repository operations.

Spawning a sub-agent creates a new thread with filtered tools:

```racket
(define (spawn-sub-agent! prompt run-fn #:context [context ""] #:profile [profile 'all])
  (set! agent-counter (add1 agent-counter))
  (define id (format "task-~a" agent-counter))
  (define result-channel (make-async-channel))
  (define tools-filter (get-tool-profile profile))
  
  (define t 
    (thread
     (λ ()
       (with-handlers ([exn:fail? (λ (e) 
                                    (async-channel-put result-channel 
                                                       (hash 'status 'error 
                                                             'error (exn-message e))))])
         (define result (run-fn prompt context tools-filter))
         (async-channel-put result-channel (hash 'status 'done 'result result))))))
  
  (hash-set! SUB-AGENTS id 
             (hash 'thread t 
                   'channel result-channel 
                   'status 'running 
                   'prompt prompt
                   'profile profile
                   'result #f))
  id)
```

The `run-fn` parameter is a function that executes the prompt with the given context and tool filter. By passing this as a parameter rather than hard-coding it, the sub-agent system remains flexible—different execution strategies can be plugged in.

Results flow back through async channels, enabling non-blocking status checks:

```racket
(define (sub-agent-status id)
  (define agent (hash-ref SUB-AGENTS id #f))
  (unless agent (error 'task_status "Unknown task ID: ~a" id))
  
  (define t (hash-ref agent 'thread))
  (define alive? (thread-running? t))
  
  (cond
    [(not alive?)
     ;; Thread finished, get result
     (define result (async-channel-try-get (hash-ref agent 'channel)))
     ;; ... return status with result ...]
    [else
     (hash 'status 'running 
           'prompt (hash-ref agent 'prompt) 
           'profile (hash-ref agent 'profile))]))
```

This enables progress monitoring without blocking. The main agent can spawn several sub-agents, periodically check their status, and collect results as they complete.

---

## The Tools Layer: Capabilities and Safety

The tools layer (`src/tools/acp-tools.rkt`) defines the 25 built-in tools that give the agent capabilities beyond pure language generation. Tools are the bridge between the LLM's reasoning and the external world.

Each tool is defined with a JSON schema describing its parameters:

```racket
(hash 'type "function"
      'function (hash 'name "write_file"
                      'description "Write content to a file, creating it if needed"
                      'parameters (hash 'type "object"
                                        'properties 
                                        (hash 'path (hash 'type "string" 
                                                          'description "File path")
                                              'content (hash 'type "string" 
                                                             'description "Content to write"))
                                        'required '("path" "content"))))
```

This schema is passed to the LLM as part of the tools specification. The model learns which tools are available and what arguments they expect.

Tool execution is gated by security level:

```racket
(define (execute-acp-tool name args security-level)
  (match name
    ["read_file" 
     (if (>= security-level 1)
         (file->string (hash-ref args 'path))
         "Permission Denied: Requires Level 1.")]
    
    ["write_file"
     (if (and (>= security-level 2) 
              (confirm-risk! "WRITE" (hash-ref args 'path)))
         (begin
           (display-to-file (hash-ref args 'content) 
                            (hash-ref args 'path) 
                            #:exists 'replace)
           "File written successfully.")
         "Permission Denied: Requires Level 2.")]
    
    ["run_term" 
     (if (>= security-level 3) 
         ... 
         "Permission Denied: Requires Level 3.")]
    ...))
```

Security levels form a hierarchy:

- **Level 0** (read-only): No execution, only conversation
- **Level 1** (sandbox): Read files, safe operations
- **Level 2** (limited I/O): Write files with confirmation
- **Level 3** (full): Shell access with approval

The `confirm-risk!` function implements user approval for sensitive operations. At level 2, writes prompt for confirmation. At level 3 ("god mode"), confirmation is skipped but operations are still logged.

An optional LLM judge provides an additional safety layer:

```racket
(define (evaluate-safety action content)
  (unless (llm-judge-param) (values #t ""))
  
  (define sender (make-openai-sender #:model (llm-judge-model-param)))
  (define prompt 
    (format "You are a Security Auditor. A user or agent is attempting:
ACTION: ~a
CONTENT: ~a

Is this safe? Reply [SAFE] or [UNSAFE] with explanation." action content))
  (define-values (ok? res usage) (sender prompt))
  (if (and ok? (string-contains? res "[SAFE]"))
      (values #t res)
      (values #f res)))
```

When enabled, this LLM-as-judge reviews potentially dangerous operations before they execute. It's not foolproof, but it catches obvious problems like "delete all files" or "send credentials to external URL."

---

## The Entry Point: Tying It All Together

The `main.rkt` file ties all layers together, implementing the REPL and command-line interface. The core execution loop:

1. Load or create context from the context store
2. Parse user input (prompt, commands, configuration)
3. If the input is a command (starts with `/`), handle it directly
4. Otherwise, invoke the LLM with the current context and tools
5. Process tool calls, executing them with appropriate security checks
6. Log results to trace and eval stores
7. Update context with new history
8. Repeat

The streaming response handler provides real-time output while accumulating tool calls:

```racket
(define (responses-run-turn/stream messages tools send-delta! finish!)
  ;; Stream response deltas to the user
  ;; Accumulate tool calls
  ;; On completion, return structured result
  ...)
```

This streaming approach is essential for user experience. Rather than waiting for the entire response, users see output as it's generated, with tool calls processed as they complete.

---

## Design Principles

Several principles guided the architecture:

**Separation of Concerns**: Each layer has a clear responsibility. Stores handle persistence. LLM handles model interaction. Core handles orchestration. Tools handle capabilities. This separation makes the system easier to understand, test, and modify.

**Explicit State**: All state is captured in explicit data structures—`Ctx`, `DecompositionState`, `ModuleArchive`. There's no hidden global state that makes reasoning difficult. Every function's behavior is determined by its inputs.

**Fail-Safe Defaults**: When something goes wrong, the system degrades gracefully. Unknown priorities fall back to defaults. Failed decomposition triggers rollback. Missing tools return informative errors rather than crashing.

**Observable Execution**: Everything is logged. Traces capture every operation. Evals track every outcome. This observability is what enables learning—you can't improve what you can't measure.

**Composable Components**: Modules, tools, and profiles are designed for composition. New tools can be added without modifying existing ones. New profiles can be defined by listing tool names. New modules can be created by combining signatures with strategies.

These principles reflect the conviction that building reliable AI systems requires engineering discipline, not just bigger models. Chrysalis Forge is infrastructure for that discipline.
