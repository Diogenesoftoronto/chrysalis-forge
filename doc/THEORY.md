# Theoretical Foundations of Chrysalis Forge

Chrysalis Forge emerges from a confluence of research threads that have, in recent years, begun to reshape how we think about building intelligent systems. Rather than treating large language models as monolithic oracles to be prompted and hoped for the best, this framework treats them as components in a larger evolutionary and geometric system—one that learns, adapts, and improves through principled mechanisms borrowed from evolutionary computation, differential geometry, and distributed systems theory.

This document is intended for researchers, graduate students, and developers who want to understand not just *what* Chrysalis Forge does, but *why* it does it that way. We trace each major component back to its theoretical roots, quote the key insights from the foundational papers, and show how these ideas manifest in the Racket implementation.

---

## The Problem of Prompt Optimization

Before diving into specific techniques, it's worth understanding the problem space. Large language models are remarkably sensitive to how they're prompted. The difference between a mediocre and an excellent result often comes down to subtle variations in instruction phrasing, the choice and ordering of few-shot examples, or the structural scaffolding around the task. This sensitivity creates an optimization problem: given a task, how do we find the prompt configuration that maximizes performance?

Traditional approaches have treated this as a reinforcement learning problem. Run the prompt, observe whether it succeeded or failed, use that binary signal to update. But as the GEPA authors observe, this approach squanders the richest resource we have—the model's own ability to reason about *why* something failed.

---

## GEPA: Learning in the Space of Language

The GEPA paper (Agrawal et al., 2025) makes a provocative claim that cuts against the prevailing wisdom in LLM optimization:

> "We argue that the interpretable nature of *language* can often provide a much richer learning medium for LLMs, compared with policy gradients derived from sparse, scalar rewards."

This insight is deceptively simple but has profound implications. When a prompt fails, the failure trace—the reasoning steps, the tool calls, the intermediate outputs—contains far more information than a binary success/failure signal. A model that can reflect on this trace in natural language can diagnose specific problems ("I consistently missed edge cases involving negative numbers") and propose targeted fixes.

The GEPA algorithm operationalizes this insight through what the authors call "reflective prompt evolution":

> "Given any AI system containing one or more LLM prompts, GEPA samples system-level trajectories (e.g., reasoning, tool calls, and tool outputs) and reflects on them in natural language to diagnose problems, propose and test prompt updates, and combine complementary lessons from the Pareto frontier of its own attempts."

The key innovation is the Pareto frontier. Rather than greedily accepting any improvement, GEPA maintains a population of prompts that represent different trade-offs between objectives (accuracy, cost, latency). When a new prompt variant is proposed, it's evaluated against the frontier: if it advances on any objective without regressing on others, it joins the population. This prevents the optimizer from collapsing onto a single local optimum and maintains diversity that proves valuable when requirements change.

The results are striking: GEPA outperforms GRPO (Group Relative Policy Optimization) by 10-20% while using up to 35× fewer rollouts. This sample efficiency comes directly from the richness of natural language feedback compared to scalar rewards.

### Implementation in Chrysalis Forge

The [`optimizer-gepa.rkt`](../src/core/optimizer-gepa.rkt) module implements this reflective evolution loop. The core function is deceptively simple because the complexity lives in the meta-prompt that guides the optimizer LLM:

```racket
(define (gepa-evolve! feedback [model "gpt-5.2"])
  (check-usage!)
  (define active (ctx-get-active))
  (define sender (make-openai-sender #:model model))
  (define-values (ok? res usage) 
    (sender (format "~a\nCURRENT: ~a\nFEEDBACK: ~a" 
                    (get-meta) (Ctx-system active) feedback)))
  (if ok?
      (let ([new-sys (hash-ref (string->jsexpr res) 'new_system_prompt)])
        (log-cost-analysis model usage)
        (save-ctx! (let ([db (load-ctx)]) 
                     (hash-set db 'items 
                       (hash-set (hash-ref db 'items) 
                                 (format "evo_~a" (current-seconds)) 
                                 (struct-copy Ctx active [system new-sys])))))
        "Context Evolved.")
      "Evolution Failed."))
```

