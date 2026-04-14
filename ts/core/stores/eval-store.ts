import { readFile, appendFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";

import { ensureChrysalisDirs, evalStorePath, evalProfileStatsPath } from "../paths.js";
import { type ChrysalisProfile } from "../types.js";

export interface EvalRecord {
  ts: number;
  taskId: string;
  success: boolean;
  profile: string;
  taskType: string;
  toolsUsed: string[];
  durationMs: number;
  feedback: string;
  candidateId?: string | null;
  evalStage: string;
}

export interface EvalProfileStats {
  total: number;
  success: number;
  successRate: number;
  taskTypes: Record<string, number>;
  toolFreq: Record<string, number>;
}

async function readJsonFile<T>(path: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch {
    return fallback;
  }
}

async function writeJsonFile(path: string, value: unknown): Promise<void> {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function loadProfileStats(cwd: string): Promise<Record<string, EvalProfileStats>> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile(evalProfileStatsPath(cwd), {});
}

async function saveProfileStats(cwd: string, stats: Record<string, EvalProfileStats>): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFile(evalProfileStatsPath(cwd), stats);
}

export async function logEval(cwd: string, record: Omit<EvalRecord, "ts">): Promise<void> {
  await ensureChrysalisDirs(cwd);
  const entry: EvalRecord = { ...record, ts: Math.floor(Date.now() / 1000) };
  await appendFile(evalStorePath(cwd), `${JSON.stringify(entry)}\n`, "utf8");
  await updateProfileStats(cwd, record.profile, record.success, record.taskType, record.toolsUsed);
}

async function updateProfileStats(cwd: string, profile: string, success: boolean, taskType: string, toolsUsed: string[]): Promise<void> {
  const stats = await loadProfileStats(cwd);
  const current = stats[profile] ?? { total: 0, success: 0, successRate: 0, taskTypes: {}, toolFreq: {} };
  current.total += 1;
  current.success += success ? 1 : 0;
  current.successRate = current.success / current.total;
  current.taskTypes[taskType] = (current.taskTypes[taskType] ?? 0) + 1;
  for (const tool of toolsUsed) {
    current.toolFreq[tool] = (current.toolFreq[tool] ?? 0) + 1;
  }
  stats[profile] = current;
  await saveProfileStats(cwd, stats);
}

export async function getProfileStats(cwd: string, profile?: string): Promise<EvalProfileStats | Record<string, EvalProfileStats>> {
  const stats = await loadProfileStats(cwd);
  if (profile) return stats[profile] ?? { total: 0, success: 0, successRate: 0, taskTypes: {}, toolFreq: {} };
  return stats;
}

export async function getToolStats(cwd: string): Promise<Record<string, number>> {
  const stats = await loadProfileStats(cwd);
  const allFreq: Record<string, number> = {};
  for (const data of Object.values(stats)) {
    for (const [tool, count] of Object.entries(data.toolFreq)) {
      allFreq[tool] = (allFreq[tool] ?? 0) + count;
    }
  }
  return allFreq;
}

export async function suggestProfile(cwd: string, taskType: string): Promise<{ profile: string; rate: number }> {
  const stats = await loadProfileStats(cwd);
  let bestProfile = "best";
  let bestRate = 0;
  for (const [profileName, data] of Object.entries(stats)) {
    if (data.taskTypes[taskType] && data.successRate >= bestRate) {
      bestProfile = profileName;
      bestRate = data.successRate;
    }
  }
  return { profile: bestProfile, rate: bestRate };
}

export async function evolveProfile(cwd: string, profileName: string, threshold = 0.7): Promise<{
  profile: string;
  successRate: number;
  recommendedTools: string[];
  evaluation: string;
}> {
  const allStats = await loadProfileStats(cwd);
  const stats = allStats[profileName];
  if (!stats) throw new Error(`Unknown profile: ${profileName}`);
  const sorted = Object.entries(stats.toolFreq).sort(([, a], [, b]) => b - a);
  const topTools = sorted.slice(0, 5).map(([tool]) => tool);
  return {
    profile: profileName,
    successRate: stats.successRate,
    recommendedTools: topTools,
    evaluation: stats.successRate >= threshold ? "stable" : "needs_improvement"
  };
}
