import {
  type DecompPhenotype,
  type DecompositionPattern,
  type DecompositionArchive,
  type ChrysalisProfile
} from "./types.js";
import { phenotypeDistance, normalizePhenotype } from "./evolution.js";
import { loadArchive, saveArchive } from "./stores/decomp-archive.js";

const PRIORITY_PHENOTYPE: Record<ChrysalisProfile, DecompPhenotype> = {
  fast: { depth: 1, parallelism: 3, toolDiversity: 1, complexity: 2 },
  cheap: { depth: 2, parallelism: 1, toolDiversity: 2, complexity: 3 },
  best: { depth: 3, parallelism: 2, toolDiversity: 4, complexity: 5 },
  verbose: { depth: 4, parallelism: 2, toolDiversity: 5, complexity: 7 }
};

export function priorityToPhenotype(priority: ChrysalisProfile): DecompPhenotype {
  return PRIORITY_PHENOTYPE[priority];
}

export function computeDecompPhenotype(pattern: DecompositionPattern): DecompPhenotype {
  const steps = pattern.steps;
  const n = steps.length;
  const depth = n === 0 ? 0 : 1 + Math.max(...steps.map((s) => s.dependencies.length));
  const allDeps = steps.flatMap((s) => s.dependencies);
  const uniqueDeps = new Set(allDeps);
  const parallelism = Math.max(0, n - uniqueDeps.size);
  const allTools = steps.flatMap((s) => s.toolHints);
  const toolDiversity = new Set(allTools).size;
  return { depth, parallelism, toolDiversity, complexity: n };
}

export function selectPatternForPhenotype(
  archive: DecompositionArchive,
  target: DecompPhenotype
): DecompositionPattern | null {
  const entries = Object.values(archive.archive);
  if (entries.length === 0) return null;

  const phenos = entries.map((e) => computeDecompPhenotype(e.pattern));
  const allDepth = phenos.map((p) => p.depth);
  const allParallel = phenos.map((p) => p.parallelism);
  const allTool = phenos.map((p) => p.toolDiversity);
  const allComplex = phenos.map((p) => p.complexity);

  const mins = [Math.min(...allDepth), Math.min(...allParallel), Math.min(...allTool), Math.min(...allComplex)];
  const maxs = [Math.max(...allDepth), Math.max(...allParallel), Math.max(...allTool), Math.max(...allComplex)];

  const targetArr = [target.depth, target.parallelism, target.toolDiversity, target.complexity];
  const targetNorm = normalizePhenotype(
    { accuracy: target.depth, latency: target.parallelism, cost: target.toolDiversity, usage: target.complexity },
    mins, maxs
  );

  let bestDist = Infinity;
  let bestPattern: DecompositionPattern | null = null;

  for (const entry of entries) {
    const pheno = computeDecompPhenotype(entry.pattern);
    const norm = normalizePhenotype(
      { accuracy: pheno.depth, latency: pheno.parallelism, cost: pheno.toolDiversity, usage: pheno.complexity },
      mins, maxs
    );
    const dist = phenotypeDistance(targetNorm, norm);
    if (dist < bestDist) {
      bestDist = dist;
      bestPattern = entry.pattern;
    }
  }

  return bestPattern;
}

export function selectPatternForPriority(
  archive: DecompositionArchive,
  priority: ChrysalisProfile
): DecompositionPattern | null {
  const target = priorityToPhenotype(priority);
  return selectPatternForPhenotype(archive, target);
}

export function binKeyForDecomp(pheno: DecompPhenotype): string {
  const depthBin = pheno.depth < 2 ? "shallow" : "deep";
  const parallelBin = pheno.parallelism < 2 ? "serial" : "parallel";
  const toolBin = pheno.toolDiversity < 2 ? "mono" : "diverse";
  return `${depthBin}:${parallelBin}:${toolBin}`;
}

export async function selectOrDecompose(
  cwd: string,
  taskType: string,
  priority: ChrysalisProfile
): Promise<{ pattern: DecompositionPattern | null; source: "archive" | "fallback" }> {
  const archive = await loadArchive(cwd, taskType);
  const pattern = selectPatternForPriority(archive, priority);
  if (pattern) return { pattern, source: "archive" };
  return { pattern: null, source: "fallback" };
}
