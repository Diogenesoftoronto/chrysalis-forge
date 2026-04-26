# Chrysalis Forge — API Reference

> All functions are async unless noted otherwise. Every store/evolution function takes `cwd: string` as its first argument.

---

## Types — `ts/core/types.ts`

### Type Aliases

```typescript
type PiRuntimePreference = "embedded-only" | "prefer-embedded" | "standalone-only" | "prefer-standalone";
type ChrysalisProfile = "fast" | "cheap" | "best" | "verbose";
type ChrysalisTaskType = "build" | "bugfix" | "refactor" | "review" | "research" | "migration";
type EvolutionFamily = "prompt" | "meta" | "workflow" | "harness";
type ToolProfile = "editor" | "researcher" | "vcs" | "all";
type StoreKind = "kv" | "log" | "set" | "counter";
```

### Core Interfaces

```typescript
interface Phenotype {
  accuracy: number;  // 0–10
  latency: number;   // lower is faster
  cost: number;      // lower is cheaper
  usage: number;     // token utilization
}

interface ArchiveEntry {
  id: string;
  family: EvolutionFamily;
  taskFamily: string;
  content: string;
  score: number;
  phenotype: Phenotype;
  binKey: string;
  createdAt: string;
  active: boolean;
  model: string;
  metadata: Record<string, unknown>;
}

interface BanditArm { alpha: number; beta: number; }
interface BanditState { arms: Record<string, BanditArm>; }

interface HarnessStrategy {
  contextBudget: number;
  compactionThreshold: number;
  strategyType: "predict" | "cot";
  temperature: number;
  topP: number;
  toolHintWeight: number;
  preferTools: boolean;
  demoCount: number;
  demoSelection: "random" | "similar" | "diverse";
  preferCheapDecomp: boolean;
  executionPriority: ChrysalisProfile;
  mutationRate: number;
}

interface EvaluationRecord {
  ts: number;
  taskId: string;
  success: boolean;
  profile: ChrysalisProfile | string;
  taskType: string;
  toolsUsed: string[];
  durationMs: number;
  feedback: string;
  candidateId?: string | null;
  evalStage: string;
  model?: string | null;
  score?: number | null;
  latencyMs?: number | null;
  costUsd?: number | null;
  binKey?: string | null;
}

interface EvolutionState {
  currentSystemPrompt: string;
  currentMetaPrompt: string;
  harness: HarnessStrategy;
  bandit: BanditState;
  noveltyArchive: string[];
  updatedAt: string;
  lastAutonomousRunAt?: string;
  autonomousRuns: number;
  lastAutonomousReason?: string;
}

interface AutonomousEvolutionTrigger {
  kind: "session_start" | "task_plan" | "evaluation" | "manual";
  task?: string;
  taskType?: ChrysalisTaskType;
  profile?: ChrysalisProfile;
  planSummary?: string;
  force?: boolean;
}

interface AutonomousEvolutionDecision {
  shouldEvolveSystem: boolean;
  shouldEvolveMeta: boolean;
  shouldMutateHarness: boolean;
  reason: string;
  focus: string[];
}

interface AutonomousEvolutionReport {
  decision: AutonomousEvolutionDecision;
  applied: boolean;
  skippedReason?: string;
  results: Array<{ target: string; status: "applied" | "skipped"; detail: string }>;
}

interface TaskPlan {
  summary: string;
  taskType: ChrysalisTaskType;
  recommendedProfile: ChrysalisProfile;
  deliverables: string[];
  risks: string[];
  firstSteps: string[];
  mode: "heuristic" | "ax";
  systemPrompt?: string;
  harness?: HarnessStrategy;
}
```

### Session & Thread Types

```typescript
interface SessionContext {
  system: string;
  memory: string;
  toolHints: string;
  mode: "ask" | "code";
  priority: ChrysalisProfile | string;
  history: unknown[];
  compactedSummary: string;
}

interface SessionMetadata {
  id: string;
  title?: string | null;
  createdAt: number;
  updatedAt: number;
}

interface SessionDB {
  active: string;
  items: Record<string, SessionContext>;
  metadata: Record<string, SessionMetadata>;
}

interface ThreadData {
  id: string;
  title: string;
  project?: string | null;
  status: string;
  summary?: string | null;
  sessionName?: string | null;
  createdAt: number;
  updatedAt: number;
}

interface ThreadRelation { from: string; to: string; type: string; createdAt: number; }

interface ContextNode {
  id: string;
  threadId: string;
  parentId?: string | null;
  title: string;
  kind: string;
  body?: string | null;
  createdAt: number;
  children?: ContextNode[];
}

interface ThreadsDB {
  threads: Record<string, ThreadData>;
  relations: ThreadRelation[];
  contexts: Record<string, ContextNode>;
  activeThread: string | null;
}
```

