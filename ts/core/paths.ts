import { mkdir } from "node:fs/promises";
import { join, resolve } from "node:path";

export function artifactRoot(cwd: string, rootName = ".chrysalis"): string {
  return resolve(cwd, rootName);
}

export function outputsDir(cwd: string, rootName = ".chrysalis"): string {
  return join(artifactRoot(cwd, rootName), "outputs");
}

export function plansDir(cwd: string, rootName = ".chrysalis"): string {
  return join(outputsDir(cwd, rootName), "plans");
}

export function sessionsDir(cwd: string, rootName = ".chrysalis"): string {
  return join(artifactRoot(cwd, rootName), "sessions");
}

export function stateDir(cwd: string, rootName = ".chrysalis"): string {
  return join(artifactRoot(cwd, rootName), "state");
}

export function evolutionDir(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "evolution");
}

export function profilePath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "profile.json");
}

export function evolutionStatePath(cwd: string, rootName = ".chrysalis"): string {
  return join(evolutionDir(cwd, rootName), "state.json");
}

export function evolutionArchivePath(cwd: string, rootName = ".chrysalis"): string {
  return join(evolutionDir(cwd, rootName), "archive.json");
}

export function evolutionProfileStatsPath(cwd: string, rootName = ".chrysalis"): string {
  return join(evolutionDir(cwd, rootName), "profile-stats.json");
}

export function evolutionEvalPath(cwd: string, rootName = ".chrysalis"): string {
  return join(evolutionDir(cwd, rootName), "evals.jsonl");
}

export function evolutionSystemPromptPath(cwd: string, rootName = ".chrysalis"): string {
  return join(evolutionDir(cwd, rootName), "system-prompt.md");
}

export function evolutionMetaPromptPath(cwd: string, rootName = ".chrysalis"): string {
  return join(evolutionDir(cwd, rootName), "meta-prompt.md");
}

export function rdfDir(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "rdf");
}

export function rdfDbPath(cwd: string, rootName = ".chrysalis"): string {
  return join(rdfDir(cwd, rootName), "graph.db");
}

export function threadStorePath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "threads.json");
}

export function contextStorePath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "context.json");
}

export function rollbackDir(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "rollbacks");
}

export function traceStorePath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "traces.jsonl");
}

export function cacheStorePath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "web-cache.json");
}

export function evalStorePath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "evals.jsonl");
}

export function evalProfileStatsPath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "profile-stats.json");
}

export function decompArchiveDir(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "decomp-archives");
}

export function vectorStorePath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "vectors.json");
}

export function sessionStatsPath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "session-stats.json");
}

export function storeRegistryPath(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "store-registry.json");
}

export function dynamicStoresDir(cwd: string, rootName = ".chrysalis"): string {
  return join(stateDir(cwd, rootName), "stores");
}

export async function ensureChrysalisDirs(cwd: string, rootName = ".chrysalis"): Promise<void> {
  for (const dir of [
    artifactRoot(cwd, rootName),
    outputsDir(cwd, rootName),
    plansDir(cwd, rootName),
    sessionsDir(cwd, rootName),
    stateDir(cwd, rootName),
    evolutionDir(cwd, rootName),
    rdfDir(cwd, rootName),
    rollbackDir(cwd, rootName),
    decompArchiveDir(cwd, rootName),
    dynamicStoresDir(cwd, rootName)
  ]) {
    await mkdir(dir, { recursive: true });
  }
}