The `get-meta` function returns the meta-prompt—the instructions that tell the optimizer *how* to optimize. This is itself subject to evolution through `gepa-meta-evolve!`, creating a recursive self-improvement loop. The evolved contexts are versioned with timestamps, maintaining a history that could be analyzed to understand the evolution trajectory.

What makes this implementation particularly elegant is how it separates concerns: the feedback comes from the user or from automated evaluation; the meta-prompt encodes optimization strategy; the sender handles the mechanics of LLM interaction. This separation allows each component to evolve independently.

---

## MAP-Elites: Illuminating the Space of Possible Solutions

While GEPA handles the *evolution* of prompts, we need a complementary mechanism for *organizing* the population of evolved variants. This is where MAP-Elites (Mouret & Clune, 2015) enters the picture.

The central insight of MAP-Elites is that optimization should produce not a single solution, but a *map* of solutions across a behavioral space:

> "Many fields use search algorithms, which automatically explore a search space to find high-performing solutions... The goal of search algorithms has traditionally been to return the single highest-performing solution in a search space. Here we describe a new, fundamentally different type of algorithm that is more useful because it provides a holistic view of how high-performing solutions are distributed throughout a search space."

Traditional optimization is like searching for the highest peak in a mountain range. MAP-Elites is like creating a topographic map that shows the highest point in every grid cell. This distinction matters because different situations call for different trade-offs. Sometimes you need the fastest response; sometimes you need the cheapest; sometimes accuracy trumps everything.

The algorithm works by discretizing a behavioral space (what MAP-Elites calls the "phenotype space") into bins, then maintaining the best-performing solution found for each bin. When a new solution is generated, it competes only against other solutions in its bin—local competition rather than global. This local competition is what enables the algorithm to maintain diversity while still selecting for quality.

### The Phenotype Space in Chrysalis

In Chrysalis Forge, we use a four-dimensional phenotype space defined in [`dspy-core.rkt`](../src/llm/dspy-core.rkt):

```racket
(struct Phenotype (accuracy latency cost usage) #:transparent)
```

These dimensions capture the fundamental trade-offs in LLM-based systems:

**Accuracy** measures correctness. A prompt that produces the right answer scores high; one that hallucinates scores low. This is the dimension users care about most, but it's not the only one that matters.

**Latency** captures response time. Some applications (voice assistants, real-time coding) demand speed; others (batch processing, research) can tolerate slower responses. A high-accuracy prompt that takes 30 seconds isn't useful for interactive applications.

**Cost** reflects token expenditure. With API-based LLMs charging per token, a prompt that achieves 95% accuracy using 10× the tokens of one achieving 90% may not be the better choice. This dimension enables cost-conscious operation.

**Usage** measures output verbosity. Sometimes you want concise answers; sometimes you want thorough explanations. This dimension captures that preference.

The `ModuleArchive` structure maintains both discrete bins (for backward-compatible keyword selection) and a continuous point cloud (for geometric KNN selection):

```racket
(struct ModuleArchive (id sig archive point-cloud default-id) #:transparent)
```

The dual representation is key to flexibility. The `archive` hash maps bin keys to (score, module) pairs, enabling fast lookup when the user specifies a keyword like "fast" or "cheap". The `point-cloud` list of (phenotype, module) pairs enables smooth interpolation when the user provides natural language like "I need something reasonably fast but accuracy matters more."

---

## Geometric Selection: From Keywords to Manifolds

The MAP-Elites archive gives us a collection of elite solutions, but we still need a mechanism for selecting among them based on user intent. This is where geometric intuition becomes valuable.

The "Attention Is Not What You Need" paper (Zhang, 2025) proposes a radical rethinking of the attention mechanism through the lens of differential geometry:

> "We propose an attention-free architecture based on Grassmann flows. Instead of forming an L by L attention matrix, our Causal Grassmann layer (i) linearly reduces token states, (ii) encodes local token pairs as two-dimensional subspaces on a Grassmann manifold via Plücker coordinates, and (iii) fuses these geometric features back into the hidden states through gated mixing."

