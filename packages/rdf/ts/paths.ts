import { mkdir } from "node:fs/promises";
import { join, resolve } from "node:path";

export function rdfDir(cwd: string, rootName = ".chrysalis"): string {
  return join(resolve(cwd, rootName), "state", "rdf");
}

export function rdfDbPath(cwd: string, rootName = ".chrysalis"): string {
  return join(rdfDir(cwd, rootName), "graph.db");
}

export function vectorStorePath(cwd: string, rootName = ".chrysalis"): string {
  return join(resolve(cwd, rootName), "state", "vectors.json");
}

export async function ensureRdfDir(cwd: string, rootName = ".chrysalis"): Promise<void> {
  await mkdir(rdfDir(cwd, rootName), { recursive: true });
}