### Decomposition Types

```typescript
interface DecompStep { id: string; description: string; toolHints: string[]; dependencies: number[]; }
interface DecompositionPattern { id: string; name: string; steps: DecompStep[]; metadata: Record<string, unknown>; }
interface DecompPhenotype { depth: number; parallelism: number; toolDiversity: number; complexity: number; }
interface DecompositionArchive {
  taskType: string;
  archive: Record<string, { score: number; pattern: DecompositionPattern }>;
  pointCloud: Array<{ phenotype: DecompPhenotype; pattern: DecompositionPattern }>;
  defaultId: string | null;
}
interface SubtaskDefinition { description: string; dependencies: number[]; profileHint: ToolProfile; }
interface VotingConfig { nVoters: number; kThreshold: number; timeoutMs: number; decorrelate: boolean; }
interface VotingResult<T> { consensus: boolean; tally: Map<T, number>; winner: T; margin: number; votes: T[]; }
```

### Remaining Types

```typescript
interface SessionStats { startTime: number; turns: number; tokensIn: number; tokensOut: number; totalCost: number; filesWritten: string[]; filesRead: string[]; toolsUsed: Record<string, number>; }
interface RollbackEntry { timestamp: number; backupPath: string; }
interface TraceRecord { ts: number; task: string; final: string; tokens: Record<string, number>; cost: number; toolResults: unknown[]; }
interface CacheEntry { value: string; createdAt: number; ttl: number; tags: string[]; }
interface CacheStats { total: number; valid: number; expired: number; tags: Record<string, number>; }
interface VectorEntry { text: string; vec: number[]; }
interface ProfileState { activeProfile: ChrysalisProfile; updatedAt: string; reason?: string; }
interface StoreSpec { name: string; namespace: string; kind: StoreKind; description: string; createdAt: number; updatedAt: number; }
interface StoreRegistryDB { stores: Record<string, StoreSpec>; }
interface ChrysalisConfig { pi: { runtimePreference: PiRuntimePreference; defaultProvider?: string; defaultModel?: string; defaultThinking?: string; tools: string[] }; profiles: { default: ChrysalisProfile }; artifacts: { root: string }; }
```

---

## Core

### Evolution — `ts/core/evolution.ts`

#### Novelty & Phenotype Utilities (sync)

```typescript
function instructionNgrams(text: string, n?: number): Set<string>
function instructionNoveltyScore(existing: string[], candidate: string): number
function novelEnough(existing: string[], candidate: string, threshold?: number): boolean
function phenotypeDistance(left: Phenotype, right: Phenotype): number
function normalizePhenotype(pheno: Phenotype, mins: number[], maxs: number[]): Phenotype
function selectEliteEntry(entries: ArchiveEntry[], target: Phenotype): ArchiveEntry | null
```

#### State Management (async)

```typescript
async function loadEvolutionState(cwd: string): Promise<EvolutionState>
async function saveEvolutionState(cwd: string, state: EvolutionState): Promise<EvolutionState>
async function loadEffectiveSystemPrompt(cwd: string): Promise<string>
async function loadEffectiveMetaPrompt(cwd: string): Promise<string>
```

#### Evolution Operations (async)

```typescript
async function evolveSystemPrompt(cwd: string, feedback: string, currentProfile: ChrysalisProfile): Promise<{ state: EvolutionState; entry: ArchiveEntry; noveltyScore: number; rejected?: boolean }>
async function evolveMetaPrompt(cwd: string, feedback: string, currentProfile: ChrysalisProfile): Promise<{ state: EvolutionState; entry: ArchiveEntry; noveltyScore: number }>
async function evolveHarnessStrategy(cwd: string, feedback: string, currentProfile: ChrysalisProfile): Promise<{ state: EvolutionState; harness: HarnessStrategy }>
```

#### Autonomous Evolution (async)

```typescript
async function runAutonomousEvolution(cwd: string, trigger: AutonomousEvolutionTrigger): Promise<AutonomousEvolutionReport>
```

Respects cooldown (6h for `session_start`, 1h otherwise) unless `trigger.force` is `true`.

#### Archive & Evaluation (async)