While Chrysalis Forge doesn't implement Grassmann flows at the neural architecture level (that would require custom model training), it adopts the geometric philosophy for selection. The phenotype space is treated as a continuous manifold, and selection is performed via K-nearest-neighbor search in this space.

The [`dspy-selector.rkt`](../src/llm/dspy-selector.rkt) module implements this geometric selection:

```racket
(define (phenotype-distance p1 p2)
  (sqrt (+ (expt (- (Phenotype-accuracy p1) (Phenotype-accuracy p2)) 2)
           (expt (- (Phenotype-latency p1) (Phenotype-latency p2)) 2)
           (expt (- (Phenotype-cost p1) (Phenotype-cost p2)) 2)
           (expt (- (Phenotype-usage p1) (Phenotype-usage p2)) 2))))

(define (normalize-phenotype pheno mins maxs)
  (define (safe-norm v lo hi) 
    (if (= lo hi) 0.5 (/ (- v lo) (- hi lo))))
  (Phenotype (safe-norm (Phenotype-accuracy pheno) (first mins) (first maxs))
             (safe-norm (Phenotype-latency pheno) (second mins) (second maxs))
             (safe-norm (Phenotype-cost pheno) (third mins) (third maxs))
             (safe-norm (Phenotype-usage pheno) (fourth mins) (fourth maxs))))
```

The normalization step is crucial. Raw phenotype values have different scales—accuracy might range from 0-10, latency from 100-10000ms, cost from 0.001-0.1 dollars. Without normalization, the distance metric would be dominated by whichever dimension has the largest absolute values. By normalizing to [0,1], we ensure each dimension contributes proportionally.

The `select-elite` function performs KNN search (with K=1) in the normalized space:

```racket
(define (select-elite archive target)
  (define cloud (ModuleArchive-point-cloud archive))
  (when (null? cloud)
    (error "Cannot select elite: point cloud is empty"))
  
  (define-values (mins maxs) (find-bounds cloud))
  (define target-norm (normalize-phenotype target mins maxs))
  
  (define scored
    (for/list ([entry cloud])
      (define pheno (car entry))
      (define mod (cdr entry))
      (define pheno-norm (normalize-phenotype pheno mins maxs))
      (cons (phenotype-distance target-norm pheno-norm) mod)))
  
  (define sorted (sort scored < #:key car))
  (cdr (first sorted)))
```

This geometric approach enables something powerful: natural language priority specification. The `text->vector` function maps natural language descriptions to target phenotypes, either through a keyword fast-path or through LLM interpretation:

```racket
(define KEYWORD-MAP
  (hash "fast"     (Phenotype 5.0 0.0 0.5 0.5)   ; Low latency
        "cheap"    (Phenotype 5.0 0.5 0.0 0.5)   ; Low cost  
        "accurate" (Phenotype 10.0 0.5 0.5 0.5)  ; High accuracy
        "concise"  (Phenotype 5.0 0.5 0.5 0.0)   ; Low usage
        "verbose"  (Phenotype 5.0 0.5 0.5 1.0))) ; High usage

(define (text->vector text [send! #f])
  (define lower (string-downcase text))
  (define matched
    (for/first ([(kw pheno) (in-hash KEYWORD-MAP)]
                #:when (string-contains? lower kw))
      pheno))
  (cond
    [matched matched]
    [send!
     ;; Use LLM to interpret novel descriptions
     (define prompt 
       (format "The user wants an agent with priority: \"~a\"
Return JSON with accuracy, speed, cost, brevity (0.0-1.0 scale)." text))
     (define-values (ok? raw meta) (send! prompt))
     (if ok?
         (let ([parsed (string->jsexpr raw)])
           (Phenotype (* 10.0 (hash-ref parsed 'accuracy 0.5))
                      (- 1.0 (hash-ref parsed 'speed 0.5))
                      (- 1.0 (hash-ref parsed 'cost 0.5))
                      (- 1.0 (hash-ref parsed 'brevity 0.5))))
         (Phenotype 5.0 0.5 0.5 0.5))]
    [else (Phenotype 5.0 0.5 0.5 0.5)]))
```

