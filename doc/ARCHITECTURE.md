# Chrysalis Forge Architecture

Chrysalis Forge is a TypeScript agent framework that treats prompts, strategies, and decomposition patterns as evolvable components. The system self-improves through a GEPA-style evolutionary loop backed by MAP-Elites archiving, bandit-based model selection, and autonomous evolution triggers. Every component — from the system prompt to the harness strategy's 12 evolvable fields — is subject to mutation, selection, and archival.

The framework migrated from Racket to TypeScript, shedding the GUI layer and visual modules entirely. Persistence is JSON-backed across all stores. Sub-agent orchestration routes through the Pi runtime rather than Racket threads. The architecture prioritizes composable, terminal-first components that can be independently evolved, tested, and replaced.

---

## The Layered Design

```
┌─────────────────────────────────────────────────────┐
│  CLI  (ts/cli/main.ts)                              │
│  Command dispatch: shell, plan, evolve, decomp, …    │
├─────────────────────────────────────────────────────┤
│  Pi Extension / Commands  (ts/pi/)                   │
│  /plan /profile /evolve /meta-evolve /harness …      │
│  Session hooks: autonomous evolution on session_start │
├─────────────────────────────────────────────────────┤
│  Core / Orchestration  (ts/core/)                   │
│  Evolution │ Decomposition │ Priority │ Project      │
│  Config │ Ax Integration │ Paths │ Util             │
├─────────────────────────────────────────────────────┤
│  Stores  (ts/core/stores/)                           │
│  Context │ Eval │ Trace │ Cache │ Vector │ RDF      │
│  Decomp Archive │ Rollback │ Thread │ Session Stats │
│  Dynamic Store Registry (kv/log/set/counter)         │
├─────────────────────────────────────────────────────┤
│  Tools  (ts/core/tools/)                             │
│  Evolution │ Judge │ Test │ Priority │ Evolver │ Git   │
│  Jujutsu │ Web │ Sub-Agent │ Store │ Cache │ RDF    │
│  Rollback │ Decomp                        │
│  Tool Registry (runtime enable/disable/evolve)       │
│  Tool Evolution (novelty-gated variant management)   │
└─────────────────────────────────────────────────────┘
```

Each layer depends only on the layer below it. The CLI and Pi extension both exercise the Core orchestration layer. The Core depends on Stores for persistence and Tools for structured I/O. Stores are pure JSON-backed data modules with no cross-dependencies.

---

## The Stores Layer

All persistence lives under `ts/core/stores/`. Every store reads and writes JSON files under the `.chrysalis/state/` directory tree (configured via `ts/core/paths.ts`). There is no SQLite — even the RDF store is JSON-backed.

### Context Store

**File:** `ts/core/stores/context-store.ts`

Manages named sessions with their system prompts, memory, tool hints, mode, and priority. Sessions are the primary isolation boundary for conversation state.

```typescript
interface SessionDB {
  active: string;
  items: Record<string, SessionContext>;
  metadata: Record<string, SessionMetadata>;
}

interface SessionContext {
  system: string;
  memory: string;
  toolHints: string;
  mode: "ask" | "code";
  priority: ChrysalisProfile | string;
  history: unknown[];
  compactedSummary: string;
}
```

Operations: `sessionCreate`, `sessionSwitch`, `sessionDelete`, `sessionList`, `sessionGetActive`. Writes are atomic via `rename()` over a `.tmp` file.

### Eval Store

**File:** `ts/core/stores/eval-store.ts`

Appends task outcome records to a JSONL file and maintains aggregated profile statistics. Each evaluation records success/failure, profile, task type, tools used, and duration.

```typescript
interface EvalRecord {
  ts: number;
  taskId: string;
  success: boolean;
  profile: string;
  taskType: string;
  toolsUsed: string[];
  durationMs: number;
  feedback: string;
}
```

Profile statistics track per-profile success rates, task type distributions, and tool frequency histograms. The `suggestProfile()` function uses these statistics to recommend the best-performing profile for a given task type.

### Trace Store

**File:** `ts/core/stores/trace-store.ts`

Append-only JSONL audit trail. Each trace captures the task, final output, token usage, cost, and tool results.

```typescript
interface TraceRecord {
  ts: number;
  task: string;
  final: string;
  tokens: Record<string, number>;
  cost: number;
  toolResults: unknown[];
}
```

### Decomposition Archive

**File:** `ts/core/stores/decomp-archive.ts`

Stores per-task-type decomposition patterns in a MAP-Elites–inspired structure. Each archive maintains an `archive` map keyed by phenotype bin, a `pointCloud` of all observed pattern/phenotype pairs, and a `defaultId` pointing to the best overall pattern.

