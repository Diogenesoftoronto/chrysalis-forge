import { readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";

import { ensureChrysalisDirs, cacheStorePath } from "../paths.js";
import { type CacheEntry, type CacheStats } from "../types.js";

const DEFAULT_TTL = 86400;
const MAX_TTL = 604800;

function expired(entry: CacheEntry): boolean {
  return Date.now() / 1000 > entry.createdAt + entry.ttl;
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

async function loadCache(cwd: string): Promise<Record<string, CacheEntry>> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile(cacheStorePath(cwd), {});
}

async function saveCache(cwd: string, cache: Record<string, CacheEntry>): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFile(cacheStorePath(cwd), cache);
}

export async function cacheGet(cwd: string, key: string, ignoreTtl = false): Promise<string | null> {
  const cache = await loadCache(cwd);
  const entry = cache[key];
  if (!entry) return null;
  if (!ignoreTtl && expired(entry)) {
    delete cache[key];
    await saveCache(cwd, cache);
    return null;
  }
  return entry.value;
}

export async function cacheSet(cwd: string, key: string, value: string, ttl = DEFAULT_TTL, tags: string[] = []): Promise<string> {
  const cache = await loadCache(cwd);
  cache[key] = { value, createdAt: Math.floor(Date.now() / 1000), ttl: Math.min(ttl, MAX_TTL), tags };
  await saveCache(cwd, cache);
  return "Cached.";
}

export async function cacheInvalidate(cwd: string, key: string): Promise<string> {
  const cache = await loadCache(cwd);
  if (!(key in cache)) return "Key not found.";
  delete cache[key];
  await saveCache(cwd, cache);
  return "Invalidated.";
}

export async function cacheInvalidateByTag(cwd: string, tag: string): Promise<string> {
  const cache = await loadCache(cwd);
  let removed = 0;
  for (const [k, v] of Object.entries(cache)) {
    if (v.tags.includes(tag)) {
      delete cache[k];
      removed++;
    }
  }
  await saveCache(cwd, cache);
  return `Invalidated ${removed} entries.`;
}

export async function cacheCleanup(cwd: string): Promise<string> {
  const cache = await loadCache(cwd);
  let removed = 0;
  for (const [k, v] of Object.entries(cache)) {
    if (expired(v)) {
      delete cache[k];
      removed++;
    }
  }
  await saveCache(cwd, cache);
  return `Cleaned up ${removed} expired entries.`;
}

export async function cacheClear(cwd: string): Promise<string> {
  await saveCache(cwd, {});
  return "Cache cleared.";
}

export async function cacheStats(cwd: string): Promise<CacheStats> {
  const cache = await loadCache(cwd);
  const entries = Object.values(cache);
  const expiredCount = entries.filter(expired).length;
  const tagCounts: Record<string, number> = {};
  for (const entry of entries) {
    for (const tag of entry.tags) {
      tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
    }
  }
  return { total: entries.length, valid: entries.length - expiredCount, expired: expiredCount, tags: tagCounts };
}