A user saying "I'm broke but need precision" triggers the LLM interpretation path, which returns something like `{accuracy: 0.9, speed: 0.3, cost: 0.1, brevity: 0.5}`. This gets transformed into a target phenotype emphasizing accuracy and low cost, which then drives KNN selection to find the closest elite in the archive.

---

## MAKER: Achieving Reliability Through Decomposition

The preceding techniques—GEPA, MAP-Elites, geometric selection—address how to *optimize* and *select* prompts. But even the best prompt will occasionally fail, and for some applications, occasional failure is unacceptable. The MAKER paper (Cognizant AI Lab, 2025) addresses this reliability problem through a radical approach: extreme decomposition.

> "LLMs have achieved remarkable breakthroughs in reasoning, insights, and tool use, but chaining these abilities into extended processes at the scale of those routinely executed by humans, organizations, and societies has remained out of reach. The models have a persistent error rate that prevents scale-up."

The key insight is that reliability compounds multiplicatively. If each step has a 1% error rate, a 100-step task will fail more than 63% of the time. A 1000-step task will almost certainly fail. The MAKER solution is three-fold:

**Maximal Agentic Decomposition (MAD)**: Decompose tasks into the smallest possible subtasks, each handled by a focused "microagent" with minimal context. This isolation prevents errors from propagating and makes each subtask easier to verify.

**First-to-K Voting**: Run multiple agents on the same subtask in parallel, accepting the first answer to achieve K more votes than any alternative. This provides rapid consensus without requiring all agents to complete.

**Red-flagging**: Automatically discard responses that show signs of unreliability—length explosion, format violations, confidence hedging, or repetitive loops.

The results are remarkable:

> "This paper describes MAKER, the first system that successfully solves a task with over one million LLM steps with zero errors, and, in principle, scales far beyond this level."

### Geometric Decomposition in Chrysalis

Chrysalis Forge implements MAKER-inspired decomposition in [`geometric-decomposition.rkt`](../src/core/geometric-decomposition.rkt). The module defines a decomposition phenotype that extends the module phenotype with task-specific dimensions:

```racket
(struct DecompositionPhenotype 
  (depth breadth accumulated-cost context-size success-rate) 
  #:transparent)

(struct DecompositionLimits 
  (max-depth max-breadth max-cost max-context min-success-rate) 
  #:transparent)
```

The **depth** dimension tracks how deeply the task has been decomposed—how many levels of subtasks. Excessive depth suggests the decomposition strategy is wrong or the task is genuinely intractable.

The **breadth** dimension measures the maximum parallel fan-out at any level. Too much breadth strains resources and can indicate poor problem decomposition.

The **accumulated-cost** tracks total expenditure across all subtasks. Even if each subtask is cheap, thousands of them add up.

The **context-size** monitors peak context tokens across active branches. Context limits are real constraints that must be respected.

The **success-rate** tracks the fraction of subtasks that succeed. A dropping success rate suggests the decomposition strategy is producing subtasks the model can't handle.

The explosion detection mechanism monitors all these dimensions against limits that vary by priority:

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
    [_
     (DecompositionLimits 6 10 budget context-limit 0.75)]))

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

When an explosion is detected, the system doesn't simply fail. It rolls back to the most recent checkpoint and tries an alternative approach:

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

