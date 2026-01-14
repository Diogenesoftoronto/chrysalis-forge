# Geometric Decomposition System

> **A self-regulating, learning-based task decomposition framework that applies MAP-Elites phenotype selection to discover optimal decomposition strategies organically.**

## Overview

Traditional multi-agent decomposition systems (like MAKER) require decomposition strategies to be provided *a priori*. Geometric Decomposition takes a fundamentally different approach: it treats decomposition strategies themselves as a **phenotype space** that can be explored, learned, and optimized over time.

The system combines:
- **MAP-Elites archiving** for maintaining diverse, high-quality decomposition patterns
- **Phenotype-based KNN selection** for choosing strategies based on task priority
- **Explosion detection** for self-regulating decomposition depth
- **Checkpoint/rollback** for graceful recovery from over-decomposition
- **Voting consensus** for critical operations requiring high reliability

## Theoretical Foundation

### The Decomposition Phenotype

Just as biological phenotypes are observable characteristics resulting from genotype expression, a **Decomposition Phenotype** captures the observable characteristics of how a task was decomposed:

```
DecompositionPhenotype = (depth, breadth, cost, context, success-rate)
```

| Dimension | Description | Range |
|-----------|-------------|-------|
| `depth` | Maximum depth of decomposition tree | 0-∞ (typically 1-5) |
| `breadth` | Maximum parallel subtasks at any level | 1-∞ (typically 1-16) |
| `cost` | Accumulated $ cost of all LLM calls | 0-budget |
| `context` | Total context tokens across active branches | 0-limit |
| `success-rate` | Fraction of subtasks that succeeded | 0.0-1.0 |

### Geometric Selection

The phenotype forms a 5-dimensional space. When a new task arrives:

1. The user's **priority** (e.g., "cheap", "accurate", "I need speed") is mapped to a **target phenotype**
2. **KNN search** finds the closest successful decomposition pattern in the archive
3. That pattern is **replayed** as a template for the new task

This is analogous to how `dspy-selector.rkt` selects module variants based on priority, but applied to decomposition strategies instead.

### Explosion Detection

Unlike static decomposition, Geometric Decomposition is **self-regulating**. After each decomposition step, the system checks if any phenotype dimension has "exploded" beyond its limit:

```
if depth > max-depth       → EXPLOSION: depth
if breadth > max-breadth   → EXPLOSION: breadth  
if cost > budget           → EXPLOSION: cost
if context > limit         → EXPLOSION: context
if success-rate < min-sr   → EXPLOSION: diminishing-returns
```

On explosion, the system:
1. **Rolls back** to the last checkpoint
2. **Prunes** the offending branch
3. **Executes inline** (no further decomposition for that subtree)

### Organic Learning

Successful decomposition runs are archived with their phenotypes. Over time:
- Good patterns **crowd out** bad ones in each niche
- New tasks can **retrieve proven strategies** via KNN
- The system **adapts** to different task types and priority preferences

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Geometric Decomposition                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐    ┌──────────────────┐    ┌─────────────────────────┐    │
│  │ Task Entry  │───▶│ Pattern Selection │───▶│ Decomposition Loop      │    │
│  │             │    │ (KNN in Archive)  │    │ (with Checkpoints)      │    │
│  └─────────────┘    └──────────────────┘    └───────────┬─────────────┘    │
│                                                         │                   │
│                     ┌───────────────────────────────────┼───────────────┐   │
│                     │                                   ▼               │   │
│                     │  ┌─────────────┐    ┌─────────────────────────┐  │   │
│                     │  │ Explosion?  │◀───│ Update Phenotype        │  │   │
│                     │  └──────┬──────┘    └─────────────────────────┘  │   │
│                     │         │                                         │   │
│                     │    ┌────┴────┐                                    │   │
│                     │    │         │                                    │   │
│                     │   yes        no                                   │   │
│                     │    │         │                                    │   │
│                     │    ▼         ▼                                    │   │
│                     │ ┌────────┐ ┌────────────┐                         │   │
│                     │ │Rollback│ │More Steps? │                         │   │
│                     │ │+ Prune │ └─────┬──────┘                         │   │
│                     │ └────────┘       │                                │   │
│                     │                  ▼                                │   │
│                     │         ┌────────────────┐                        │   │
│                     │         │ Execute Leaves │                        │   │
│                     │         │ (Sub-Agents)   │                        │   │
│                     │         └───────┬────────┘                        │   │
│                     └─────────────────┼─────────────────────────────────┘   │
│                                       │                                     │
│                                       ▼                                     │
│                     ┌─────────────────────────────────┐                     │
│                     │ Record to Archive (MAP-Elites)  │                     │
│                     └─────────────────────────────────┘                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. DecompositionPhenotype

