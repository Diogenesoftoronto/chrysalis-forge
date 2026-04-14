import { ai, ax } from "@ax-llm/ax";

import { chooseExecutionModel, loadEvolutionState } from "./evolution.js";
import { interpretProfilePhrase } from "./priority.js";
import { dedupe } from "./util.js";
import { type ChrysalisProfile, type ChrysalisTaskType, type TaskPlan } from "./types.js";

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

function detectTaskType(task: string): ChrysalisTaskType {
  const normalized = task.toLowerCase();
  if (/\bmigrat|rewrite|replace|port\b/.test(normalized)) return "migration";
  if (/\bbug|fix|failing|regression|broken\b/.test(normalized)) return "bugfix";
  if (/\brefactor|cleanup|simplify|reshape\b/.test(normalized)) return "refactor";
  if (/\breview|audit|inspect\b/.test(normalized)) return "review";
  if (/\bresearch|investigate|compare|explore\b/.test(normalized)) return "research";
  return "build";
}

function heuristicPlan(task: string): TaskPlan {
  const taskType = detectTaskType(task);
  const recommendedProfile = interpretProfilePhrase(task).profile;
  const deliverables = dedupe([
    taskType === "migration" ? "migration scaffold and compatibility notes" : "",
    taskType === "review" ? "ranked findings with concrete references" : "",
    taskType === "bugfix" ? "targeted fix with regression coverage" : "",
    "verified terminal-first implementation path"
  ]);
  const risks = dedupe([
    taskType === "migration" ? "runtime and packaging drift while two implementations coexist" : "",
    taskType === "review" ? "missing hidden behavior coupled to the legacy runtime" : "",
    "tooling assumptions that differ between Pi and the legacy Chrysalis runtime"
  ]);
  const firstSteps = dedupe([
    "inspect the current runtime surface and identify the smallest shippable terminal slice",
    "wire Pi prompts, skills, and extension commands before porting advanced runtime features",
    "verify the launcher and artifact paths with a real shell run"
  ]);

  return {
    summary: `Plan the task as a ${taskType} with a terminal-first delivery bias.`,
    taskType,
    recommendedProfile,
    deliverables,
    risks,
    firstSteps,
    mode: "heuristic"
  };
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

  if (configs.openai) {
    return configs.openai;
  }
  return configs.anthropic ?? configs["google-gemini"] ?? null;
}

export async function createTaskPlan(task: string, cwd: string, currentProfile: ChrysalisProfile): Promise<TaskPlan> {
  const fallback = heuristicPlan(task);
  const evolution = await loadEvolutionState(cwd);
  const provider = resolveProviderConfig(chooseExecutionModel(evolution));
  if (!provider) return fallback;

  try {
    const llm = ai({
      name: provider.provider,
      apiKey: provider.apiKey,
      ...(provider.model ? { model: provider.model } : {}),
      ...(provider.baseURL ? { baseURL: provider.baseURL } : {})
    } as any);

    const planner = ax(`
      task:string, cwd:string, currentProfile:string, systemPrompt:string, harness:string ->
      summary:string,
      taskType:class "build, bugfix, refactor, review, research, migration",
      recommendedProfile:class "fast, cheap, best, verbose",
      deliverables:string[],
      risks:string[],
      firstSteps:string[]
    `);

    const result = await withTimeout(
      planner.forward(llm as any, {
      task,
      cwd,
      currentProfile,
      systemPrompt: evolution.currentSystemPrompt,
      harness: JSON.stringify(evolution.harness)
      }),
      15000
    );

    return {
      summary: result.summary,
      taskType: result.taskType,
      recommendedProfile: result.recommendedProfile,
      deliverables: dedupe(result.deliverables),
      risks: dedupe(result.risks),
      firstSteps: dedupe(result.firstSteps),
      mode: "ax",
      systemPrompt: evolution.currentSystemPrompt,
      harness: evolution.harness
    };
  } catch {
    return {
      ...fallback,
      systemPrompt: evolution.currentSystemPrompt,
      harness: evolution.harness
    };
  }
}
