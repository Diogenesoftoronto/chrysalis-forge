import { readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";

import { ensureChrysalisDirs, vectorStorePath } from "../paths.js";
import { type VectorEntry } from "../types.js";

function cosineSimilarity(a: number[], b: number[]): number {
  let dot = 0, magA = 0, magB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    magA += a[i] * a[i];
    magB += b[i] * b[i];
  }
  const denom = Math.sqrt(magA) * Math.sqrt(magB);
  return denom === 0 ? 0 : dot / denom;
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

async function loadDB(cwd: string): Promise<Record<string, VectorEntry>> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile(vectorStorePath(cwd), {});
}

async function saveDB(cwd: string, db: Record<string, VectorEntry>): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFile(vectorStorePath(cwd), db);
}

export async function vectorAdd(cwd: string, text: string, vec: number[]): Promise<string> {
  const db = await loadDB(cwd);
  const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  db[id] = { text, vec };
  await saveDB(cwd, db);
  return id;
}

export async function vectorSearch(cwd: string, queryVec: number[], topK = 3): Promise<Array<{ score: number; text: string }>> {
  const db = await loadDB(cwd);
  const scored: Array<{ score: number; text: string }> = [];
  for (const entry of Object.values(db)) {
    scored.push({ score: cosineSimilarity(queryVec, entry.vec), text: entry.text });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, topK);
}

export { cosineSimilarity };
