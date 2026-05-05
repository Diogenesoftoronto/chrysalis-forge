export type PiRuntimePreference =
  | "embedded-only"
  | "prefer-embedded"
  | "standalone-only"
  | "prefer-standalone";

export type ChrysalisProfile = "fast" | "cheap" | "best" | "verbose";

export type ChrysalisTaskType =
  | "build"
  | "bugfix"
  | "refactor"
  | "review"
  | "research"
  | "migration";

export type EvolutionFamily = "prompt" | "meta" | "workflow" | "harness";

export interface Phenotype {
  accuracy: number;
  latency: number;
  cost: number;
  usage: number;
}

export interface ArchiveEntry {
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

export interface BanditArm {
  alpha: number;
  beta: number;
}

export interface BanditState {
  arms: Record<string, BanditArm>;
}

export interface HarnessStrategy {
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

export interface ProfileStatsEntry {
  total: number;
  success: number;
  successRate: number;
  taskTypes: Record<string, number>;
  toolFreq: Record<string, number>;
}

export interface EvaluationRecord {
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

export interface EvolutionState {
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

export interface AutonomousEvolutionTrigger {
  kind: "session_start" | "task_plan" | "evaluation" | "manual";
  task?: string;
  taskType?: ChrysalisTaskType;
  profile?: ChrysalisProfile;
  planSummary?: string;
  force?: boolean;
}

export interface AutonomousEvolutionDecision {
  shouldEvolveSystem: boolean;
  shouldEvolveMeta: boolean;
  shouldMutateHarness: boolean;
  reason: string;
  focus: string[];
}

export interface AutonomousEvolutionReport {
  decision: AutonomousEvolutionDecision;
  applied: boolean;
  skippedReason?: string;
  results: Array<{ target: string; status: "applied" | "skipped"; detail: string }>;
}

export interface ChrysalisConfig {
  pi: {
    runtimePreference: PiRuntimePreference;
    defaultProvider?: string;
    defaultModel?: string;
    defaultThinking?: string;
    tools: string[];
  };
  profiles: {
    default: ChrysalisProfile;
  };
  artifacts: {
    root: string;
  };
}

export interface TaskPlan {
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

export type ToolProfile = "editor" | "researcher" | "vcs" | "all";

export interface SessionStats {
  startTime: number;
  turns: number;
  tokensIn: number;
  tokensOut: number;
  totalCost: number;
  filesWritten: string[];
  filesRead: string[];
  toolsUsed: Record<string, number>;
}

export interface SessionContext {
  system: string;
  memory: string;
  toolHints: string;
  mode: "ask" | "code";
  priority: ChrysalisProfile | string;
  history: unknown[];
  compactedSummary: string;
}

export interface SessionMetadata {
  id: string;
  title?: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface SessionDB {
  active: string;
  items: Record<string, SessionContext>;
  metadata: Record<string, SessionMetadata>;
}

export interface ThreadData {
  id: string;
  title: string;
  project?: string | null;
  status: string;
  summary?: string | null;
  sessionName?: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface ThreadRelation {
  from: string;
  to: string;
  type: string;
  createdAt: number;
}

export interface ContextNode {
  id: string;
  threadId: string;
  parentId?: string | null;
  title: string;
  kind: string;
  body?: string | null;
  createdAt: number;
  children?: ContextNode[];
}

export interface ThreadsDB {
  threads: Record<string, ThreadData>;
  relations: ThreadRelation[];
  contexts: Record<string, ContextNode>;
  activeThread: string | null;
}

export interface RollbackEntry {
  timestamp: number;
  backupPath: string;
}

export interface TraceRecord {
  ts: number;
  task: string;
  final: string;
  tokens: Record<string, number>;
  cost: number;
  toolResults: unknown[];
}

export interface CacheEntry {
  value: string;
  createdAt: number;
  ttl: number;
  tags: string[];
}

export interface CacheStats {
  total: number;
  valid: number;
  expired: number;
  tags: Record<string, number>;
}

export interface DecompStep {
  id: string;
  description: string;
  toolHints: string[];
  dependencies: number[];
}

export interface DecompositionPattern {
  id: string;
  name: string;
  steps: DecompStep[];
  metadata: Record<string, unknown>;
}

export interface DecompPhenotype {
  depth: number;
  parallelism: number;
  toolDiversity: number;
  complexity: number;
}

export interface DecompositionArchive {
  taskType: string;
  archive: Record<string, { score: number; pattern: DecompositionPattern }>;
  pointCloud: Array<{ phenotype: DecompPhenotype; pattern: DecompositionPattern }>;
  defaultId: string | null;
}

export interface VectorEntry {
  text: string;
  vec: number[];
}

export interface SubtaskDefinition {
  description: string;
  dependencies: number[];
  profileHint: ToolProfile;
}

export interface VotingConfig {
  nVoters: number;
  kThreshold: number;
  timeoutMs: number;
  decorrelate: boolean;
}

export interface VotingResult<T> {
  consensus: boolean;
  tally: Map<T, number>;
  winner: T;
  margin: number;
  votes: T[];
}

export interface ProfileState {
  activeProfile: ChrysalisProfile;
  updatedAt: string;
  reason?: string;
}

export type StoreKind = "kv" | "log" | "set" | "counter";

export interface StoreSpec {
  name: string;
  namespace: string;
  kind: StoreKind;
  description: string;
  createdAt: number;
  updatedAt: number;
}

export interface StoreRegistryDB {
  stores: Record<string, StoreSpec>;
}

