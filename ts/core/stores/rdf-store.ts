import { readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";

import { ensureChrysalisDirs, rdfDbPath } from "../paths.js";

export interface Triple {
  subject: string;
  predicate: string;
  object: string;
  graph: string;
  timestamp: number;
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

async function loadTriples(cwd: string): Promise<Triple[]> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile<Triple[]>(rdfDbPath(cwd), []);
}

async function saveTriples(cwd: string, triples: Triple[]): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFile(rdfDbPath(cwd), triples);
}

export async function rdfLoad(cwd: string, path: string, graphId: string): Promise<string> {
  if (!existsSync(path)) return "File not found.";
  const content = await readFile(path, "utf8");
  const lines = content.split(/\r?\n/).filter(Boolean);
  const now = Math.floor(Date.now() / 1000);
  let existing = await loadTriples(cwd);
  existing = existing.filter((t) => t.graph !== graphId);
  const newTriples: Triple[] = [];
  for (const line of lines) {
    const parts = line.trim().split(/\s+/);
    if (parts.length >= 3) {
      newTriples.push({ subject: parts[0], predicate: parts[1], object: parts.slice(2).join(" "), graph: graphId, timestamp: now });
    }
  }
  await saveTriples(cwd, [...existing, ...newTriples]);
  return `Loaded ${newTriples.length} lines into graph ${graphId}.`;
}

function matchPattern(triple: Triple, pattern: { subject?: string; predicate?: string; object?: string; graph?: string }): boolean {
  if (pattern.subject !== undefined && pattern.subject !== "?" && triple.subject !== pattern.subject) return false;
  if (pattern.predicate !== undefined && pattern.predicate !== "?" && triple.predicate !== pattern.predicate) return false;
  if (pattern.object !== undefined && pattern.object !== "?" && triple.object !== pattern.object) return false;
  if (pattern.graph !== undefined && pattern.graph !== "?" && triple.graph !== pattern.graph) return false;
  return true;
}

export async function rdfQuery(cwd: string, query: string, graphId?: string): Promise<string> {
  const triples = await loadTriples(cwd);
  const upperQuery = query.trim().toUpperCase();

  if (upperQuery.startsWith("SELECT")) {
    return JSON.stringify({ error: "SQL SELECT not supported in JSON-backed store. Use pattern matching syntax: '?s predicate object'" });
  }

  const parts = query.trim().split(/\s+/);
  const pattern: Record<string, string> = {};
  const fieldOrder = ["subject", "predicate", "object", "graph"];

  for (let i = 0; i < parts.length && i < fieldOrder.length; i++) {
    pattern[fieldOrder[i]] = parts[i];
  }

  if (graphId && !("graph" in pattern)) {
    pattern.graph = graphId;
  }

  const results = triples.filter((t) =>
    matchPattern(t, {
      subject: pattern.subject,
      predicate: pattern.predicate,
      object: pattern.object,
      graph: pattern.graph
    })
  ).slice(0, 200);

  return JSON.stringify(results.map((t) => ({
    subject: t.subject,
    predicate: t.predicate,
    object: t.object,
    graph: t.graph,
    timestamp: t.timestamp
  })), null, 2);
}

export async function rdfInsert(
  cwd: string,
  subject: string,
  predicate: string,
  object: string,
  graph = "default",
  timestamp?: number
): Promise<string> {
  const triples = await loadTriples(cwd);
  triples.push({ subject, predicate, object, graph, timestamp: timestamp ?? Math.floor(Date.now() / 1000) });
  await saveTriples(cwd, triples);
  return `Inserted triple: ${subject} ${predicate} ${object} (graph: ${graph})`;
}
