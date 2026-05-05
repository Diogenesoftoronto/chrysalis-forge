import { ai, ax } from "@ax-llm/ax";
import { type SubtaskDefinition, type ToolProfile, type ChrysalisTaskType } from "./types.js";
import { loadArchive, recordPattern, saveArchive } from "./stores/decomp-archive.js";
import { type DecompPhenotype } from "./types.js";
import { slugify } from "./util.js";

const TASK_TYPE_KEYWORDS: Record<string, string[]> = {
  refactor: ["refactor", "restructure", "reorganize", "clean up"],
  implement: ["implement", "create", "build", "add", "write"],
  debug: ["debug", "fix", "bug", "error", "issue", "broken"],
  research: ["find", "search", "look", "analyze", "understand", "explain"],
  test: ["test", "verify", "check", "validate"],
  document: ["document", "docs", "readme", "comment"]
};

export function classifyTask(taskDescription: string): string {
  const lower = taskDescription.toLowerCase();
  for (const [type, keywords] of Object.entries(TASK_TYPE_KEYWORDS)) {
    if (keywords.some((kw) => lower.includes(kw))) return type;
  }
  return "general";
}

export function suggestProfileForSubtask(description: string): ToolProfile {
  const lower = description.toLowerCase();
  if (/read|search|find|analyze|understand/.test(lower)) return "researcher";
  if (/write|create|modify|edit|update|patch/.test(lower)) return "editor";
  if (/commit|git|jj|branch|merge/.test(lower)) return "vcs";
  return "all";
}

interface ProviderConfig {
  provider: string;
  apiKey: string;
  model?: string;
  baseURL?: string;
}

function resolveProviderConfig(preferredProvider?: string): ProviderConfig | null {
  const configs: Record<string, ProviderConfig | null> = {
    openai: process.env.OPENAI_API_KEY
      ? { provider: "openai", apiKey: process.env.OPENAI_API_KEY, model: process.env.OPENAI_MODEL ?? "gpt-5.4", baseURL: process.env.OPENAI_BASE_URL }
      : null,
    anthropic: process.env.ANTHROPIC_API_KEY
      ? { provider: "anthropic", apiKey: process.env.ANTHROPIC_API_KEY, model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-0" }
      : null,
    "google-gemini": process.env.GEMINI_API_KEY
      ? { provider: "google-gemini", apiKey: process.env.GEMINI_API_KEY, model: process.env.GEMINI_MODEL ?? "gemini-2.5-pro" }
      : null
  };
  if (preferredProvider && configs[preferredProvider]) return configs[preferredProvider];
  return configs.openai ?? configs.anthropic ?? configs["google-gemini"] ?? null;
}

async function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => { timer = setTimeout(() => reject(new Error(`Timed out after ${ms}ms`)), ms); })
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export async function decomposeTaskLLM(
  task: string,
  cwd: string,
  maxSubtasks = 4
): Promise<SubtaskDefinition[]> {
  const provider = resolveProviderConfig();
  if (!provider) return heuristicDecomposition(task, maxSubtasks);

  try {
    const llm = ai({
      name: provider.provider,
      apiKey: provider.apiKey,
      ...(provider.model ? { model: provider.model } : {}),
      ...(provider.baseURL ? { baseURL: provider.baseURL } : {})
    } as any);

    const decomposer = ax(`
      task:string, maxSubtasks:number ->
      subtasks:{ description:string, dependencies:number[], profileHint:"editor"|"researcher"|"vcs"|"all" }[]
    `);

    const result = await withTimeout(
      decomposer.forward(llm as any, { task, maxSubtasks }),
      20000
    );

    return (result.subtasks ?? []).slice(0, maxSubtasks).map((s: any) => ({
      description: String(s.description ?? ""),
      dependencies: Array.isArray(s.dependencies) ? s.dependencies.map(Number) : [],
      profileHint: ["editor", "researcher", "vcs", "all"].includes(s.profileHint) ? s.profileHint : "all"
    }));
  } catch {
    return heuristicDecomposition(task, maxSubtasks);
  }
}

export function heuristicDecomposition(task: string, maxSubtasks = 4): SubtaskDefinition[] {
  const taskType = classifyTask(task);
  const base: SubtaskDefinition[] = [
    { description: `Read and understand the current codebase relevant to: ${task}`, dependencies: [], profileHint: "researcher" },
    { description: `Implement changes for: ${task}`, dependencies: [0], profileHint: "editor" },
    { description: "Verify the changes work correctly", dependencies: [1], profileHint: "all" }
  ];

  if (taskType === "debug") {
    base.splice(1, 0, { description: `Identify the root cause of the issue: ${task}`, dependencies: [0], profileHint: "researcher" });
  }
  if (taskType === "refactor") {
    base.splice(1, 0, { description: `Plan the refactoring approach for: ${task}`, dependencies: [0], profileHint: "researcher" });
  }
  if (taskType === "research") {
    return [
      { description: `Search for relevant information about: ${task}`, dependencies: [], profileHint: "researcher" },
      { description: `Analyze and synthesize findings for: ${task}`, dependencies: [0], profileHint: "researcher" }
    ];
  }

  return base.slice(0, maxSubtasks);
}

export async function runDecomposition(
  cwd: string,
  task: string,
  taskType: ChrysalisTaskType | string
): Promise<{ subtasks: SubtaskDefinition[]; patternId: string }> {
  const subtasks = await decomposeTaskLLM(task, cwd);
  const patternId = `decomp-${slugify(task)}-${Date.now()}`;

  const archive = await loadArchive(cwd, taskType);
  const updated = recordPattern(archive, {
    id: patternId,
    name: task,
    steps: subtasks.map((s, i) => ({
      id: `step-${i}`,
      description: s.description,
      toolHints: [s.profileHint],
      dependencies: s.dependencies
    })),
    metadata: { taskType, createdAt: new Date().toISOString() }
  }, subtasks.length > 0 ? 5 : 0);
  await saveArchive(cwd, updated);

  return { subtasks, patternId };
}

export function shouldVote(task: string): boolean {
  const lower = task.toLowerCase();
  return /\breview|audit|judge|critique|verify|validate|confirm\b/.test(lower);
}