```typescript
async function loadEvolutionArchive(cwd: string): Promise<ArchiveEntry[]>
async function listEvolutionBins(cwd: string): Promise<Record<string, ArchiveEntry>>
async function recordEvolutionEvaluation(cwd: string, record: EvaluationRecord): Promise<void>
async function suggestProfileFromStats(cwd: string, taskType: string): Promise<{ profile: ChrysalisProfile; score: number }>
```

#### Summary & Bootstrap (async)

```typescript
function summarizeEvolutionState(state: EvolutionState): string[]
function chooseExecutionModel(state: EvolutionState): string
async function ensureEvolutionBootstrap(cwd: string): Promise<EvolutionState>
async function loadEvolutionSummary(cwd: string): Promise<{ state: EvolutionState; archive: ArchiveEntry[]; bins: Record<string, ArchiveEntry>; profileStats: Record<string, ProfileStatsEntry> }>
```

---

### Decomposition Planner — `ts/core/decomp-planner.ts`

```typescript
function classifyTask(taskDescription: string): string
function suggestProfileForSubtask(description: string): ToolProfile
async function decomposeTaskLLM(task: string, cwd: string, maxSubtasks?: number): Promise<SubtaskDefinition[]>
function heuristicDecomposition(task: string, maxSubtasks?: number): SubtaskDefinition[]
async function runDecomposition(cwd: string, task: string, taskType: ChrysalisTaskType | string): Promise<{ subtasks: SubtaskDefinition[]; patternId: string }>
function shouldVote(task: string): boolean
```

### Decomposition Voter — `ts/core/decomp-voter.ts`

```typescript
const STAKES_PRESETS: Record<string, VotingConfig>
// NONE: 0v/0k/0ms  LOW: 3v/2k/5s  MEDIUM: 5v/3k/10s  HIGH: 7v/5k/15s  CRITICAL: 9v/7k/20s

function tallyVotes<T extends string>(votes: T[], config: VotingConfig): VotingResult<T>
function decorrelatePrompt(base: string, index: number, total: number): string
function selectStakes(taskDescription: string): keyof typeof STAKES_PRESETS
async function executeWithVoting<T extends string>(task: string, executeVote: (prompt: string, index: number) => Promise<T>, config?: VotingConfig): Promise<VotingResult<T>>
```

### Decomposition Selector — `ts/core/decomp-selector.ts`

```typescript
function priorityToPhenotype(priority: ChrysalisProfile): DecompPhenotype
function computeDecompPhenotype(pattern: DecompositionPattern): DecompPhenotype
function selectPatternForPhenotype(archive: DecompositionArchive, target: DecompPhenotype): DecompositionPattern | null
function selectPatternForPriority(archive: DecompositionArchive, priority: ChrysalisProfile): DecompositionPattern | null
async function selectOrDecompose(cwd: string, taskType: string, priority: ChrysalisProfile): Promise<{ pattern: DecompositionPattern | null; source: "archive" | "fallback" }>
```

### Decomposition Archive — `ts/core/stores/decomp-archive.ts`

```typescript
async function loadArchive(cwd: string, taskType: string): Promise<DecompositionArchive>
async function saveArchive(cwd: string, arch: DecompositionArchive): Promise<void>
async function listArchives(cwd: string): Promise<string[]>
function recordPattern(archive: DecompositionArchive, pattern: DecompositionPattern, score: number): DecompositionArchive
function pruneArchive(archive: DecompositionArchive, maxCloudSize?: number): DecompositionArchive
function archiveStats(archive: DecompositionArchive): { totalPatterns: number; binsFilled: number; avgScore: number; bestPatternId: string | null }
```

### Priority — `ts/core/priority.ts`

```typescript
function interpretProfilePhrase(input: string): { profile: ChrysalisProfile; reason: string }
```

### Task Planner — `ts/core/ax.ts`

```typescript
async function createTaskPlan(task: string, cwd: string, currentProfile: ChrysalisProfile): Promise<TaskPlan>
```

### Utilities — `ts/core/util.ts`

```typescript
function slugify(value: string): string
function dedupe(items: string[]): string[]
```

---

## Stores

### Context Store — `ts/core/stores/context-store.ts`

```typescript
async function sessionCreate(cwd: string, name: string, opts?: { mode?: "ask" | "code"; id?: string; title?: string }): Promise<SessionDB>
async function sessionSwitch(cwd: string, name: string): Promise<SessionDB>
async function sessionList(cwd: string): Promise<{ names: string[]; active: string }>
async function sessionDelete(cwd: string, name: string): Promise<SessionDB>
async function sessionGetActive(cwd: string): Promise<SessionContext>
async function sessionGetLast(cwd: string): Promise<string | null>
```

