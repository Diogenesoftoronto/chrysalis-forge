import { existsSync } from "node:fs";
import { readFile, writeFile, appendFile } from "node:fs/promises";
import { join } from "node:path";

import { ai, ax } from "@ax-llm/ax";

import {
  evolutionArchivePath,
  evolutionDir,
  evolutionEvalPath,
  evolutionMetaPromptPath,
  evolutionProfileStatsPath,
  evolutionStatePath,
  evolutionSystemPromptPath,
  ensureChrysalisDirs
} from "./paths.js";
import { interpretProfilePhrase } from "./priority.js";
import {
  type AutonomousEvolutionDecision,
  type AutonomousEvolutionReport,
  type AutonomousEvolutionTrigger,
  type ArchiveEntry,
  type BanditState,
  type ChrysalisProfile,
  type ChrysalisTaskType,
  type EvaluationRecord,
  type EvolutionFamily,
  type EvolutionState,
  type HarnessStrategy,
  type Phenotype,
  type TaskPlan,
  type ProfileStatsEntry
} from "./types.js";
import { dedupe, slugify } from "./util.js";

const DEFAULT_SYSTEM_PROMPT = [
  "You are Chrysalis, a terminal-first coding agent.",
  "Prefer precise, verifiable shell workflows and deterministic artifacts.",
  "Use the simplest implementation that preserves the requested behavior.",
  "When the user asks for evolution, optimize the shell experience first and keep GUI work out of scope unless explicitly requested.",
  "You can create, read, and modify dynamic stores via /stores and /store commands. Use these to persist task state, accumulate results, or build custom knowledge bases as needed."
].join(" ");

const DEFAULT_META_PROMPT = [
  "You are Chrysalis' optimizer.",
  "Rewrite system prompts and harness strategy based on direct feedback.",
  "Return concise structured output that preserves terminal-first behavior and the current project constraints.",
  "Dynamic stores (kv, log, set, counter) are available to the agent for persisting operational state. When evolving prompts, consider whether the agent should be guided to create stores for tracking its own performance, accumulating feedback, or building task-specific indexes."
].join(" ");

const DEFAULT_HARNESS: HarnessStrategy = {
  contextBudget: 0.8,
  compactionThreshold: 0.9,
  strategyType: "predict",
  temperature: 0,
  topP: 1,
  toolHintWeight: 0.5,
  preferTools: false,
  demoCount: 3,
  demoSelection: "random",
  preferCheapDecomp: true,
  executionPriority: "best",
  mutationRate: 0.3
};

const DEFAULT_BANDIT: BanditState = {
  arms: {
    openai: { alpha: 1, beta: 1 },
    anthropic: { alpha: 1, beta: 1 },
    "google-gemini": { alpha: 1, beta: 1 }
  }
};

interface EvolutionArchiveState {
  entries: ArchiveEntry[];
}

interface ProviderConfig {
  provider: string;
  apiKey: string;
  model?: string;
  baseURL?: string;
}

