# Agent Guidance: Core Systems

This directory contains the core orchestration and decomposition systems.

## Geometric Decomposition System

A self-regulating, learning-based task decomposition framework. See [documentation](/doc/geometric-decomposition.md).

### Key Modules

| Module | Purpose |
|--------|---------|
| `geometric-decomposition.rkt` | Core structs: Phenotype, State, Limits, Checkpoints |
| `decomp-selector.rkt` | KNN selection of patterns, priority→phenotype mapping |
| `decomp-voter.rkt` | First-to-K voting consensus (from MAKER paper) |
| `decomp-planner.rkt` | Main orchestrator tying everything together |
| `sub-agent.rkt` | Parallel sub-agent execution with tool profiles |

### Usage Pattern

```racket
(require "decomp-planner.rkt")

;; Run geometric decomposition on a task
(define-values (result phenotype success?)
  (run-geometric-decomposition 
    "Refactor auth module to use JWT"
    ctx
    send!
    run-subtask!
    #:budget 1.0
    #:context-limit 80000))
```

### Phenotype Dimensions

- **depth**: Max tree depth (1-5 typical)
- **breadth**: Max parallel leaves (1-16 typical)
- **cost**: Accumulated $ spent
- **context**: Peak context tokens
- **success-rate**: Subtask success fraction (0-1)

### Explosion Handling

When any dimension exceeds limits:
1. Rollback to last checkpoint
2. Prune offending branch
3. Execute remaining work inline (no further decomposition)

### Voting

Use voting for high-stakes operations:
- `VOTING-NONE` (1 voter) - default
- `VOTING-LOW` (2 voters, k=2)
- `VOTING-MEDIUM` (3 voters, k=2)
- `VOTING-HIGH` (5 voters, k=3)
- `VOTING-CRITICAL` (7 voters, k=4)

### Archive Learning

Successful decomposition patterns are archived by task-type and priority. Future similar tasks retrieve patterns via KNN for faster, more reliable execution.

## Sub-Agent System

Parallel task execution with focused tool profiles.

### Profiles

- `'editor` - File operations: read, write, patch, diff
- `'researcher` - Search operations: grep, web search, file reading
- `'vcs` - Version control: git + jujutsu operations
- `'all` - Full toolkit (use sparingly)

### Usage

```racket
(define task-id (spawn-sub-agent! "Fix the bug in auth.rkt" run-fn #:profile 'editor))
(define result (await-sub-agent! task-id))
```
