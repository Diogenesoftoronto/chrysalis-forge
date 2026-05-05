import { ai, ax } from "@ax-llm/ax";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type ToolDefinition, type ToolExecutor } from "./tool-registry.js";
import { slugify } from "../util.js";

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

export interface EvolvableToolField {
  path: string;
  current: string;
  mutations: Array<{ value: string; score: number; ts: number }>;
}

export interface ToolVariant {
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

export interface ToolEvolutionState {
  variants: Record<string, ToolVariant[]>;
  fieldHistory: Record<string, EvolvableToolField>;
  updatedAt: string;
}

const TOOL_EVOLUTION_PROMPT = `You are Chrysalis's tool evolution optimizer.
Given a tool's current definition and feedback about how it should improve, generate an evolved version.
Focus on making descriptions clearer, parameters more precise, and defaults more useful.
Return only the JSON without commentary.`;

export function ngramDistance(a: string, b: string, n = 3): number {
  if (!a || !b) return a === b ? 0 : 1;
  const gramsA = new Set<string>();
  const gramsB = new Set<string>();
  const normA = a.toLowerCase().trim();
  const normB = b.toLowerCase().trim();
  for (let i = 0; i <= normA.length - n; i++) gramsA.add(normA.slice(i, i + n));
  for (let i = 0; i <= normB.length - n; i++) gramsB.add(normB.slice(i, i + n));
  let intersection = 0;
  for (const g of gramsA) if (gramsB.has(g)) intersection++;
  const union = new Set([...gramsA, ...gramsB]).size;
  return union === 0 ? 0 : 1 - intersection / union;
}

export function toolNoveltyScore(existing: ToolVariant[], candidate: string): number {
  if (existing.length === 0) return 1;
  let best = 0;
  for (const variant of existing) {
    const descDist = ngramDistance(variant.description, candidate);
    best = Math.max(best, descDist);
  }
  return best;
}

export function defaultToolEvolutionState(): ToolEvolutionState {
  return { variants: {}, fieldHistory: {}, updatedAt: new Date().toISOString() };
}

export function loadToolEvolutionState(cwd: string): ToolEvolutionState {
  const path = join(cwd, ".chrysalis", "state", "tool-evolution.json");
  if (!existsSync(path)) return defaultToolEvolutionState();
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return defaultToolEvolutionState();
  }
}

export function saveToolEvolutionState(cwd: string, state: ToolEvolutionState): void {
  const dir = join(cwd, ".chrysalis", "state");
  writeFileSync(join(dir, "tool-evolution.json"), JSON.stringify(state, null, 2), "utf8");
}

export async function evolveToolDescription(
  tool: ToolDefinition,
  feedback: string,
  providerOverride?: string
): Promise<{ description: string; noveltyScore: number; model: string }> {
  const provider = resolveProviderConfig(providerOverride);
  const currentDesc = tool.description;
  const currentParams = JSON.stringify(tool.parameters);

  if (!provider) {
    const evolved = `${currentDesc} ${feedback}`.slice(0, 500);
    return { description: evolved, noveltyScore: 0.3, model: "heuristic" };
  }

  try {
    const llm = ai({
      name: provider.provider,
      apiKey: provider.apiKey,
      ...(provider.model ? { model: provider.model } : {}),
      ...(provider.baseURL ? { baseURL: provider.baseURL } : {})
    } as any);

    const evolver = ax(`
      currentDescription:string, currentParameters:string, feedback:string ->
      description:string,
      parameters:{ type:string, properties:Record<string, unknown>, required?:string[] }
    `);

    const result = await withTimeout(
      evolver.forward(llm as any, { currentDescription: currentDesc, currentParameters: currentParams, feedback }),
      20000
    );

    const novelty = toolNoveltyScore([], result.description ?? currentDesc);
    return {
      description: result.description ?? currentDesc,
      noveltyScore: novelty,
      model: provider.model ?? provider.provider
    };
  } catch {
    return { description: `${currentDesc} ${feedback}`.slice(0, 500), noveltyScore: 0.2, model: "heuristic-fallback" };
  }
}

export async function evolveToolParameters(
  tool: ToolDefinition,
  feedback: string,
  providerOverride?: string
): Promise<{ parameters: Record<string, unknown>; noveltyScore: number; model: string }> {
  const provider = resolveProviderConfig(providerOverride);
  const currentParams = JSON.stringify(tool.parameters);

  if (!provider) {
    const evolved = { type: "object", properties: tool.parameters.properties ?? {}, required: tool.parameters.required ?? [] };
    return { parameters: evolved, noveltyScore: 0.3, model: "heuristic" };
  }

  try {
    const llm = ai({
      name: provider.provider,
      apiKey: provider.apiKey,
      ...(provider.model ? { model: provider.model } : {}),
      ...(provider.baseURL ? { baseURL: provider.baseURL } : {})
    } as any);

    const evolver = ax(`
      toolName:string, currentParameters:string, feedback:string ->
      properties:Record<string, { type:string, description?:string, default?:unknown }>,
      required:string[],
      newProperties:Record<string, unknown>
    `);

    const result = await withTimeout(
      evolver.forward(llm as any, { toolName: tool.name, currentParameters: currentParams, feedback }),
      20000
    );

    const novelty = toolNoveltyScore([], JSON.stringify(result));
    return {
      parameters: {
        type: "object",
        properties: result.properties ?? tool.parameters.properties ?? {},
        required: result.required ?? tool.parameters.required ?? []
      },
      noveltyScore: novelty,
      model: provider.model ?? provider.provider
    };
  } catch {
    return { parameters: tool.parameters, noveltyScore: 0.2, model: "heuristic-fallback" };
  }
}