async function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out after ${ms}ms`)), ms);
      })
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function cloneHarness(harness: HarnessStrategy): HarnessStrategy {
  return { ...harness };
}

function cloneBandit(bandit: BanditState): BanditState {
  return {
    arms: Object.fromEntries(
      Object.entries(bandit.arms).map(([key, value]) => [key, { alpha: value.alpha, beta: value.beta }])
    )
  };
}

function defaultProfileStats(): Record<string, ProfileStatsEntry> {
  return {};
}

async function readTextOrDefaultAsync(path: string, fallback: string): Promise<string> {
  try {
    if (existsSync(path)) {
      return await readFile(path, "utf8");
    }
  } catch {}
  return fallback;
}

async function readJsonFile<T>(path: string, fallback: T): Promise<T> {
  try {
    const parsed = JSON.parse(await readFile(path, "utf8")) as T;
    return parsed;
  } catch {
    return fallback;
  }
}

async function writeJsonFile(path: string, value: unknown): Promise<void> {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function resolveProviderConfig(preferredProvider?: string): ProviderConfig | null {
  const configs: Record<string, ProviderConfig | null> = {
    openai: process.env.OPENAI_API_KEY
      ? {
          provider: "openai",
          apiKey: process.env.OPENAI_API_KEY,
          model: process.env.OPENAI_MODEL ?? process.env.MODEL ?? "gpt-5.4",
          baseURL: process.env.OPENAI_BASE_URL ?? process.env.OPENAI_API_BASE
        }
      : null,
    anthropic: process.env.ANTHROPIC_API_KEY
      ? {
          provider: "anthropic",
          apiKey: process.env.ANTHROPIC_API_KEY,
          model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-0"
        }
      : null,
    "google-gemini": process.env.GEMINI_API_KEY
      ? {
          provider: "google-gemini",
          apiKey: process.env.GEMINI_API_KEY,
          model: process.env.GEMINI_MODEL ?? "gemini-2.5-pro"
        }
      : null
  };

  if (preferredProvider && configs[preferredProvider]) {
    return configs[preferredProvider];
  }
  return configs.openai ?? configs.anthropic ?? configs["google-gemini"] ?? null;
}

function phraseToSentences(text: string): string[] {
  return dedupe(
    text
      .split(/[\n\r.;]+/g)
      .map((entry) => entry.trim())
      .filter(Boolean)
  );
}

function appendInstructionBlock(base: string, feedback: string, additions: string[]): string {
  const blocks = [
    base.trim(),
    "",
    "Evolution notes:",
    ...additions.map((line) => `- ${line}`),
    ...(feedback.trim() ? ["", `Feedback: ${feedback.trim()}`] : [])
  ];
  return blocks.join("\n").trim() + "\n";
}

function defaultSystemPrompt(): string {
  return `${DEFAULT_SYSTEM_PROMPT}\n`;
}

function defaultMetaPrompt(): string {
  return `${DEFAULT_META_PROMPT}\n`;
}

function defaultEvolutionState(): EvolutionState {
  return {
    currentSystemPrompt: defaultSystemPrompt(),
    currentMetaPrompt: defaultMetaPrompt(),
    harness: cloneHarness(DEFAULT_HARNESS),
    bandit: cloneBandit(DEFAULT_BANDIT),
    noveltyArchive: [],
    updatedAt: new Date().toISOString(),
    autonomousRuns: 0
  };
}

function detectTaskType(task: string): ChrysalisTaskType {
  const normalized = task.toLowerCase();
  if (/\bmigrat|rewrite|replace|port\b/.test(normalized)) return "migration";
  if (/\bbug|fix|failing|regression|broken\b/.test(normalized)) return "bugfix";
  if (/\brefactor|cleanup|simplify|reshape\b/.test(normalized)) return "refactor";
  if (/\breview|audit|inspect\b/.test(normalized)) return "review";
  if (/\bresearch|investigate|compare|explore\b/.test(normalized)) return "research";
  return "build";
}

function sampleGamma(shape: number): number {
  if (shape < 1) {
    return sampleGamma(shape + 1) * Math.pow(Math.random(), 1 / shape);
  }

  const d = shape - 1 / 3;
  const c = 1 / Math.sqrt(9 * d);

  for (;;) {
    let x = 0;
    let v = 0;
    do {
      x = gaussianRandom();
      v = 1 + c * x;
    } while (v <= 0);

    v = v * v * v;
    const u = Math.random();
    if (u < 1 - 0.0331 * (x * x) * (x * x)) return d * v;
    if (Math.log(u) < 0.5 * x * x + d * (1 - v + Math.log(v))) return d * v;
  }
}

function sampleBeta(alpha: number, beta: number): number {
  const left = sampleGamma(alpha);
  const right = sampleGamma(beta);
  const total = left + right;
  return total === 0 ? 0.5 : left / total;
}

function gaussianRandom(): number {
  let u = 0;
  let v = 0;
  while (u === 0) u = Math.random();
  while (v === 0) v = Math.random();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

export function instructionNgrams(text: string, n = 3): Set<string> {
  const cleaned = text.toLowerCase().trim();
  if (cleaned.length < n) return new Set([cleaned]);
  const grams = new Set<string>();
  for (let i = 0; i <= cleaned.length - n; i += 1) {
    grams.add(cleaned.slice(i, i + n));
  }
  return grams;
}

export function instructionNoveltyScore(existing: string[], candidate: string): number {
  if (existing.length === 0) return 1;
  const cand = instructionNgrams(candidate);
  let best = 1;
  for (const entry of existing) {
    const other = instructionNgrams(entry);
    let intersection = 0;
    for (const gram of cand) {
      if (other.has(gram)) intersection += 1;
    }
    const union = new Set([...cand, ...other]).size;
    const distance = union === 0 ? 0 : 1 - intersection / union;
    best = Math.min(best, distance);
  }
  return best;
}

export function novelEnough(existing: string[], candidate: string, threshold = 0.3): boolean {
  return instructionNoveltyScore(existing, candidate) >= threshold;
}

export function phenotypeDistance(left: Phenotype, right: Phenotype): number {
  return Math.sqrt(
    (left.accuracy - right.accuracy) ** 2 +
      (left.latency - right.latency) ** 2 +
      (left.cost - right.cost) ** 2 +
      (left.usage - right.usage) ** 2
  );
}

export function normalizePhenotype(pheno: Phenotype, mins: number[], maxs: number[]): Phenotype {
  const safeNorm = (value: number, lo: number, hi: number) => (lo === hi ? 0.5 : (value - lo) / (hi - lo));
  return {
    accuracy: safeNorm(pheno.accuracy, mins[0], maxs[0]),
    latency: safeNorm(pheno.latency, mins[1], maxs[1]),
    cost: safeNorm(pheno.cost, mins[2], maxs[2]),
    usage: safeNorm(pheno.usage, mins[3], maxs[3])
  };
}

function phenotypeBounds(entries: ArchiveEntry[]): { mins: number[]; maxs: number[] } {
  const phenos = entries.map((entry) => entry.phenotype);
  return {
    mins: [
      Math.min(...phenos.map((p) => p.accuracy)),
      Math.min(...phenos.map((p) => p.latency)),
      Math.min(...phenos.map((p) => p.cost)),
      Math.min(...phenos.map((p) => p.usage))
    ],
    maxs: [
      Math.max(...phenos.map((p) => p.accuracy)),
      Math.max(...phenos.map((p) => p.latency)),
      Math.max(...phenos.map((p) => p.cost)),
      Math.max(...phenos.map((p) => p.usage))
    ]
  };
}

export function selectEliteEntry(entries: ArchiveEntry[], target: Phenotype): ArchiveEntry | null {
  if (entries.length === 0) return null;
  const { mins, maxs } = phenotypeBounds(entries);
  const targetNorm = normalizePhenotype(target, mins, maxs);
  const scored = entries
    .map((entry) => ({
      distance: phenotypeDistance(targetNorm, normalizePhenotype(entry.phenotype, mins, maxs)),
      entry
    }))
    .sort((left, right) => left.distance - right.distance || right.entry.score - left.entry.score);
  return scored[0]?.entry ?? null;
}

function mean(values: number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.floor(sorted.length / 2)];
}

function heuristicPhenotype(content: string, score: number, metadata: Record<string, unknown> = {}): Phenotype {
  const words = content.trim().split(/\s+/).filter(Boolean).length;
  const chars = content.length;
  const estimatedTokens = Math.max(1, Math.ceil(chars / 4));
  const latencyHint = typeof metadata.elapsedMs === "number" ? (metadata.elapsedMs as number) : Math.max(0, 12 - words / 20);
  const costHint = typeof metadata.costUsd === "number" ? (metadata.costUsd as number) : Math.max(0, 10 - estimatedTokens / 60);
  const usageHint = typeof metadata.usage === "number" ? (metadata.usage as number) : Math.max(0, 10 - estimatedTokens / 80);
  return {
    accuracy: Math.max(0, Math.min(10, score)),
    latency: Math.max(0, Math.min(10, latencyHint)),
    cost: Math.max(0, Math.min(10, costHint)),
    usage: Math.max(0, Math.min(10, usageHint))
  };
}

function thresholdsForEntries(entries: ArchiveEntry[]): { cost: number; latency: number; usage: number } {
  return {
    cost: median(entries.map((entry) => entry.phenotype.cost)),
    latency: median(entries.map((entry) => entry.phenotype.latency)),
    usage: median(entries.map((entry) => entry.phenotype.usage))
  };
}

function binKeyForPhenotype(phenotype: Phenotype, thresholds: { cost: number; latency: number; usage: number }): string {
  return [
    phenotype.cost < thresholds.cost ? "cheap" : "premium",
    phenotype.latency < thresholds.latency ? "fast" : "slow",
    phenotype.usage < thresholds.usage ? "compact" : "verbose"
  ].join(":");
}

function scoreCandidate(content: string, feedback: string, currentProfile: ChrysalisProfile): number {
  const novelty = instructionNoveltyScore([content], feedback);
  const profileBias = currentProfile === "best" ? 8 : currentProfile === "fast" ? 6 : currentProfile === "cheap" ? 5 : 7;
  const brevity = Math.max(0, 10 - content.trim().split(/\s+/).length / 20);
  return Math.max(0.1, Math.min(10, profileBias * 0.5 + novelty * 2 + brevity * 0.3));
}

interface HarnessSignals {
  compact: boolean;
  detailed: boolean;
  urgent: boolean;
  costSensitive: boolean;
  toolHeavy: boolean;
  precisionHeavy: boolean;
  exploratory: boolean;
  migrationHeavy: boolean;
  reviewHeavy: boolean;
}

function detectHarnessSignals(text: string): HarnessSignals {
  const lower = text.toLowerCase();
  return {
    compact: /\b(compact|concise|short|terse|brief|summary)\b/.test(lower),
    detailed: /\b(detailed|thorough|deep|careful|expansive|comprehensive)\b/.test(lower),
    urgent: /\b(fast|urgent|quick|speed|low latency)\b/.test(lower),
    costSensitive: /\b(cheap|budget|cost|savings|efficient|thrifty)\b/.test(lower),
    toolHeavy: /\b(tool|tools|shell|terminal|workflow|automation)\b/.test(lower),
    precisionHeavy: /\b(precise|verifiable|deterministic|strict|safe|reliable)\b/.test(lower),
    exploratory: /\b(explore|explore|investigate|compare|research|novel|broad)\b/.test(lower),
    migrationHeavy: /\b(migration|migrate|port|rewrite|replace|refactor)\b/.test(lower),
    reviewHeavy: /\b(review|audit|inspect|judge|critique)\b/.test(lower)
  };
}

function mutateHarnessFromSignals(
  harness: HarnessStrategy,
  signals: HarnessSignals,
  currentProfile: ChrysalisProfile
): HarnessStrategy {
  const next = cloneHarness(harness);

  if (signals.compact) {
    next.contextBudget = Math.max(0.35, next.contextBudget - 0.15);
    next.compactionThreshold = Math.max(0.45, next.compactionThreshold - 0.1);
    next.demoCount = Math.max(1, next.demoCount - 1);
    next.demoSelection = "random";
  }

  if (signals.detailed || signals.reviewHeavy) {
    next.contextBudget = Math.min(0.98, next.contextBudget + 0.12);
    next.compactionThreshold = Math.min(0.98, next.compactionThreshold + 0.08);
    next.strategyType = "cot";
    next.preferTools = true;
    next.demoCount = Math.min(8, next.demoCount + 1);
    next.demoSelection = signals.reviewHeavy ? "similar" : "diverse";
  }

  if (signals.urgent) {
    next.executionPriority = "fast";
    next.temperature = 0;
    next.contextBudget = Math.max(0.4, next.contextBudget - 0.05);
  }

  if (signals.costSensitive) {
    next.executionPriority = "cheap";
    next.preferCheapDecomp = true;
    next.toolHintWeight = Math.min(1, next.toolHintWeight + 0.08);
  }

  if (signals.toolHeavy) {
    next.preferTools = true;
    next.toolHintWeight = Math.min(1, next.toolHintWeight + 0.15);
  }

  if (signals.precisionHeavy) {
    next.temperature = 0;
    next.topP = 1;
    next.compactionThreshold = Math.min(0.98, next.compactionThreshold + 0.04);
    next.strategyType = next.strategyType === "cot" ? next.strategyType : "predict";
  }

  if (signals.exploratory) {
    next.mutationRate = Math.min(1, next.mutationRate + 0.1);
    next.demoSelection = "diverse";
    next.topP = Math.min(1, Math.max(0.85, next.topP - 0.05));
  }

  if (signals.migrationHeavy) {
    next.contextBudget = Math.min(0.95, next.contextBudget + 0.05);
    next.preferTools = true;
    next.executionPriority = currentProfile === "cheap" ? "cheap" : "best";
    next.demoSelection = "similar";
    next.mutationRate = Math.min(1, next.mutationRate + 0.05);
  }

  if (signals.reviewHeavy) {
    next.executionPriority = currentProfile === "fast" ? "fast" : "best";
    next.preferTools = true;
  }

  next.mutationRate = Math.min(1, Math.max(0.05, next.mutationRate));
  next.executionPriority = interpretProfilePhrase(next.executionPriority).profile ?? next.executionPriority;
  return next;
}

function buildArchiveEntry(
  family: EvolutionFamily,
  content: string,
  taskFamily: string,
  score: number,
  metadata: Record<string, unknown>,
  entries: ArchiveEntry[]
): ArchiveEntry {
  const phenotype = heuristicPhenotype(content, score, metadata);
  const threshold = thresholdsForEntries(entries);
  return {
    id: `${family}-${slugify(taskFamily)}-${Date.now()}`,
    family,
    taskFamily,
    content,
    score,
    phenotype,
    binKey: binKeyForPhenotype(phenotype, threshold),
    createdAt: new Date().toISOString(),
    active: true,
    model: typeof metadata.model === "string" ? metadata.model : "heuristic",
    metadata
  };
}

function chooseBanditArm(bandit: BanditState): string {
  const samples = Object.entries(bandit.arms).map(([id, arm]) => {
    const sample = sampleBeta(arm.alpha, arm.beta);
    return { id, sample };
  });
  samples.sort((left, right) => right.sample - left.sample);
  return samples[0]?.id ?? "openai";
}

function updateBandit(bandit: BanditState, modelId: string, success: boolean): BanditState {
  const arm = bandit.arms[modelId] ?? { alpha: 1, beta: 1 };
  return {
    arms: {
      ...bandit.arms,
      [modelId]: success ? { alpha: arm.alpha + 1, beta: arm.beta } : { alpha: arm.alpha, beta: arm.beta + 1 }
    }
  };
}

async function loadArchive(cwd: string): Promise<EvolutionArchiveState> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile<EvolutionArchiveState>(evolutionArchivePath(cwd), { entries: [] });
}

async function saveArchive(cwd: string, archive: EvolutionArchiveState): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFile(evolutionArchivePath(cwd), archive);
}

async function loadProfileStatsStore(cwd: string): Promise<Record<string, ProfileStatsEntry>> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile<Record<string, ProfileStatsEntry>>(evolutionProfileStatsPath(cwd), defaultProfileStats());
}

async function saveProfileStatsStore(cwd: string, stats: Record<string, ProfileStatsEntry>): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFile(evolutionProfileStatsPath(cwd), stats);
}

async function loadStateRaw(cwd: string): Promise<EvolutionState> {
  await ensureChrysalisDirs(cwd);
  const state = await readJsonFile<EvolutionState>(evolutionStatePath(cwd), defaultEvolutionState());
  state.harness = state.harness ?? cloneHarness(DEFAULT_HARNESS);
  state.bandit = state.bandit ?? cloneBandit(DEFAULT_BANDIT);
  state.noveltyArchive = Array.isArray(state.noveltyArchive) ? state.noveltyArchive : [];
  state.currentSystemPrompt = state.currentSystemPrompt?.trim() ? state.currentSystemPrompt : defaultSystemPrompt();
  state.currentMetaPrompt = state.currentMetaPrompt?.trim() ? state.currentMetaPrompt : defaultMetaPrompt();
  state.autonomousRuns = typeof state.autonomousRuns === "number" ? state.autonomousRuns : 0;
  return state;
}

async function saveStateRaw(cwd: string, state: EvolutionState): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFile(evolutionStatePath(cwd), state);
}

export async function loadEvolutionState(cwd: string): Promise<EvolutionState> {
  const state = await loadStateRaw(cwd);
  const systemPromptPath = evolutionSystemPromptPath(cwd);
  const metaPromptPath = evolutionMetaPromptPath(cwd);
  const repoPromptPath = join(cwd, "SYSTEM.md");
  if (existsSync(systemPromptPath)) {
    state.currentSystemPrompt = await readTextOrDefaultAsync(systemPromptPath, state.currentSystemPrompt);
  } else if (existsSync(repoPromptPath)) {
    state.currentSystemPrompt = await readTextOrDefaultAsync(repoPromptPath, state.currentSystemPrompt);
  }
  if (existsSync(metaPromptPath)) {
    state.currentMetaPrompt = await readTextOrDefaultAsync(metaPromptPath, state.currentMetaPrompt);
  }
  return state;
}

export async function saveEvolutionState(cwd: string, state: EvolutionState): Promise<EvolutionState> {
  const next = { ...state, updatedAt: new Date().toISOString() };
  await saveStateRaw(cwd, next);
  await writeFile(evolutionSystemPromptPath(cwd), next.currentSystemPrompt.trim() + "\n", "utf8");
  await writeFile(evolutionMetaPromptPath(cwd), next.currentMetaPrompt.trim() + "\n", "utf8");
  return next;
}

export async function loadEffectiveSystemPrompt(cwd: string): Promise<string> {
  const state = await loadEvolutionState(cwd);
  return state.currentSystemPrompt;
}

export async function loadEffectiveMetaPrompt(cwd: string): Promise<string> {
  const state = await loadEvolutionState(cwd);
  return state.currentMetaPrompt;
}

async function llmRewritePrompt(
  family: EvolutionFamily,
  basePrompt: string,
  feedback: string,
  currentProfile: ChrysalisProfile
): Promise<{ prompt: string; rationale: string; model: string }> {
  const provider = resolveProviderConfig();
  if (!provider) {
    const additions = dedupe([
      ...phraseToSentences(feedback),
      "Keep the assistant terminal-first.",
      `Bias toward the ${currentProfile} profile.`,
      family === "meta" ? "Focus on rewriting the optimizer itself." : "Optimize for deterministic shell workflows."
    ]);
    return {
      prompt: appendInstructionBlock(basePrompt, feedback, additions),
      rationale: "heuristic mutation",
      model: "heuristic"
    };
  }

  try {
    const llm = ai({
      name: provider.provider,
      apiKey: provider.apiKey,
      ...(provider.model ? { model: provider.model } : {}),
      ...(provider.baseURL ? { baseURL: provider.baseURL } : {})
    } as any);

    const generator = ax(`
      family:string, currentPrompt:string, feedback:string, currentProfile:string ->
      prompt:string,
      rationale:string
    `);

    const result = await withTimeout(
      generator.forward(llm as any, {
        family,
        currentPrompt: basePrompt,
        feedback,
        currentProfile
      }),
      15000
    );

    return {
      prompt: result.prompt,
      rationale: result.rationale,
      model: provider.model ?? provider.provider
    };
  } catch {
    const additions = dedupe([
      ...phraseToSentences(feedback),
      "Keep the assistant terminal-first.",
      `Bias toward the ${currentProfile} profile.`,
      family === "meta" ? "Focus on rewriting the optimizer itself." : "Optimize for deterministic shell workflows."
    ]);
    return {
      prompt: appendInstructionBlock(basePrompt, feedback, additions),
      rationale: "heuristic fallback",
      model: "heuristic"
    };
  }
}

export async function evolveSystemPrompt(
  cwd: string,
  feedback: string,
  currentProfile: ChrysalisProfile
): Promise<{ state: EvolutionState; entry: ArchiveEntry; noveltyScore: number; rejected?: boolean }> {
  const archive = await loadArchive(cwd);
  const state = await loadEvolutionState(cwd);
  const firstRewrite = await llmRewritePrompt("prompt", state.currentSystemPrompt, feedback, currentProfile);
  let rewritten = firstRewrite;
  let noveltyScore = instructionNoveltyScore(state.noveltyArchive, rewritten.prompt);
  let accepted = novelEnough(state.noveltyArchive, rewritten.prompt);
  if (!accepted) {
    rewritten = await llmRewritePrompt(
      "prompt",
      state.currentSystemPrompt,
      `${feedback}\nRewrite from scratch. Avoid repeating previous wording. Keep the assistant terminal-first.`,
      currentProfile
    );
    noveltyScore = instructionNoveltyScore(state.noveltyArchive, rewritten.prompt);
    accepted = novelEnough(state.noveltyArchive, rewritten.prompt);
  }
  const entries = archive.entries;
  const score = scoreCandidate(rewritten.prompt, feedback, currentProfile);
  const entry = buildArchiveEntry(
    "prompt",
    rewritten.prompt,
    detectTaskType(feedback || "prompt evolution"),
    score,
    { feedback, currentProfile, rationale: rewritten.rationale, model: rewritten.model, noveltyScore, noveltyRejected: !accepted },
    entries
  );

  const nextState: EvolutionState = {
    ...state,
    currentSystemPrompt: rewritten.prompt,
    noveltyArchive: dedupe([rewritten.prompt, ...state.noveltyArchive]).slice(0, 100),
    updatedAt: new Date().toISOString()
  };

  archive.entries = [
    ...archive.entries.map((existing) => (existing.family === "prompt" ? { ...existing, active: false } : existing)),
    entry
  ];

  await saveArchive(cwd, archive);
  await saveEvolutionState(cwd, nextState);
  return { state: nextState, entry, noveltyScore, rejected: !accepted };
}

export async function evolveMetaPrompt(
  cwd: string,
  feedback: string,
  currentProfile: ChrysalisProfile
): Promise<{ state: EvolutionState; entry: ArchiveEntry; noveltyScore: number }> {
  const archive = await loadArchive(cwd);
  const state = await loadEvolutionState(cwd);
  let rewritten = await llmRewritePrompt("meta", state.currentMetaPrompt, feedback, currentProfile);
  let score = scoreCandidate(rewritten.prompt, feedback, currentProfile);
  let noveltyScore = instructionNoveltyScore(state.noveltyArchive, rewritten.prompt);
  if (!novelEnough(state.noveltyArchive, rewritten.prompt)) {
    rewritten = await llmRewritePrompt(
      "meta",
      state.currentMetaPrompt,
      `${feedback}\nRewrite from scratch. Avoid repeating previous wording. Focus on the optimizer itself.`,
      currentProfile
    );
    score = scoreCandidate(rewritten.prompt, feedback, currentProfile);
    noveltyScore = instructionNoveltyScore(state.noveltyArchive, rewritten.prompt);
  }
  const entry = buildArchiveEntry(
    "meta",
    rewritten.prompt,
    detectTaskType(feedback || "meta evolution"),
    score,
    { feedback, currentProfile, rationale: rewritten.rationale, model: rewritten.model, noveltyScore },
    archive.entries
  );

  const nextState: EvolutionState = {
    ...state,
    currentMetaPrompt: rewritten.prompt,
    noveltyArchive: dedupe([rewritten.prompt, ...state.noveltyArchive]).slice(0, 100),
    updatedAt: new Date().toISOString()
  };

  archive.entries = [...archive.entries, entry];
  await saveArchive(cwd, archive);
  await saveEvolutionState(cwd, nextState);
  return { state: nextState, entry, noveltyScore };
}

export async function evolveHarnessStrategy(
  cwd: string,
  feedback: string,
  currentProfile: ChrysalisProfile
): Promise<{ state: EvolutionState; harness: HarnessStrategy }> {
  const state = await loadEvolutionState(cwd);
  const signals = detectHarnessSignals([feedback, state.currentSystemPrompt, state.currentMetaPrompt].join("\n"));
  let next = mutateHarnessFromSignals(state.harness, signals, currentProfile);
  const profileOverride = interpretProfilePhrase(feedback).profile;
  if (profileOverride && profileOverride !== next.executionPriority) {
    next.executionPriority = profileOverride;
  }

  const nextState: EvolutionState = {
    ...state,
    harness: next,
    updatedAt: new Date().toISOString()
  };

  await saveEvolutionState(cwd, nextState);
  return { state: nextState, harness: next };
}

export async function loadEvolutionArchive(cwd: string): Promise<ArchiveEntry[]> {
  const archive = await loadArchive(cwd);
  return archive.entries.sort((left, right) => right.createdAt.localeCompare(left.createdAt));
}

export async function listEvolutionBins(cwd: string): Promise<Record<string, ArchiveEntry>> {
  const entries = await loadEvolutionArchive(cwd);
  const map: Record<string, ArchiveEntry> = {};
  for (const entry of entries) {
    if (!map[entry.binKey] || map[entry.binKey].score < entry.score) {
      map[entry.binKey] = entry;
    }
  }
  return map;
}

export async function recordEvolutionEvaluation(cwd: string, record: EvaluationRecord): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await appendFile(evolutionEvalPath(cwd), `${JSON.stringify(record)}\n`, "utf8");

  const stats = await loadProfileStatsStore(cwd);
  const profileName = typeof record.profile === "string" ? record.profile : String(record.profile);
  const current = stats[profileName] ?? { total: 0, success: 0, successRate: 0, taskTypes: {}, toolFreq: {} };

  current.total += 1;
  current.success += record.success ? 1 : 0;
  current.successRate = current.success / current.total;
  current.taskTypes[record.taskType] = (current.taskTypes[record.taskType] ?? 0) + 1;
  for (const tool of record.toolsUsed) {
    current.toolFreq[tool] = (current.toolFreq[tool] ?? 0) + 1;
  }
  stats[profileName] = current;
  await saveProfileStatsStore(cwd, stats);

  const state = await loadEvolutionState(cwd);
  if (record.model) {
    state.bandit = {
      arms: {
        ...state.bandit.arms,
        [record.model]: record.success
          ? {
              alpha: (state.bandit.arms[record.model]?.alpha ?? 1) + 1,
              beta: state.bandit.arms[record.model]?.beta ?? 1
            }
          : {
              alpha: state.bandit.arms[record.model]?.alpha ?? 1,
              beta: (state.bandit.arms[record.model]?.beta ?? 1) + 1
            }
      }
    };
    await saveEvolutionState(cwd, state);
  }
}

export async function suggestProfileFromStats(cwd: string, taskType: string): Promise<{ profile: ChrysalisProfile; score: number }> {
  const stats = await loadProfileStatsStore(cwd);
  let bestProfile: ChrysalisProfile = "best";
  let bestScore = 0;

  for (const [profileName, data] of Object.entries(stats)) {
    if (!(taskType in data.taskTypes) && !Object.keys(data.taskTypes).includes(taskType)) continue;
    if (data.successRate >= bestScore) {
      bestProfile = profileName as ChrysalisProfile;
      bestScore = data.successRate;
    }
  }

  return { profile: bestProfile, score: bestScore };
}

export function chooseExecutionModel(state: EvolutionState): string {
  return chooseBanditArm(state.bandit);
}

export function summarizeEvolutionState(state: EvolutionState): string[] {
  return [
    `system_prompt_chars=${state.currentSystemPrompt.length}`,
    `meta_prompt_chars=${state.currentMetaPrompt.length}`,
    `harness_priority=${state.harness.executionPriority}`,
    `harness_strategy=${state.harness.strategyType}`,
    `bandit_arms=${Object.keys(state.bandit.arms).length}`,
    `novelty_entries=${state.noveltyArchive.length}`
  ];
}

export async function ensureEvolutionBootstrap(cwd: string): Promise<EvolutionState> {
  await ensureChrysalisDirs(cwd);
  const state = await loadEvolutionState(cwd);
  const archive = await loadArchive(cwd);
  if (archive.entries.length === 0) {
    const initialEntry = buildArchiveEntry(
      "prompt",
      state.currentSystemPrompt,
      "build",
      5,
      { model: "bootstrap", rationale: "initial state" },
      []
    );
    archive.entries.push(initialEntry);
    await saveArchive(cwd, archive);
  }
  return state;
}

export async function loadEvolutionSummary(cwd: string): Promise<{
  state: EvolutionState;
  archive: ArchiveEntry[];
  bins: Record<string, ArchiveEntry>;
  profileStats: Record<string, ProfileStatsEntry>;
}> {
  const state = await loadEvolutionBootstrap(cwd);
  const archive = await loadEvolutionArchive(cwd);
  const bins = await listEvolutionBins(cwd);
  const profileStats = await loadProfileStatsStore(cwd);
  return { state, archive, bins, profileStats };
}

async function loadEvolutionBootstrap(cwd: string): Promise<EvolutionState> {
  return ensureEvolutionBootstrap(cwd);
}

export async function getCurrentSystemPromptPath(cwd: string): Promise<string> {
  await ensureChrysalisDirs(cwd);
  return evolutionSystemPromptPath(cwd);
}

export async function getCurrentMetaPromptPath(cwd: string): Promise<string> {
  await ensureChrysalisDirs(cwd);
  return evolutionMetaPromptPath(cwd);
}

export async function getEvolutionDirectory(cwd: string): Promise<string> {
  await ensureChrysalisDirs(cwd);
  return evolutionDir(cwd);
}

function summarizeTrigger(trigger: AutonomousEvolutionTrigger): string {
  const parts: string[] = [trigger.kind];
  if (trigger.taskType) parts.push(`taskType=${trigger.taskType}`);
  if (trigger.profile) parts.push(`profile=${trigger.profile}`);
  if (trigger.task) parts.push(`task=${trigger.task.slice(0, 120)}`);
  if (trigger.planSummary) parts.push(`plan=${trigger.planSummary.slice(0, 160)}`);
  return parts.join(" | ");
}

function heuristicAutonomousDecision(state: EvolutionState, trigger: AutonomousEvolutionTrigger): AutonomousEvolutionDecision {
  const text = [trigger.task ?? "", trigger.planSummary ?? "", trigger.taskType ?? "", trigger.profile ?? ""]
    .join(" ")
    .toLowerCase();
  const systemPressure =
    /migration|refactor|review|rewrite|port|terminal|tool|prompt/.test(text) || state.currentSystemPrompt.length < 1200;
  const metaPressure = /optimiz|judge|evolve|feedback|archive|strategy/.test(text) || state.currentMetaPrompt.length < 240;
  const harnessPressure =
    /fast|cheap|budget|cost|latency|tool|shell|terminal|workflow/.test(text) || state.harness.mutationRate > 0.25;

  return {
    shouldEvolveSystem: systemPressure,
    shouldEvolveMeta: metaPressure && trigger.kind !== "session_start",
    shouldMutateHarness: harnessPressure,
    reason: systemPressure || metaPressure || harnessPressure ? "heuristic autonomy triggered" : "heuristic autonomy held steady",
    focus: dedupe([
      systemPressure ? "system prompt" : "",
      metaPressure ? "meta prompt" : "",
      harnessPressure ? "harness strategy" : ""
    ])
  };
}

async function llmAutonomousDecision(
  cwd: string,
  state: EvolutionState,
  trigger: AutonomousEvolutionTrigger
): Promise<AutonomousEvolutionDecision> {
  const provider = resolveProviderConfig(chooseExecutionModel(state));
  if (!provider) {
    return heuristicAutonomousDecision(state, trigger);
  }

  try {
    const llm = ai({
      name: provider.provider,
      apiKey: provider.apiKey,
      ...(provider.model ? { model: provider.model } : {}),
      ...(provider.baseURL ? { baseURL: provider.baseURL } : {})
    } as any);

    const decider = ax(`
      trigger:string, systemPrompt:string, metaPrompt:string, harness:string, archiveCount:number, lastRun:string ->
      shouldEvolveSystem:boolean,
      shouldEvolveMeta:boolean,
      shouldMutateHarness:boolean,
      reason:string,
      focus:string[]
    `);

    const result = await withTimeout(
      decider.forward(llm as any, {
        trigger: summarizeTrigger(trigger),
        systemPrompt: state.currentSystemPrompt,
        metaPrompt: state.currentMetaPrompt,
        harness: JSON.stringify(state.harness),
        archiveCount: state.noveltyArchive.length,
        lastRun: state.lastAutonomousRunAt ?? ""
      }),
      10000
    );

    return {
      shouldEvolveSystem: Boolean(result.shouldEvolveSystem),
      shouldEvolveMeta: Boolean(result.shouldEvolveMeta),
      shouldMutateHarness: Boolean(result.shouldMutateHarness),
      reason: typeof result.reason === "string" && result.reason.trim() ? result.reason.trim() : "model decision",
      focus: Array.isArray(result.focus) ? dedupe(result.focus.map((item) => String(item).trim())) : []
    };
  } catch {
    return heuristicAutonomousDecision(state, trigger);
  }
}

async function bumpAutonomousRunState(cwd: string, reason: string): Promise<EvolutionState> {
  const state = await loadEvolutionState(cwd);
  const updated: EvolutionState = {
    ...state,
    autonomousRuns: state.autonomousRuns + 1,
    lastAutonomousRunAt: new Date().toISOString(),
    lastAutonomousReason: reason,
    updatedAt: new Date().toISOString()
  };
  await saveEvolutionState(cwd, updated);
  return updated;
}

export async function runAutonomousEvolution(
  cwd: string,
  trigger: AutonomousEvolutionTrigger
): Promise<AutonomousEvolutionReport> {
  const state = await loadEvolutionState(cwd);
  const now = Date.now();
  const lastRun = state.lastAutonomousRunAt ? Date.parse(state.lastAutonomousRunAt) : 0;
  const cooldownMs = trigger.kind === "session_start" ? 6 * 60 * 60 * 1000 : 60 * 60 * 1000;

  if (!trigger.force && lastRun && Number.isFinite(lastRun) && now - lastRun < cooldownMs) {
    return {
      decision: {
        shouldEvolveSystem: false,
        shouldEvolveMeta: false,
        shouldMutateHarness: false,
        reason: `cooldown active for ${Math.max(1, Math.ceil((cooldownMs - (now - lastRun)) / 60000))} minutes`,
        focus: []
      },
      applied: false,
      skippedReason: "cooldown",
      results: []
    };
  }

  const decision = await llmAutonomousDecision(cwd, state, trigger);
  const results: AutonomousEvolutionReport["results"] = [];
  let applied = false;

  if (decision.shouldEvolveSystem) {
    const profile = trigger.profile ?? (await suggestProfileFromStats(cwd, trigger.taskType ?? "build")).profile;
    const feedback = trigger.planSummary || trigger.task || decision.reason;
    const outcome = await evolveSystemPrompt(cwd, feedback, profile);
    results.push({
      target: "system",
      status: "applied",
      detail: `${outcome.noveltyScore.toFixed(3)}${outcome.rejected ? " (low novelty)" : ""}`
    });
    applied = true;
  }

  if (decision.shouldEvolveMeta) {
    const profile = trigger.profile ?? (await suggestProfileFromStats(cwd, trigger.taskType ?? "build")).profile;
    const feedback = trigger.planSummary || trigger.task || decision.reason;
    const outcome = await evolveMetaPrompt(cwd, feedback, profile);
    results.push({
      target: "meta",
      status: "applied",
      detail: outcome.noveltyScore.toFixed(3)
    });
    applied = true;
  }

  if (decision.shouldMutateHarness) {
    const profile = trigger.profile ?? (await suggestProfileFromStats(cwd, trigger.taskType ?? "build")).profile;
    const feedback = trigger.planSummary || trigger.task || decision.reason;
    const outcome = await evolveHarnessStrategy(cwd, feedback, profile);
    results.push({
      target: "harness",
      status: "applied",
      detail: `${outcome.harness.executionPriority}/${outcome.harness.strategyType}`
    });
    applied = true;
  }

  if (!applied) {
    return {
      decision,
      applied: false,
      results: [
        {
          target: "autonomy",
          status: "skipped",
          detail: decision.reason
        }
      ]
    };
  }

  await bumpAutonomousRunState(cwd, decision.reason);
  return {
    decision,
    applied: true,
    results
  };
}
