# Agent Architecture in Chrysalis Forge

Chrysalis Forge defines agents as **Evolvable Modules** that combine logic, state, optimization, and self-improvement. The TypeScript implementation routes sub-agent orchestration through the Pi runtime, uses JSON-backed stores, and exposes a terminal-first CLI.

## Pi Sibling Agent (`pi/`)

Alongside the TypeScript harness, the repo ships a lightweight, terminal-first agent under `pi/`:

- `pi/prompts/{architect,review,ship}.md` — task prompts for design, review, and implementation
- `pi/skills/ax-workflows` — route structured planning/eval through Ax programs, falling back to deterministic heuristics
- `pi/skills/terminal-first` — keep work on the shell path before any GUI detour
- `pi/architecture.mmd` / `pi/architecture.svg` — oxdraw-rendered overview (`oxdraw -i pi/architecture.mmd -o pi/architecture.svg`)

Pi artifacts land in `.chrysalis/outputs/` so they stay inspectable from the command line.

## Core Components

### 1. Types (`ts/core/types.ts`)

TypeScript interfaces define the agent's data model — signatures, harness strategies, evolution state, archive entries, profiles, and all store schemas. Key types include:

- `HarnessStrategy` — 12 evolvable fields controlled by 9 signal detectors
- `EvolutionState` — current prompts, archive, bandit model state, profile stats
- `ArchiveEntry` — phenotype, instruction, family lineage, evaluation history
- `ChrysalisProfile` — named priority profile with model and tool preferences
- `Phenotype` — `[cost, latency, tokens]` feature vector for MAP-Elites binning

### 2. Evolution Engine (`ts/core/evolution.ts`)

GEPA-style evolutionary loop with MAP-Elites archiving and bandit model selection:

```typescript
const { state, entry, noveltyScore } = await evolveSystemPrompt(cwd, feedback, currentProfile);
```

Key functions:
- `evolveSystemPrompt` — LLM-rewrites the system prompt, gates by novelty score
- `evolveMetaPrompt` — evolves the optimizer prompt itself
- `evolveHarnessStrategy` — mutates harness parameters based on detected signals
- `chooseExecutionModel` — Thompson sampling via Beta-bandit to pick LLM provider
- `runAutonomousEvolution` — cooldown check → LLM decision → apply mutations

### 3. Decomposition Planner (`ts/core/decomp-planner.ts`)

Task decomposition with LLM-backed and heuristic decomposition:

```typescript
const { subtasks, patternId } = await runDecomposition(cwd, task, taskType);
```

Key functions:
- `classifyTask` — returns task type: `refactor`, `implement`, `debug`, `research`, `test`, `document`, or `general`
- `decomposeTaskLLM` — LLM-backed decomposition via Ax prompt (falls back to heuristic)
- `heuristicDecomposition` — rule-based decomposition based on task type
- `suggestProfileForSubtask` — maps subtask description to tool profile

### 4. Priority Interpretation (`ts/core/priority.ts`)

Natural language priority selection — interpret phrases like "I need accuracy" into named profiles.

### 5. Context & Persistence (`ts/core/stores/context-store.ts`)

Agents operate within a `Ctx` (Context):
- `system`: High-level persona and rules
- `memory`: Working memory/scratchpad
- `tool-hints`: Guidance on tool usage
- `mode`: Operational mode gating tool access:
  - **`ask`**: Basic interaction, no filesystem
  - **`architect`**: Read files for analysis
  - **`code`**: Full capabilities including write, network, services
  - **`semantic`**: RDF Knowledge Graph mode

**Project Rules**: `.chrysalis/rules.md` in the working directory is automatically appended to the system prompt.

### 6. RDF Tools (`ts/core/tools/rdf-tools.ts`)

Three tool definitions exposed to the Pi agent:

| Tool | Description |
|------|-------------|
| `rdf_load` | Load triples from a file into a named graph |
| `rdf_query` | Query the knowledge graph with pattern syntax |
| `rdf_insert` | Insert a single triple or quad |

Dispatched via `executeRdfTool(cwd, name, args)`.

## Stores Layer (`ts/core/stores/`)

All stores are JSON-backed for zero-dependency portability:

| Store | File | Purpose |
|-------|------|---------|
| `context-store.ts` | `.chrysalis/state/context.json` | Agent context (system, memory, tool-hints, mode) |
| `eval-store.ts` | `.chrysalis/state/evals.jsonl` | Evaluation records for profile learning |
| `trace-store.ts` | `.chrysalis/state/traces.jsonl` | Task execution traces |
| `cache-store.ts` | `.chrysalis/state/web-cache.json` | HTTP response cache |
| `vector-store.ts` | `.chrysalis/state/vectors.json` | Semantic similarity search |
| `rdf-store.ts` | `.chrysalis/state/rdf/graph.db` | Triple/quad knowledge graph |
| `thread-store.ts` | `.chrysalis/state/threads.json` | Thread relations and context trees |
| `session-stats.ts` | `.chrysalis/state/session-stats.json` | Session performance metrics |
| `decomp-archive.ts` | `.chrysalis/state/decomp-archives/` | Archived decomposition patterns |
| `rollback-store.ts` | `.chrysalis/state/rollbacks/` | File version snapshots |
| Dynamic registry | `.chrysalis/state/stores/` | User-created kv/log/set/counter stores |

## Execution Loop (`ts/cli/main.ts`)

CLI dispatches commands:

| Command | Purpose |
|---------|---------|
| `shell` | Launch Pi interactive session |
| `plan <task>` | Write task plan artifact |
| `decomp <task>` | Run task decomposition |
| `profile [phrase]` | Show/interpret priority profile |
| `evolve <feedback>` | Evolve system prompt |
| `meta-evolve <feedback>` | Evolve meta/optimizer prompt |
| `harness <feedback>` | Mutate harness strategy |
| `archive` | View evolution archive |
| `stats` | Evolution state summary |
| `threads` / `thread <id>` | Thread management |
| `sessions` / `session <name>` | Session management |
| `rdf-load` / `rdf-query` / `rdf-insert` | RDF knowledge graph |
| `stores` / `store` | Dynamic store operations |
| `rollback <path>` | File rollback |
| `doctor` | Health check |

**Core Loop** (inside Pi session):
1. **Prompt Rendering**: Module + context + inputs compiled to prompt
2. **Tool Execution**: Security-gated via tool dispatch
3. **Context Compaction**: Automatic summarization when approaching token limits
4. **Trace Logging**: All tasks logged to `traces.jsonl`
5. **Eval Logging**: Profile performance logged to `evals.jsonl`

## Thread System (`ts/core/stores/thread-store.ts`)

Threads provide user-facing conversation continuity while hiding session implementation details.

### Hierarchy
```
Project → Thread → Context Nodes
                 ↓ (hidden)
              Sessions
```

### Key Functions

```typescript
threadCreate(cwd, title, project?)          // Create thread, returns T-<hex> ID
threadContinue(cwd, fromId, title?)         // Continuation thread with continues_from
threadSpawnChild(cwd, parentId, title)      // Child thread with child_of
threadRelationCreate(cwd, fromId, toId, type) // Custom relation edge
contextCreate(cwd, threadId, title, opts?)  // Create context node
contextTree(cwd, threadId)                  // Build hierarchical context tree
```

### Thread Relations
- `continues_from`: Linear continuation of a thread
- `child_of`: Hierarchical breakdown into subtopics
- `relates_to`: Loose association

## Optimization & Evolution

### GEPA (General Evolvable Prompting Architecture)

`ts/core/evolution.ts` — Evolves system prompts based on feedback:

```typescript
const { state, entry, noveltyScore } = await evolveSystemPrompt(cwd, feedback, profile);
```

### Meta-Optimization

`evolveMetaPrompt` — Evolves the optimizer prompt itself:
1. Bootstrap few-shot examples
2. Instruction mutation testing
3. Novelty-gated archival

### Eval Store (`ts/core/stores/eval-store.ts`)

Tracks performance for learning:
- `recordEvolutionEvaluation`: Log evaluation results
- `suggestProfileFromStats`: Recommend optimal profile for task type
- `chooseExecutionModel`: Bandit model selection for provider choice

**Feedback Loop**:
```
log_feedback → eval-store → profile_stats → suggest_profile
                          ↓
            evolve_system → GEPA → improved prompts
```

## Dynamic Store Registry

The TypeScript implementation adds a dynamic store registry (`kv/log/set/counter`) not present in the Racket version. Users can create named stores from the CLI:

```bash
chrysalis store create my-kv kv        # Key-value store
chrysalis store create my-counter counter  # Counter store
chrysalis store set my-kv foo bar      # Write value
chrysalis store get my-kv foo          # Read value
chrysalis stores                       # List all stores
```

Data lives under `.chrysalis/state/stores/<namespace>.json`.