```typescript
interface DecompositionArchive {
  taskType: string;
  archive: Record<string, { score: number; pattern: DecompositionPattern }>;
  pointCloud: Array<{ phenotype: DecompPhenotype; pattern: DecompositionPattern }>;
  defaultId: string | null;
}
```

`recordPattern()` replaces the bin entry when a higher-scoring pattern arrives and prepends to the point cloud. `pruneArchive()` caps the cloud size at 1000 entries while preserving binned patterns.

### Rollback Store

**File:** `ts/core/stores/rollback-store.ts`

File-level undo system. `fileBackup()` copies a file to `.chrysalis/state/rollbacks/` with a timestamped backup name and records the entry in an index. `fileRollback()` restores a file to a previous version by copying the backup back. The index tracks up to 10 rollback entries per file (configurable).

```typescript
interface RollbackEntry {
  timestamp: number;
  backupPath: string;
}
```

### Thread Store

**File:** `ts/core/stores/thread-store.ts`

Durable conversation state with relations and context trees. Threads can be linked to sessions, spawned as children, or continued from previous threads.

```typescript
interface ThreadsDB {
  threads: Record<string, ThreadData>;
  relations: ThreadRelation[];
  contexts: Record<string, ContextNode>;
  activeThread: string | null;
}
```

Relations model `continues_from` and `child_of` edges. Context nodes form a tree (via `parentId`) within each thread, enabling hierarchical note-taking. Writes are atomic.

### Cache Store

**File:** `ts/core/stores/cache-store.ts`

TTL-bounded key-value cache with tag-based invalidation. Default TTL is 86400s (1 day), max 604800s (1 week).

```typescript
interface CacheEntry {
  value: string;
  createdAt: number;
  ttl: number;
  tags: string[];
}
```

`cacheInvalidateByTag()` removes all entries carrying a given tag. `cacheCleanup()` evicts expired entries. Stats report total, valid, expired, and per-tag counts.

### Vector Store

**File:** `ts/core/stores/vector-store.ts`

Cosine similarity search over stored embeddings. Each entry pairs text with a numeric vector.

```typescript
interface VectorEntry {
  text: string;
  vec: number[];
}
```

`vectorSearch()` computes cosine similarity between a query vector and all stored vectors, returning the top-K results. Suitable for small-scale semantic retrieval without an external vector database.

### RDF Store

**File:** `ts/core/stores/rdf-store.ts`

JSON-backed triple/quad store with pattern-matching queries. Each triple has subject, predicate, object, graph, and timestamp fields.

```typescript
interface Triple {
  subject: string;
  predicate: string;
  object: string;
  graph: string;
  timestamp: number;
}
```

`rdfLoad()` parses N-triples format files into a named graph (replacing existing triples for that graph). `rdfQuery()` supports pattern matching with `?` wildcards (e.g., `?s predicate object ?g`). `rdfInsert()` adds a single triple. All data is stored in a single JSON file.

### Session Stats

**File:** `ts/core/stores/session-stats.ts`

Tracks per-session metrics: turns, token counts, costs, files read/written, and tool usage frequency.

```typescript
interface SessionStats {
  startTime: number;
  turns: number;
  tokensIn: number;
  tokensOut: number;
  totalCost: number;
  filesWritten: string[];
  filesRead: string[];
  toolsUsed: Record<string, number>;
}
```

Incremental updates via `addTurn()`, `addTokens()`, `addCost()`, `recordToolUse()`, `recordFileOp()`.

### Dynamic Store Registry

**File:** `ts/core/stores/store-registry.ts`

User-created stores at runtime. The registry tracks specs and delegates to per-kind data files.

```typescript
type StoreKind = "kv" | "log" | "set" | "counter";

interface StoreSpec {
  name: string;
  namespace: string;
  kind: StoreKind;
  description: string;
  createdAt: number;
  updatedAt: number;
}
```

- **kv**: key-value map (`Record<string, unknown>`)
- **log**: append-only array of timestamped entries
- **set**: array with deduplication on insert
- **counter**: single `{ value: number }` incremented by `storeSet`

Stores are namespaced (`namespace:name`). Each store's data lives in a separate JSON file under `.chrysalis/state/stores/`.

---

## The Core Layer

### Evolution Engine

**File:** `ts/core/evolution.ts`

The evolutionary loop implements GEPA (Generate-Evaluate-Preserve-Adapt) with MAP-Elites archiving. Four evolution families are tracked: `"prompt"`, `"meta"`, `"workflow"`, and `"harness"`.