(define (rollback! state)
  (define cps (DecompositionState-checkpoints state))
  (when (null? cps)
    (error 'rollback! "No checkpoints available"))
  (define cp (car cps))
  (restore-tree! (DecompositionState-tree state) 
                 (DecompositionCheckpoint-tree-snapshot cp))
  (set-DecompositionState-phenotype! state (DecompositionCheckpoint-phenotype cp))
  (set-DecompositionState-steps-taken! state (DecompositionCheckpoint-step-index cp))
  (set-DecompositionState-checkpoints! state (cdr cps))
  state)
```

This checkpoint/rollback mechanism is what allows Chrysalis to explore multiple decomposition strategies without committing irrevocably to any one approach. If a strategy leads to explosion, the system can backtrack and try something else.

---

## Temporal Knowledge and Memory

The preceding techniques handle individual tasks, but real agents operate over extended periods, accumulating knowledge and experience. The Zep paper (Rasmussen et al., 2025) addresses this temporal dimension:

> "We introduce Zep, a novel memory layer service for AI agents... Unlike existing retrieval-augmented generation (RAG) frameworks for large language model (LLM)-based agents are limited to static document retrieval, enterprise applications demand dynamic knowledge integration from diverse sources including ongoing conversations and business data."

The key innovation is **bi-temporal tracking**: distinguishing between when an event occurred and when the system learned about it. This distinction matters for reasoning about change. If a user says "I switched from Adidas to Nike" today, the system needs to know that "prefers Adidas" was true until today but is now false, and that this change was recorded today.

Chrysalis Forge doesn't implement a full temporal knowledge graph (that would be a substantial subsystem), but it applies the temporal principle through its store architecture:

The **context store** (`context-store.rkt`) maintains versioned contexts with timestamps, enabling point-in-time recovery and evolution analysis.

The **trace store** (`trace-store.rkt`) logs all operations with timing information, creating an audit trail for debugging and learning.

The **eval store** (`eval-store.rkt`) tracks task outcomes by profile over time, enabling the system to learn which configurations work best for which task types.

---

## Recursive Language Models and Sub-Agents

The final piece of the theoretical puzzle addresses context management. Even with the largest context windows, there are tasks that require processing more information than fits. The Recursive Language Models paper (Zhang et al., 2025) proposes an elegant solution:

> "We study allowing large language models (LLMs) to process arbitrarily long prompts through the lens of inference-time scaling. We propose Recursive Language Models (RLMs), a general inference strategy that treats long prompts as part of an external environment and allows the LLM to programmatically examine, decompose, and recursively call itself over snippets of the prompt."

Rather than forcing the model to process everything at once, RLMs give the model control over what it examines. The model can peek at portions of the context, grep for relevant sections, and spawn recursive sub-calls to process chunks—all while keeping its own context window lean.

Chrysalis Forge implements this through the sub-agent system in [`sub-agent.rkt`](../src/core/sub-agent.rkt). Sub-agents are spawned with specific **profiles** that determine their tool access:

- **editor**: File operations (read, write, patch, diff)
- **researcher**: Search operations (grep, web search, file reading)
- **vcs**: Version control (git and jujutsu operations)
- **all**: Full toolkit (used sparingly)

This profile system serves two purposes. First, it reduces the tool surface area that each sub-agent must reason about, improving focus and reducing confusion. Second, it provides a security boundary—a researcher sub-agent can't accidentally modify files.

The sub-agent architecture enables parallel execution of independent subtasks. When a complex task decomposes into researching multiple files, an editor sub-agent and several researcher sub-agents can work simultaneously, with results merged when all complete.

---

## The DSPy Programming Model

Underlying all these techniques is a programming model borrowed from Stanford's DSPy framework. The core insight is that LLM interactions should be treated as typed modules with explicit signatures:

```racket
(struct SigField (name pred) #:transparent)
(struct Signature (name ins outs) #:transparent)
(struct Module (id sig strategy instructions demos params) #:transparent)
```

A `Signature` declares what goes in and what comes out. A `Module` wraps a signature with execution strategy (direct prediction vs. chain-of-thought reasoning), instructions, few-shot demonstrations, and parameters.

This structure enables several things that ad-hoc prompting doesn't:

**Composability**: Modules can be chained, with the outputs of one becoming inputs to another. Type checking (via predicates) catches mismatches.

**Optimization**: Because the signature is explicit, an optimizer knows exactly what success looks like. It can generate training examples, mutate instructions, and evaluate results against expected outputs.

**Abstraction**: Users interact with modules, not prompts. The prompt is an implementation detail that can be evolved without changing the interface.

The `run-module` function handles execution:

```racket
(define (run-module m ctx inputs send! #:trace [tr #f] #:cache? [cache? #t])
  (define target-m 
    (cond
      [(Module? m) m]
      [(ModuleArchive? m)
       (define prio (Ctx-priority ctx))
       (cond
         ;; Symbol priority: use keyword mapping
         [(and (symbol? prio) (member prio '(cheap fast compact verbose)))
          (define matching-key 
            (for/first ([(k v) (in-hash (ModuleArchive-archive m))]
                        #:when (member prio k))
              k))
          (if matching-key 
              (cdr (hash-ref (ModuleArchive-archive m) matching-key))
              (cdr (hash-ref (ModuleArchive-archive m) 
                             (ModuleArchive-default-id m))))]
         ;; Symbol 'best: use default
         [(equal? prio 'best)
          (cdr (hash-ref (ModuleArchive-archive m) 
                         (ModuleArchive-default-id m)))]
         ;; String priority: geometric KNN selection
         [(and (string? prio) (not (null? (ModuleArchive-point-cloud m))))
          (ensure-selector!)
          (define target-vec (text->vector-fn prio send!))
          (select-elite-fn m target-vec)]
         [else (cdr (hash-ref (ModuleArchive-archive m) 
                              (ModuleArchive-default-id m)))])]
      [else (error "Invalid module type")]))
  ;; ... rest of execution
  )
```

This code shows the priority-aware selection in action. When passed a `ModuleArchive` rather than a single `Module`, the function examines the context's priority and selects appropriately—keyword fast-path for simple priorities, geometric KNN for natural language.

---

## Synthesis: The Integrated System

These theoretical components don't exist in isolation. They form an integrated system where each part reinforces the others:

**DSPy** provides the programming model—typed modules with explicit signatures that can be composed, optimized, and swapped.

**GEPA** evolves the content of these modules, using natural language reflection to diagnose failures and propose improvements, maintaining a Pareto frontier of candidates.

**MAP-Elites** organizes the evolved modules into an archive indexed by phenotype, enabling selection based on user priorities without losing diversity.

**Geometric Selection** maps user intent (expressed in keywords or natural language) to a target phenotype, then finds the closest elite in the archive via KNN.

**MAKER Decomposition** handles complex tasks by breaking them into atomic subtasks, with explosion detection and checkpoint/rollback providing safety nets.

**Sub-Agents** execute subtasks in parallel with focused tool profiles, enabling context management and concurrent execution.

**Temporal Stores** record everything—contexts, traces, evaluations—enabling learning over time and providing audit trails.

The flow is: a user request enters the system with an optional priority; geometric selection chooses the appropriate module variant; the task is potentially decomposed into subtasks; sub-agents execute with appropriate profiles; results are logged to the eval store; and periodically, GEPA uses accumulated feedback to evolve the modules, which updates the MAP-Elites archive, which changes future selection.

This creates a virtuous cycle: usage generates feedback; feedback drives evolution; evolution improves future performance; improved performance generates better feedback. The system doesn't just execute tasks—it learns from them.

---

## Further Reading

The papers cited in this document represent active research directions. For deeper engagement:

**GEPA**: Agrawal et al., "GEPA: Reflective Prompt Evolution Can Outperform Reinforcement Learning" (arXiv:2507.19457, July 2025)

**MAP-Elites**: Mouret & Clune, "Illuminating search spaces by mapping elites" (arXiv:1504.04909, April 2015)

**Grassmann Flows**: Zhang, "Attention Is Not What You Need" (arXiv:2512.19428, December 2025)

**MAKER**: Cognizant AI Lab, "Solving a Million-Step LLM Task with Zero Errors" (arXiv:2511.09030, November 2025)

**Zep/Graphiti**: Rasmussen et al., "Zep: A Temporal Knowledge Graph Architecture for Agent Memory" (arXiv:2501.13956, January 2025)

**Recursive LMs**: Zhang et al., "Recursive Language Models" (arXiv:2512.24601, December 2025)

The Chrysalis Forge source code itself serves as executable documentation. Start with [`main.rkt`](../main.rkt) for the entry point, [`src/llm/dspy-core.rkt`](../src/llm/dspy-core.rkt) for core abstractions, and [`src/core/geometric-decomposition.rkt`](../src/core/geometric-decomposition.rkt) for the decomposition system.