export async function evolveTool(
  cwd: string,
  toolName: string,
  tool: { name: string; description: string; parameters: { type: string; properties: Record<string, unknown>; required?: string[] } },
  feedback: string,
  field?: "description" | "parameters" | "both",
  threshold = 0.25,
  providerOverride?: string
): Promise<{ variant: ToolVariant; rejected: boolean }> {
  const state = loadToolEvolutionState(cwd);
  const existing = state.variants[toolName] ?? [];
  const fieldMode = field ?? "both";

  let description = tool.description;
  let parameters: { type: string; properties: Record<string, unknown>; required?: string[] } = tool.parameters;
  let noveltyScore = 0;
  let model = "unchanged";

  if (fieldMode === "description" || fieldMode === "both") {
    const descResult = await evolveToolDescription(tool, feedback, providerOverride);
    description = descResult.description;
    noveltyScore = Math.max(noveltyScore, descResult.noveltyScore);
    model = descResult.model;
  }

  if (fieldMode === "parameters" || fieldMode === "both") {
    const paramResult = await evolveToolParameters(tool, feedback, providerOverride);
    parameters = paramResult.parameters as { type: string; properties: Record<string, unknown>; required?: string[] };
    noveltyScore = Math.max(noveltyScore, paramResult.noveltyScore);
    if (paramResult.model !== "heuristic") model = paramResult.model;
  }

  const rejected = noveltyScore < threshold;

  const variant: ToolVariant = {
    id: `${toolName}-${slugify(description.slice(0, 30))}-${Date.now()}`,
    toolName,
    description,
    parameters,
    active: !rejected,
    score: noveltyScore * 10,
    noveltyScore,
    createdAt: new Date().toISOString(),
    model,
    feedback
  };

  if (!state.variants[toolName]) state.variants[toolName] = [];
  state.variants[toolName].push(variant);
  state.updatedAt = new Date().toISOString();
  saveToolEvolutionState(cwd, state);

  return { variant, rejected };
}

export function getActiveToolVariant(cwd: string, toolName: string): ToolDefinition | null {
  const state = loadToolEvolutionState(cwd);
  const variants = state.variants[toolName] ?? [];
  const active = variants.filter(v => v.active);
  if (active.length === 0) return null;
  active.sort((a, b) => b.score - a.score);
  const latest = active[0];
  return {
    name: toolName,
    description: latest.description,
    parameters: latest.parameters as any,
    execute: undefined
  };
}

export function listToolVariants(cwd: string, toolName?: string): ToolVariant[] {
  const state = loadToolEvolutionState(cwd);
  if (toolName) return state.variants[toolName] ?? [];
  return Object.entries(state.variants).flatMap(([name, variants]) =>
    variants.map(v => ({ ...v, toolName: name }))
  );
}

export function archiveToolVariant(cwd: string, variantId: string): boolean {
  const state = loadToolEvolutionState(cwd);
  for (const variants of Object.values(state.variants)) {
    const idx = variants.findIndex(v => v.id === variantId);
    if (idx >= 0) {
      variants[idx].active = false;
      state.updatedAt = new Date().toISOString();
      saveToolEvolutionState(cwd, state);
      return true;
    }
  }
  return false;
}

export function selectToolVariant(cwd: string, variantId: string): boolean {
  const state = loadToolEvolutionState(cwd);
  for (const [name, variants] of Object.entries(state.variants)) {
    const idx = variants.findIndex(v => v.id === variantId);
    if (idx >= 0) {
      for (let i = 0; i < variants.length; i++) {
        variants[i].active = i === idx;
      }
      state.updatedAt = new Date().toISOString();
      saveToolEvolutionState(cwd, state);
      return true;
    }
  }
  return false;
}

export function toolEvolutionStats(cwd: string): string {
  const state = loadToolEvolutionState(cwd);
  const lines: string[] = [];
  lines.push(`Tool Evolution State (updated: ${state.updatedAt})`);
  for (const [name, variants] of Object.entries(state.variants)) {
    const active = variants.filter(v => v.active).length;
    const total = variants.length;
    lines.push(`  ${name}: ${active}/${total} active variants`);
  }
  if (Object.keys(state.variants).length === 0) {
    lines.push("  No evolved tool variants yet.");
  }
  return lines.join("\n");
}