**System Prompt Evolution** (`evolveSystemPrompt`): The LLM (or heuristic fallback) rewrites the system prompt given feedback. Novelty is checked against the `noveltyArchive` using trigram Jaccard distance. If the first rewrite is insufficiently novel (threshold 0.3), a second rewrite is forced with stronger instructions. Accepted rewrites are archived and the novelty archive is updated (capped at 100 entries).

**Meta Prompt Evolution** (`evolveMetaPrompt`): Same process for the optimizer/meta-prompt that governs how system prompts are themselves rewritten.

**Harness Strategy Evolution** (`evolveHarnessStrategy`): Signal detection on feedback text mutates the 12 evolvable fields of the harness:

```typescript
interface HarnessStrategy {
  contextBudget: number;        // 0–1, fraction of context window
  compactionThreshold: number;  // 0–1, trigger for context compaction
  strategyType: "predict" | "cot";
  temperature: number;         // 0–2
  topP: number;                 // 0–1
  toolHintWeight: number;      // 0–1, bias toward tool usage
  preferTools: boolean;        // tool-first or reasoning-first
  demoCount: number;           // 1–8 few-shot examples
  demoSelection: "random" | "similar" | "diverse";
  preferCheapDecomp: boolean;  // favor low-cost decomposition
  executionPriority: ChrysalisProfile;
  mutationRate: number;        // 0.05–1, controls evolutionary exploration
}
```

Nine signal detectors parse feedback for compact, detailed, urgent, costSensitive, toolHeavy, precisionHeavy, exploratory, migrationHeavy, and reviewHeavy signals. Each signal triggers targeted field mutations with clamped bounds.

**MAP-Elites Archive** (`ArchiveEntry`): Every evolved variant is binned by phenotype. Phenotypes are normalized and binned by median thresholds: `cheap|premium : fast|slow : compact|verbose`. `selectEliteEntry()` retrieves the nearest archived variant to a target phenotype.

**Bandit Model Selection** (`BanditState`): A Thompson sampling ensemble selects which LLM provider to use for each evolution or planning call. `chooseBanditArm()` samples from Beta(α, β) for each arm and selects the highest sample. `updateBandit()` adjusts α/β based on task success/failure.

**Autonomous Evolution** (`runAutonomousEvolution`): Triggered automatically on `session_start`, `task_plan`, and `evaluation` events. An LLM call (with heuristic fallback) decides whether to evolve the system prompt, meta prompt, and/or harness. Cooldowns prevent over-evolution: 6 hours for session_start triggers, 1 hour for others. The `force` flag bypasses cooldowns.

### Decomposition System

Three modules collaborate on task decomposition:

**Planner** (`ts/core/decomp-planner.ts`): Classifies tasks into types via keyword matching. Produces subtask definitions with dependency graphs and tool profile hints. Two decomposition paths: `decomposeTaskLLM()` uses `@ax-llm/ax` (timeout 20s), and `heuristicDecomposition()` provides rule-based fallback.

**Selector** (`ts/core/decomp-selector.ts`): Retrieves the best archived decomposition pattern for a given priority by mapping profiles to target phenotypes. `selectPatternForPhenotype()` finds the archived pattern whose computed phenotype is nearest (Euclidean distance) to the target.

**Voter** (`ts/core/decomp-voter.ts`): First-to-K voting for reliability on high-stakes tasks. Five stakes presets from NONE (0 voters) to CRITICAL (9 voters, K=7). When decorrelation is enabled, each voter receives a different style prompt. Votes are tallied with fuzzy equivalence (Jaccard ≥ 0.6 on words).

### Priority System

**File:** `ts/core/priority.ts`

Natural language to profile mapping. `interpretProfilePhrase()` parses user phrases like "I need this fast" or "keep costs down" into one of four profiles: `"fast"`, `"cheap"`, `"best"`, or `"verbose"`.

### Supporting Core Modules

**Config** (`ts/core/config.ts`): Loads `chrysalis.config.json` with sanitization. Defines the runtime preference, default provider/model/thinking, tool list, default profile, and artifact root.

**Ax Integration** (`ts/core/ax.ts`): Wraps `@ax-llm/ax` for LLM-backed task planning. Falls back to heuristic plans when no provider is configured.

**Paths** (`ts/core/paths.ts`): Central path resolver for the `.chrysalis/` directory tree. `ensureChrysalisDirs()` creates the full directory structure on first access.

**Project** (`ts/core/project.ts`): Project scaffold, profile state persistence, task plan artifact writing, and artifact listing.