### Thread Store — `ts/core/stores/thread-store.ts`

```typescript
async function threadCreate(cwd: string, title: string, project?: string): Promise<string>
async function threadFind(cwd: string, id: string): Promise<ThreadData | null>
async function threadList(cwd: string, opts?: { project?: string; status?: string; limit?: number }): Promise<ThreadData[]>
async function threadUpdate(cwd: string, id: string, updates: Partial<Pick<ThreadData, "title" | "status" | "summary">>): Promise<void>
async function threadGetActive(cwd: string): Promise<string | null>
async function threadSetActive(cwd: string, id: string): Promise<void>
async function threadSwitch(cwd: string, id: string): Promise<void>
async function threadContinue(cwd: string, fromId: string, title?: string): Promise<string>
async function threadSpawnChild(cwd: string, parentId: string, title: string): Promise<string>
async function contextCreate(cwd: string, threadId: string, title: string, opts?: { parentId?: string; kind?: string; body?: string }): Promise<string>
async function contextList(cwd: string, threadId: string): Promise<ContextNode[]>
async function contextTree(cwd: string, threadId: string): Promise<ContextNode[]>
```

### Eval Store — `ts/core/stores/eval-store.ts`

```typescript
async function logEval(cwd: string, record: Omit<EvalRecord, "ts">): Promise<void>
async function getProfileStats(cwd: string, profile?: string): Promise<EvalProfileStats | Record<string, EvalProfileStats>>
async function suggestProfile(cwd: string, taskType: string): Promise<{ profile: string; rate: number }>
async function evolveProfile(cwd: string, profileName: string, threshold?: number): Promise<{ profile: string; successRate: number; recommendedTools: string[]; evaluation: "stable" | "needs_improvement" }>
```

### Trace Store — `ts/core/stores/trace-store.ts`

```typescript
async function logTrace(cwd: string, record: Omit<TraceRecord, "ts">): Promise<void>
```

### Cache Store — `ts/core/stores/cache-store.ts`

```typescript
async function cacheGet(cwd: string, key: string, ignoreTtl?: boolean): Promise<string | null>
async function cacheSet(cwd: string, key: string, value: string, ttl?: number, tags?: string[]): Promise<string>
async function cacheInvalidate(cwd: string, key: string): Promise<string>
async function cacheInvalidateByTag(cwd: string, tag: string): Promise<string>
async function cacheCleanup(cwd: string): Promise<string>
async function cacheStats(cwd: string): Promise<CacheStats>
```

### Rollback Store — `ts/core/stores/rollback-store.ts`

```typescript
async function fileBackup(cwd: string, path: string, maxRollbacks?: number): Promise<string | null>
async function fileRollback(cwd: string, path: string, steps?: number): Promise<{ ok: boolean; message: string }>
async function fileRollbackList(cwd: string, path: string): Promise<Array<{ step: number; timestamp: number; backupPath: string; size: number }>>
```

### Session Stats — `ts/core/stores/session-stats.ts`

```typescript
async function loadSessionStats(cwd: string): Promise<SessionStats>
async function addTurn(cwd: string, opts: { tokensIn?: number; tokensOut?: number; cost?: number }): Promise<SessionStats>
async function recordToolUse(cwd: string, toolName: string): Promise<SessionStats>
async function recordFileOp(cwd: string, path: string, mode: "write" | "read"): Promise<SessionStats>
function getSessionStatsDisplay(stats: SessionStats): Record<string, string | number>
```

### Vector Store — `ts/core/stores/vector-store.ts`

```typescript
async function vectorAdd(cwd: string, text: string, vec: number[]): Promise<string>
async function vectorSearch(cwd: string, queryVec: number[], topK?: number): Promise<Array<{ score: number; text: string }>>
function cosineSimilarity(a: number[], b: number[]): number
```

### RDF Store — `ts/core/stores/rdf-store.ts`

```typescript
async function rdfLoad(cwd: string, path: string, graphId: string): Promise<string>
async function rdfQuery(cwd: string, query: string, graphId?: string): Promise<string>
async function rdfInsert(cwd: string, subject: string, predicate: string, object: string, graph?: string, timestamp?: number): Promise<string>
```

### Store Registry — `ts/core/stores/store-registry.ts`

