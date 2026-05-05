import { readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";

import { ensureChrysalisDirs, sessionStatsPath } from "../paths.js";
import { type SessionStats } from "../types.js";

function defaultStats(): SessionStats {
  return {
    startTime: Date.now(),
    turns: 0,
    tokensIn: 0,
    tokensOut: 0,
    totalCost: 0,
    filesWritten: [],
    filesRead: [],
    toolsUsed: {}
  };
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

export async function loadSessionStats(cwd: string): Promise<SessionStats> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile<SessionStats>(sessionStatsPath(cwd), defaultStats());
}

export async function saveSessionStats(cwd: string, stats: SessionStats): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFile(sessionStatsPath(cwd), stats);
}

export async function resetSessionStats(cwd: string): Promise<SessionStats> {
  const stats = defaultStats();
  await saveSessionStats(cwd, stats);
  return stats;
}

export async function addTurn(
  cwd: string,
  opts: { tokensIn?: number; tokensOut?: number; cost?: number }
): Promise<SessionStats> {
  const stats = await loadSessionStats(cwd);
  stats.turns += 1;
  stats.tokensIn += opts.tokensIn ?? 0;
  stats.tokensOut += opts.tokensOut ?? 0;
  stats.totalCost += opts.cost ?? 0;
  await saveSessionStats(cwd, stats);
  return stats;
}

export async function addTokens(cwd: string, tokensIn: number, tokensOut: number): Promise<SessionStats> {
  const stats = await loadSessionStats(cwd);
  stats.tokensIn += tokensIn;
  stats.tokensOut += tokensOut;
  await saveSessionStats(cwd, stats);
  return stats;
}

export async function addCost(cwd: string, cost: number): Promise<SessionStats> {
  const stats = await loadSessionStats(cwd);
  stats.totalCost += cost;
  await saveSessionStats(cwd, stats);
  return stats;
}

export async function recordToolUse(cwd: string, toolName: string): Promise<SessionStats> {
  const stats = await loadSessionStats(cwd);
  stats.toolsUsed[toolName] = (stats.toolsUsed[toolName] ?? 0) + 1;
  await saveSessionStats(cwd, stats);
  return stats;
}

export async function recordFileOp(cwd: string, path: string, mode: "write" | "read"): Promise<SessionStats> {
  const stats = await loadSessionStats(cwd);
  const key = mode === "write" ? "filesWritten" : "filesRead";
  if (!stats[key].includes(path)) {
    stats[key].push(path);
  }
  await saveSessionStats(cwd, stats);
  return stats;
}

export function getSessionStatsDisplay(stats: SessionStats): Record<string, string | number> {
  const totalTokens = stats.tokensIn + stats.tokensOut;
  const elapsedSec = Math.round((Date.now() - stats.startTime) / 1000);
  return {
    turns: stats.turns,
    elapsedSec,
    tokensIn: stats.tokensIn,
    tokensOut: stats.tokensOut,
    totalTokens,
    totalCost: stats.totalCost,
    filesWritten: stats.filesWritten.length,
    filesRead: stats.filesRead.length
  };
}

export function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return `${n}`;
}

export function formatCost(c: number): string {
  if (c < 0.01) return `$${c.toFixed(4)}`;
  if (c < 1.0) return `$${c.toFixed(3)}`;
  return `$${c.toFixed(2)}`;
}
