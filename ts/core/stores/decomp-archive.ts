import { readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";

import { ensureChrysalisDirs, decompArchiveDir } from "../paths.js";
import {
  type DecompStep,
  type DecompositionPattern,
  type DecompPhenotype,
  type DecompositionArchive
} from "../types.js";

function emptyArchive(taskType: string): DecompositionArchive {
  return { taskType, archive: {}, pointCloud: [], defaultId: null };
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

function taskTypeFilename(taskType: string): string {
  return `${taskType.replace(/\//g, "_")}.json`;
}

function computePhenotype(pattern: DecompositionPattern): DecompPhenotype {
  const steps = pattern.steps;
  const n = steps.length;
  const depth = n === 0 ? 0 : 1 + Math.max(...steps.map((s) => s.dependencies.length));
  const allDeps = steps.flatMap((s) => s.dependencies);
  const uniqueDeps = new Set(allDeps);
  const parallelism = n - uniqueDeps.size;
  const allTools = steps.flatMap((s) => s.toolHints);
  const toolDiversity = new Set(allTools).size;
  return { depth, parallelism: Math.max(0, parallelism), toolDiversity, complexity: n };
}

function phenotypeBinKey(pheno: DecompPhenotype): string {
  return `d${pheno.depth}_p${pheno.parallelism}_t${pheno.toolDiversity}_c${pheno.complexity}`;
}

export async function loadArchive(cwd: string, taskType: string): Promise<DecompositionArchive> {
  await ensureChrysalisDirs(cwd);
  const path = join(decompArchiveDir(cwd), taskTypeFilename(taskType));
  if (!existsSync(path)) return emptyArchive(taskType);
  const raw = await readJsonFile<any>(path, null);
  if (!raw) return emptyArchive(taskType);
  const archive: Record<string, { score: number; pattern: DecompositionPattern }> = {};
  for (const [k, v] of Object.entries(raw.archive ?? {})) {
    const entry = v as any;
    archive[k] = { score: entry.score, pattern: entry.pattern };
  }
  const pointCloud: DecompositionArchive["pointCloud"] = (raw.point_cloud ?? []).map((e: any) => ({
    phenotype: e.phenotype,
    pattern: e.pattern
  }));
  return { taskType: raw.task_type ?? taskType, archive, pointCloud, defaultId: raw.default_id ?? null };
}

export async function saveArchive(cwd: string, arch: DecompositionArchive): Promise<void> {
  await ensureChrysalisDirs(cwd);
  const path = join(decompArchiveDir(cwd), taskTypeFilename(arch.taskType));
  const serialized = {
    task_type: arch.taskType,
    archive: Object.fromEntries(
      Object.entries(arch.archive).map(([k, v]) => [k, { score: v.score, pattern: v.pattern }])
    ),
    point_cloud: arch.pointCloud.map((e) => ({ phenotype: e.phenotype, pattern: e.pattern })),
    default_id: arch.defaultId
  };
  await writeJsonFile(path, serialized);
}

export async function listArchives(cwd: string): Promise<string[]> {
  await ensureChrysalisDirs(cwd);
  const dir = decompArchiveDir(cwd);
  const indexPath = join(dir, "index.json");
  if (!existsSync(indexPath)) return [];
  try {
    return Object.keys(JSON.parse(await readFile(indexPath, "utf8")));
  } catch {
    return [];
  }
}

export function recordPattern(
  archive: DecompositionArchive,
  pattern: DecompositionPattern,
  score: number
): DecompositionArchive {
  const pheno = computePhenotype(pattern);
  const binKey = phenotypeBinKey(pheno);
  const newCloud = [{ phenotype: pheno, pattern }, ...archive.pointCloud];
  const existing = archive.archive[binKey];
  const newArchiveMap = { ...archive.archive };
  let newDefault = archive.defaultId;
  if (!existing || score > existing.score) {
    newArchiveMap[binKey] = { score, pattern };
    newDefault = pattern.id;
  }
  return { ...archive, archive: newArchiveMap, pointCloud: newCloud, defaultId: newDefault };
}

export function getPatternById(archive: DecompositionArchive, patternId: string): DecompositionPattern | null {
  for (const v of Object.values(archive.archive)) {
    if (v.pattern.id === patternId) return v.pattern;
  }
  for (const entry of archive.pointCloud) {
    if (entry.pattern.id === patternId) return entry.pattern;
  }
  return null;
}

export function pruneArchive(archive: DecompositionArchive, maxCloudSize = 1000): DecompositionArchive {
  if (archive.pointCloud.length <= maxCloudSize) return archive;
  const binPatternIds = new Set(Object.values(archive.archive).map((v) => v.pattern.id));
  const keepFromBins = archive.pointCloud.filter((e) => binPatternIds.has(e.pattern.id));
  const others = archive.pointCloud.filter((e) => !binPatternIds.has(e.pattern.id));
  const remaining = maxCloudSize - keepFromBins.length;
  const sampled = others.slice(0, remaining);
  return { ...archive, pointCloud: [...keepFromBins, ...sampled] };
}

export function archiveStats(archive: DecompositionArchive): {
  totalPatterns: number;
  binsFilled: number;
  avgScore: number;
  bestPatternId: string | null;
} {
  const bins = Object.values(archive.archive);
  const scores = bins.map((b) => b.score);
  const avgScore = scores.length === 0 ? 0 : scores.reduce((a, b) => a + b, 0) / scores.length;
  const best = bins.length > 0 ? bins.reduce((a, b) => (a.score > b.score ? a : b)) : null;
  return {
    totalPatterns: archive.pointCloud.length,
    binsFilled: bins.length,
    avgScore,
    bestPatternId: best?.pattern.id ?? null
  };
}