The observable characteristics of a decomposition run.

```racket
(struct DecompositionPhenotype
  (depth              ; max tree depth achieved
   breadth            ; max parallel leaves at any depth
   accumulated-cost   ; total $ spent
   context-size       ; peak context tokens
   success-rate)      ; subtask success fraction
  #:transparent)
```

### 2. DecompositionLimits

Thresholds that trigger explosion detection.

```racket
(struct DecompositionLimits
  (max-depth          ; stop decomposing beyond this
   max-breadth        ; limit parallel fan-out
   max-cost           ; budget in $
   max-context        ; context window limit
   min-success-rate)  ; abandon if success drops below
  #:transparent)
```

### 3. DecompStep

A single step in a decomposition pattern.

```racket
(struct DecompStep
  (op          ; 'decompose, 'spawn, 'vote, 'merge, 'inline
   args        ; operation-specific arguments
   depth       ; tree depth at which this operates
   profile)    ; sub-agent profile: 'editor, 'researcher, 'vcs, 'all
  #:transparent)
```

Operations:
- `'decompose` - Split task into subtasks via LLM
- `'spawn` - Launch sub-agent for a leaf task
- `'vote` - Run N agents and vote for consensus
- `'merge` - Combine subtask results
- `'inline` - Execute without further decomposition

### 4. DecompositionPattern

A reusable, learned decomposition strategy.

```racket
(struct DecompositionPattern
  (id              ; unique identifier
   task-type       ; e.g., "refactor", "implement", "debug"
   priority        ; 'best, 'cheap, 'fast, or priority string
   steps           ; (listof DecompStep)
   phenotype       ; observed DecompositionPhenotype
   stats)          ; hash: success-count, fail-count, avg-duration
  #:transparent)
```

### 5. DecompositionArchive

MAP-Elites archive for storing diverse, high-quality patterns.

```racket
(struct DecompositionArchive
  (task-type        ; what kind of tasks this archive serves
   archive          ; hash: bin-key → (cons score pattern)
   point-cloud      ; list of (cons phenotype pattern) for KNN
   default-id)      ; fallback pattern ID
  #:transparent)
```

### 6. DecompositionState

Live state during task decomposition with checkpoint support.

```racket
(struct DecompositionState
  (root-task        ; the original task
   task-type        ; classified task type
   priority         ; user priority
   tree             ; current decomposition tree
   phenotype        ; current phenotype
   limits           ; explosion thresholds
   checkpoints      ; stack of (tree, phenotype) snapshots
   steps-taken      ; list of DecompStep executed
   meta)            ; timing, ids, etc.
  #:transparent)
```

### 7. DecompositionCheckpoint

Saved state for rollback on explosion.

```racket
(struct DecompositionCheckpoint
  (tree-snapshot    ; decomposition tree at checkpoint
   phenotype        ; phenotype at checkpoint
   step-index       ; which step we were at
   reason)          ; 'initial, 'pre-branch, 'post-merge
  #:transparent)
```

## Voting Mechanism

For critical operations, the system uses **First-to-K voting** (from MAKER):

```racket
(struct VotingConfig
  (n-voters         ; how many agents to run
   k-threshold      ; votes needed to win
   timeout-ms       ; max wait time
   decorrelate?)    ; vary temperature/seed across voters
  #:transparent)
```

Voting is triggered when:
- Task is marked high-stakes (e.g., destructive file operations)
- Previous decomposition step had low success rate
- User priority emphasizes accuracy over cost

## Red-Flagging

Responses are automatically discarded if they show signs of unreliability:

1. **Length explosion** - Response exceeds expected length
2. **Format violation** - Response doesn't match expected structure
3. **Confidence markers** - Phrases like "I'm not sure" or excessive hedging
4. **Repetition** - Stuck in loops or repeating content

Red-flagged responses are discarded and resampled, increasing effective success rate.

## Integration Points

### With `dspy-core.rkt`

- Uses similar `Phenotype` abstraction
- Extends `Ctx` priority to drive decomposition selection
- Leverages `run-module` for decomposition LLM calls

### With `dspy-selector.rkt`

- Mirrors KNN selection pattern
- Uses same normalization approach
- Can share keyword→phenotype mappings

### With `sub-agent.rkt`

- Uses `spawn-sub-agent!` for leaf execution
- Leverages tool profiles (editor, researcher, vcs)
- Tracks sub-agent results for phenotype updates

### With `eval-store.rkt`