**Util** (`ts/core/util.ts`): `slugify()` (URL-safe filenames) and `dedupe()` (whitespace-trimmed unique filter).

---

## The Pi Runtime Layer

### Pi Agent Extension

**File:** `ts/pi/chrysalis-extension.ts`

Registers 20 commands with the Pi agent runtime and hooks into `session_start` for autonomous evolution:

![Evolution cycle](../.vhs/evo-cycle.mp4)

| Command | Action |
|---------|--------|
| `/plan` | Write a task plan artifact via Ax |
| `/profile` | Show or set the active profile |
| `/evolve` | Force system prompt evolution |
| `/meta-evolve` | Force meta/optimizer prompt evolution |
| `/harness` | Force harness strategy mutation |
| `/evolve-tool` | Evolve a tool's definition from feedback |
| `/archive` | Browse archived evolution variants |
| `/stats` | Show evolution and profile statistics |
| `/outputs` | Browse generated artifacts |
| `/sessions` | List sessions |
| `/session` | Switch session |
| `/threads` | List threads |
| `/thread` | Switch thread |
| `/rollback` | Rollback a file to a previous version |
| `/cache-stats` | Show cache statistics |
| `/rdf-load` | Load triples into an RDF graph |
| `/rdf-query` | Query the RDF knowledge graph |
| `/rdf-insert` | Insert a triple into the RDF store |
| `/decomp` | Decompose a task into subtasks |
| `/stores` | List dynamic stores |
| `/store` | Manage dynamic stores (create/get/set/rm/dump) |

The `session_start` hook loads the evolution state, prints a summary, and fires `runAutonomousEvolution()` asynchronously.

### Pi Runtime

**File:** `ts/runtime/pi.ts`

Handles two Pi runtime modes:

1. **Standalone**: Spawns the `pi` binary as a child process with `stdio: "inherit"`.
2. **Bundled/Embedded**: Imports `@mariozechner/pi-coding-agent` directly and calls `main()` in-process.

Runtime preference: `"embedded-only"` | `"prefer-embedded"` | `"standalone-only"` | `"prefer-standalone"`.

### Bundled Assets

**File:** `ts/runtime/bundled-assets.generated.ts`

Generated at build time. Contains versioned file payloads for Bun-compiled binaries. When running as a Bun binary, the runtime extracts bundled files to `~/.chrysalis/bundled/{version}/`.

### Task Prompts and Skills

The Pi runtime points to two directories passed as CLI arguments:
- `--prompt-template`: Directory containing prompt templates (typically `pi/prompts/`)
- `--skill`: Directory containing skill definitions (typically `pi/skills/`)

These are resolved by `resolveResourceLayout()` to either the source tree (development) or the bundled package directory (production binary).

---

## The Tools Layer

### RDF Tools

**File:** `ts/core/tools/rdf-tools.ts`

Exposes three tools with structured parameter schemas for Pi agent consumption: `rdf_load`, `rdf_query`, `rdf_insert`. `executeRdfTool()` dispatches by name to the corresponding `rdf-store` functions.

### Tool Profiles

Subtasks and harness strategies use tool profiles to scope available tools:

```typescript
type ToolProfile = "editor" | "researcher" | "vcs" | "all";
```

- **editor**: File read/write/edit tools
- **researcher**: Search, grep, find, read tools
- **vcs**: Git/jj branch, commit, merge tools
- **all**: Full tool access

`suggestProfileForSubtask()` in `ts/core/decomp-planner.ts` selects a profile for each subtask based on keyword analysis of its description.

### Tool Evolution Engine

**File:** `ts/core/tools/tool-evolution.ts`

Manages novelty-gated mutation of tool definitions. Mirrors the prompt evolution pattern but applied to tool descriptions and parameters.

![Tool evolution](../.vhs/tool-evolution.mp4)

```typescript
interface ToolVariant {
  id: string;
  toolName: string;
  description: string;
  parameters: Record<string, unknown>;
  active: boolean;
  score: number;
  noveltyScore: number;
  createdAt: string;
  model: string;
  feedback: string;
}

interface ToolEvolutionState {
  variants: Record<string, ToolVariant[]>;
  fieldHistory: Record<string, EvolvableToolField>;
  updatedAt: string;
}
```

`evolveTool()` mutates a tool's description and/or parameters via LLM (or heuristic append fallback). Novelty is computed as the maximum n-gram trigram distance between the candidate and all existing variants for that tool. Variants below the novelty threshold (default 0.25) are rejected (marked `active: false`). State is persisted to `.chrysalis/state/tool-evolution.json`.