```typescript
async function storeCreate(cwd: string, name: string, kind: StoreKind, opts?: { namespace?: string; description?: string }): Promise<StoreSpec>
async function storeDelete(cwd: string, name: string, namespace?: string): Promise<string>
async function storeList(cwd: string, opts?: { namespace?: string; kind?: StoreKind }): Promise<StoreSpec[]>
async function storeGet(cwd: string, name: string, field: string, namespace?: string): Promise<string>
async function storeSet(cwd: string, name: string, field: string, value: string, namespace?: string): Promise<string>
async function storeRemove(cwd: string, name: string, field: string, namespace?: string): Promise<string>
async function storeDump(cwd: string, name: string, namespace?: string): Promise<string>
async function storeDescribe(cwd: string): Promise<string>
```

---

## Tools — `ts/core/tools/rdf-tools.ts`

```typescript
const RDF_TOOL_DEFINITIONS: Array<{ name: string; description: string; parameters: object }>
// Three tools: "rdf_load", "rdf_query", "rdf_insert"

async function executeRdfTool(cwd: string, name: string, args: Record<string, unknown>): Promise<string>
```

---

## Project — `ts/core/project.ts`

```typescript
async function ensureProjectScaffold(cwd: string): Promise<void>
async function loadProfileState(cwd: string): Promise<ProfileState>
async function saveProfileState(cwd: string, activeProfile: ChrysalisProfile, reason: string): Promise<ProfileState>
async function writeTaskPlanArtifact(cwd: string, task: string): Promise<{ planPath: string; plan: TaskPlan }>
async function listArtifacts(cwd: string): Promise<Array<{ label: string; path: string }>>
```

---

## Config — `ts/core/config.ts`

```typescript
const DEFAULT_CONFIG: ChrysalisConfig
function configPath(cwd: string): string
async function loadConfig(cwd: string): Promise<ChrysalisConfig>
async function ensureConfig(cwd: string): Promise<void>
function mergePiDefaults(config: ChrysalisConfig, args: string[]): string[]
```

---

## Paths — `ts/core/paths.ts`

| Function | Path |
|----------|------|
| `artifactRoot(cwd)` | `<cwd>/.chrysalis` |
| `outputsDir(cwd)` | `.chrysalis/outputs` |
| `sessionsDir(cwd)` | `.chrysalis/sessions` |
| `stateDir(cwd)` | `.chrysalis/state` |
| `evolutionDir(cwd)` | `.chrysalis/state/evolution` |
| `evolutionStatePath(cwd)` | `.chrysalis/state/evolution/state.json` |
| `evolutionArchivePath(cwd)` | `.chrysalis/state/evolution/archive.json` |
| `evolutionEvalPath(cwd)` | `.chrysalis/state/evolution/evals.jsonl` |
| `evolutionSystemPromptPath(cwd)` | `.chrysalis/state/evolution/system-prompt.md` |
| `evolutionMetaPromptPath(cwd)` | `.chrysalis/state/evolution/meta-prompt.md` |
| `rdfDbPath(cwd)` | `.chrysalis/state/rdf/graph.db` |
| `threadStorePath(cwd)` | `.chrysalis/state/threads.json` |
| `contextStorePath(cwd)` | `.chrysalis/state/context.json` |
| `traceStorePath(cwd)` | `.chrysalis/state/traces.jsonl` |
| `cacheStorePath(cwd)` | `.chrysalis/state/web-cache.json` |
| `evalStorePath(cwd)` | `.chrysalis/state/evals.jsonl` |
| `vectorStorePath(cwd)` | `.chrysalis/state/vectors.json` |
| `sessionStatsPath(cwd)` | `.chrysalis/state/session-stats.json` |
| `storeRegistryPath(cwd)` | `.chrysalis/state/store-registry.json` |

```typescript
async function ensureChrysalisDirs(cwd: string, rootName?: string): Promise<void>
```

---

## Environment Variables

| Variable | Provider | Default Model |
|----------|----------|---------------|
| `OPENAI_API_KEY` | OpenAI | `gpt-5.4` (or `OPENAI_MODEL` / `MODEL`) |
| `ANTHROPIC_API_KEY` | Anthropic | `claude-sonnet-4-0` (or `ANTHROPIC_MODEL`) |
| `GEMINI_API_KEY` | Google Gemini | `gemini-2.5-pro` (or `GEMINI_MODEL`) |

Provider selection order: OpenAI → Anthropic → Google Gemini. Custom base URLs via `OPENAI_BASE_URL` / `OPENAI_API_BASE`.