- Logs decomposition runs via `log-eval!`
- Uses `suggest-profile` for profile selection
- Feeds success data into archive learning

## Example Flow

```
User: "Refactor the authentication module to use JWT"
Priority: 'best (accuracy matters)

1. CLASSIFY
   → task-type: "refactor"
   → limits: (depth: 4, breadth: 8, cost: $1.00, context: 80000, min-sr: 0.6)

2. SELECT PATTERN (KNN)
   → target phenotype: (depth: 3, breadth: 4, cost: 0.5, context: 50000, sr: 0.9)
   → found pattern: "deep-refactor-v3" (distance: 0.12)

3. REPLAY PATTERN
   Step 1: decompose "find all auth-related files" → 3 subtasks
     → phenotype: (1, 3, 0.02, 4000, 1.0) ✓
   Step 2: spawn researcher for each file
     → phenotype: (1, 3, 0.08, 12000, 1.0) ✓
   Step 3: decompose "plan changes per file" → 6 subtasks
     → phenotype: (2, 6, 0.15, 24000, 1.0) ✓
   Step 4: spawn editor for each change
     → phenotype: (2, 6, 0.45, 48000, 0.83) ✓
   Step 5: vote on integration approach (3 voters, k=2)
     → phenotype: (2, 6, 0.65, 52000, 0.83) ✓
   Step 6: spawn editor for integration
     → phenotype: (2, 6, 0.72, 58000, 0.85) ✓

4. EXECUTE LEAVES
   → 6 sub-agents complete
   → final phenotype: (2, 6, 0.72, 58000, 0.85)

5. RECORD TO ARCHIVE
   → score: 0.85 - 0.072 - 0.0006 = 0.777
   → bin-key: (depth:2, breadth:5-8, cost:med, context:med)
   → updates point-cloud for future KNN
```

## Configuration

### Default Limits by Priority

| Priority | max-depth | max-breadth | max-cost | max-context | min-sr |
|----------|-----------|-------------|----------|-------------|--------|
| 'cheap   | 2         | 4           | $0.10    | 20000       | 0.5    |
| 'fast    | 2         | 8           | $0.50    | 40000       | 0.5    |
| 'best    | 4         | 8           | $2.00    | 80000       | 0.6    |
| 'verbose | 5         | 12          | $5.00    | 100000      | 0.7    |

### Voting Thresholds

| Scenario | n-voters | k-threshold |
|----------|----------|-------------|
| Default (no voting) | 1 | 1 |
| Low-stakes | 2 | 2 |
| Medium-stakes | 3 | 2 |
| High-stakes | 5 | 3 |
| Critical | 7 | 4 |

## Files

```
src/core/geometric-decomposition.rkt  ; Core structs, state, explosion detection
src/core/decomp-selector.rkt          ; KNN selection, pattern matching
src/core/decomp-voter.rkt             ; Voting consensus mechanism
src/core/decomp-planner.rkt           ; Main decomposition orchestrator
src/stores/decomp-archive.rkt         ; Archive persistence
src/utils/red-flag.rkt                ; Response quality filtering
```

## Heterogeneous Model Support

The system supports dynamic model selection across providers and model families.

### Model Discovery

Models are discovered dynamically from:
1. **API Endpoints** - Query `/models` from OpenAI-compatible APIs
2. **Local Config** - `~/.chrysalis/models.json` for overrides and custom models
3. **Default Catalog** - Built-in `default-models.json` with curated capabilities

### Model Selection

Models are selected per-task based on:
- **Static Capabilities** - Reasoning, coding, speed, cost-tier
- **Learned Performance** - Success rate, latency, cost by task-type
- **User Priority** - 'cheap, 'fast, 'best, or natural language

```racket
;; Select different models for different phases
(define decomp-model (select-decomposition-model 'fast))   ; gpt-4o-mini
(define exec-model (select-execution-model "implement" 'editor 'best))  ; gpt-5.2
```

### Model Chaining

For high-stakes operations:
```racket
(define-values (draft-model refine-model) 
  (select-model-chain "implement" 'editor 'best))
;; draft: fast model for initial attempt
;; refine: accurate model for verification
```

## Future Directions

1. **Automatic limit learning** - Learn optimal limits per task-type from eval history
2. **Cross-task transfer** - Use embeddings to find patterns from similar (not identical) task types
3. **Pareto optimization** - Maintain explicit Pareto fronts for multi-objective selection
4. **Meta-decomposition** - Apply geometric decomposition to the planning process itself
5. **Distributed execution** - Run sub-agents across multiple machines
6. **External registry integration** - Fetch capabilities from models.dev and other registries