The engine provides: `evolveToolDescription()`, `evolveToolParameters()`, `getActiveToolVariant()` (returns highest-scoring active variant), `listToolVariants()`, `archiveToolVariant()`, `selectToolVariant()`, `toolEvolutionStats()`.

### Evolvable Tool Registry

**File:** `ts/core/tools/tool-registry.ts`

Runtime singleton (`globalToolRegistry`) extending `EventEmitter` that tracks registered tools and delegates to the tool evolution engine. Tools can be enabled/disabled, evolved, and have variants selected at runtime without restart.

```typescript
class EvovableToolRegistry extends EventEmitter {
  registerTool(def, executor): void;
  unregisterTool(name): boolean;
  enableTool(name): boolean;
  disableTool(name): boolean;
  getActiveDefinition(name): ToolDefinition | undefined;
  evolveToolDefinition(name, feedback, field?, threshold?): Promise<...>;
  execute(name, args): Promise<string>;
  listTools(): Array<{ name, enabled, version, hasEvolvedVariant }>;
}
```

`getActiveDefinition()` checks for evolved variants first (via `getActiveToolVariant()`), falling back to the base definition. The registry emits events (`tool:registered`, `tool:evolved`, `tool:enabled`, `tool:disabled`, `tool:variant-selected`, `tool:variant-archived`) that are wired into Pi's notification system on session start.

### Judge Tools

**File:** `ts/core/tools/judge-tools.ts`

LLM-as-judge evaluation with heuristic fallback. `use_llm_judge` evaluates code/text against configurable criteria and a pass/fail threshold. `judge_quality` is a convenience wrapper for code quality evaluation. The heuristic scores based on: documentation presence, type annotations, error handling, test presence, and line length.

### Test Generation Tools

**File:** `ts/core/tools/test-tools.ts`

LLM-backed test generation with framework auto-detection from file extension and content. `generate_tests` reads a source file, detects the framework (vitest/jest/pytest/golang), and generates tests via LLM (heuristic fallback generates basic existence/type checks). `generate_test_cases` generates concrete inputs/outputs for a function signature.

### Priority Tools

**File:** `ts/core/tools/priority-tools.ts`

LLM-callable wrappers for profile management. `set_priority` delegates to `interpretProfilePhrase()` for natural language profile selection and persists via `saveProfileState()`. `suggest_priority` maps task types to profiles (debug→fast, implement→best, research→cheap).

### Evolver Tools

**File:** `ts/core/tools/evolver-tools.ts`

LLM-callable tools for tool evolution. All 8 tools (`evolve_tool`, `list_tools`, `tool_variants`, `select_tool_variant`, `enable_tool`, `disable_tool`, `tool_stats`, `tool_evolution_stats`) delegate to `globalToolRegistry`. This makes the tool system self-referential: the agent uses its own tools to evolve its own tools.

---

## Design Principles

**Evolvability over correctness.** Every prompt and strategy is treated as a hypothesis. The evolutionary loop replaces components rather than debugging them. A poor system prompt is evolved away, not patched.

**Heuristic fallback everywhere.** Every LLM-dependent operation has a deterministic fallback: task planning, decomposition, autonomous evolution decisions, and prompt rewriting all degrade gracefully when no provider is configured or when calls timeout.

**JSON-backed simplicity.** All stores use JSON files on disk. No external databases, no SQLite, no server processes. This trades query performance for zero-dependency portability and human-readability.

**Terminal-first, no GUI.** The Racket GUI layer was removed in the TypeScript migration. All interaction is through the CLI or the Pi terminal agent. This is a deliberate constraint, not an omission.

**Atomic writes.** Critical stores (context, thread, store-registry) use `writeFile` + `rename` to avoid partial writes. Append-only stores (eval, trace) use `appendFile` for concurrent safety.

**Phenotype-driven selection.** Both evolution entries and decomposition patterns are selected by phenotype distance rather than score alone. MAP-Elites binning ensures behavioral diversity is preserved alongside quality.

**Bandit over manual selection.** Model selection for evolution and planning uses Thompson sampling on success/failure feedback. The system learns which providers perform best for which tasks without explicit configuration.

**Autonomous but bounded.** Autonomous evolution triggers on natural lifecycle events but is constrained by cooldowns and novelty gates. The system can improve itself without human intervention, but cannot spiral into infinite self-modification.

**Dynamic stores as escape hatch.** The store registry (`kv`, `log`, `set`, `counter`) allows the agent to create ad-hoc persistence at runtime. The meta-prompt is explicitly told to consider whether agents should create stores for tracking their own performance.
