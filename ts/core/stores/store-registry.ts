import { readFile, writeFile, rename, readdir, unlink, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";

import { ensureChrysalisDirs, storeRegistryPath, dynamicStoresDir } from "../paths.js";
import { type StoreSpec, type StoreKind, type StoreRegistryDB } from "../types.js";

const VALID_KINDS: StoreKind[] = ["kv", "log", "set", "counter"];

function storeKey(namespace: string, name: string): string {
  return `${namespace}:${name}`;
}

function defaultDB(): StoreRegistryDB {
  return { stores: {} };
}

async function readJsonFile<T>(path: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch {
    return fallback;
  }
}

async function writeJsonFileAtomic(path: string, value: unknown): Promise<void> {
  const tmp = `${path}.tmp`;
  await writeFile(tmp, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  await rename(tmp, path);
}

async function loadRegistry(cwd: string): Promise<StoreRegistryDB> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile<StoreRegistryDB>(storeRegistryPath(cwd), defaultDB());
}

async function saveRegistry(cwd: string, db: StoreRegistryDB): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFileAtomic(storeRegistryPath(cwd), db);
}

function storeDataPath(cwd: string, key: string): string {
  return join(dynamicStoresDir(cwd), `${key}.json`);
}

export async function storeCreate(
  cwd: string,
  name: string,
  kind: StoreKind,
  opts?: { namespace?: string; description?: string }
): Promise<StoreSpec> {
  if (!VALID_KINDS.includes(kind)) throw new Error(`Invalid store kind: ${kind}. Valid: ${VALID_KINDS.join(", ")}`);
  const namespace = opts?.namespace ?? "default";
  const key = storeKey(namespace, name);
  const db = await loadRegistry(cwd);
  if (db.stores[key]) throw new Error(`Store "${key}" already exists`);
  const now = Math.floor(Date.now() / 1000);
  const spec: StoreSpec = { name, namespace, kind, description: opts?.description ?? "", createdAt: now, updatedAt: now };
  db.stores[key] = spec;
  await saveRegistry(cwd, db);
  const dataPath = storeDataPath(cwd, key);
  if (!existsSync(dataPath)) {
    const initial = kind === "kv" ? {} : kind === "log" ? [] : kind === "set" ? [] : { value: 0 };
    await mkdir(join(dataPath, ".."), { recursive: true });
    await writeJsonFileAtomic(dataPath, initial);
  }
  return spec;
}

export async function storeDelete(cwd: string, name: string, namespace?: string): Promise<string> {
  const key = storeKey(namespace ?? "default", name);
  const db = await loadRegistry(cwd);
  if (!db.stores[key]) throw new Error(`Store "${key}" not found`);
  delete db.stores[key];
  await saveRegistry(cwd, db);
  const dataPath = storeDataPath(cwd, key);
  try { await unlink(dataPath); } catch {}
  return `Deleted store ${key}`;
}

export async function storeList(cwd: string, opts?: { namespace?: string; kind?: StoreKind }): Promise<StoreSpec[]> {
  const db = await loadRegistry(cwd);
  let specs = Object.values(db.stores);
  if (opts?.namespace) specs = specs.filter((s) => s.namespace === opts.namespace);
  if (opts?.kind) specs = specs.filter((s) => s.kind === opts.kind);
  return specs.sort((a, b) => b.updatedAt - a.updatedAt);
}

export async function storeGetSpec(cwd: string, name: string, namespace?: string): Promise<StoreSpec | null> {
  const db = await loadRegistry(cwd);
  return db.stores[storeKey(namespace ?? "default", name)] ?? null;
}

export async function storeDescribe(cwd: string): Promise<string> {
  const specs = await storeList(cwd);
  if (specs.length === 0) return "No dynamic stores.";
  const lines = specs.map((s) => `${s.namespace}/${s.name} (${s.kind}) — ${s.description || "no description"}`);
  return `Dynamic stores:\n${lines.join("\n")}`;
}

async function loadStoreData(cwd: string, key: string): Promise<unknown> {
  const path = storeDataPath(cwd, key);
  return readJsonFile(path, null);
}

async function saveStoreData(cwd: string, key: string, data: unknown): Promise<void> {
  const path = storeDataPath(cwd, key);
  await mkdir(join(path, ".."), { recursive: true });
  await writeJsonFileAtomic(path, data);
}

export async function storeGet(cwd: string, name: string, field: string, namespace?: string): Promise<string> {
  const key = storeKey(namespace ?? "default", name);
  const spec = await storeGetSpec(cwd, name, namespace);
  if (!spec) throw new Error(`Store "${key}" not found`);
  const data = await loadStoreData(cwd, key);
  if (data === null) throw new Error(`Store data for "${key}" missing`);
  switch (spec.kind) {
    case "kv": {
      const map = data as Record<string, unknown>;
      if (!(field in map)) return "null";
      return JSON.stringify(map[field]);
    }
    case "log": {
      const entries = data as unknown[];
      const idx = parseInt(field, 10);
      if (isNaN(idx) || idx < 0 || idx >= entries.length) return "null";
      return JSON.stringify(entries[idx]);
    }
    case "set": {
      const items = data as unknown[];
      const idx = parseInt(field, 10);
      if (isNaN(idx) || idx < 0 || idx >= items.length) return "null";
      return JSON.stringify(items[idx]);
    }
    case "counter": {
      return JSON.stringify(data);
    }
  }
}

export async function storeSet(cwd: string, name: string, field: string, value: string, namespace?: string): Promise<string> {
  const key = storeKey(namespace ?? "default", name);
  const spec = await storeGetSpec(cwd, name, namespace);
  if (!spec) throw new Error(`Store "${key}" not found`);
  const data = await loadStoreData(cwd, key);
  if (data === null) throw new Error(`Store data for "${key}" missing`);
  let parsed: unknown;
  try { parsed = JSON.parse(value); } catch { parsed = value; }

  switch (spec.kind) {
    case "kv": {
      const map = data as Record<string, unknown>;
      map[field] = parsed;
      await saveStoreData(cwd, key, map);
      return `Set ${field} in ${key}`;
    }
    case "log": {
      const entries = data as unknown[];
      entries.push({ ts: Date.now(), [field]: parsed });
      await saveStoreData(cwd, key, entries);
      return `Appended to log ${key}`;
    }
    case "set": {
      const items = data as unknown[];
      if (!items.some((i) => JSON.stringify(i) === JSON.stringify(parsed))) {
        items.push(parsed);
        await saveStoreData(cwd, key, items);
      }
      return `Added to set ${key}`;
    }
    case "counter": {
      const counter = data as { value: number };
      counter.value += (typeof parsed === "number" ? parsed : parseInt(String(parsed), 10) || 1);
      await saveStoreData(cwd, key, counter);
      return `Counter ${key} = ${counter.value}`;
    }
  }
}

export async function storeRemove(cwd: string, name: string, field: string, namespace?: string): Promise<string> {
  const key = storeKey(namespace ?? "default", name);
  const spec = await storeGetSpec(cwd, name, namespace);
  if (!spec) throw new Error(`Store "${key}" not found`);
  const data = await loadStoreData(cwd, key);
  if (data === null) throw new Error(`Store data for "${key}" missing`);

  switch (spec.kind) {
    case "kv": {
      const map = data as Record<string, unknown>;
      if (!(field in map)) return `Field "${field}" not found in ${key}`;
      delete map[field];
      await saveStoreData(cwd, key, map);
      return `Removed ${field} from ${key}`;
    }
    case "set": {
      const items = data as unknown[];
      let parsed: unknown;
      try { parsed = JSON.parse(field); } catch { parsed = field; }
      const before = items.length;
      const filtered = items.filter((i) => JSON.stringify(i) !== JSON.stringify(parsed));
      await saveStoreData(cwd, key, filtered);
      return `Removed ${before - filtered.length} item(s) from set ${key}`;
    }
    case "log": {
      const entries = data as unknown[];
      const idx = parseInt(field, 10);
      if (isNaN(idx) || idx < 0 || idx >= entries.length) return `Index ${field} out of range in ${key}`;
      entries.splice(idx, 1);
      await saveStoreData(cwd, key, entries);
      return `Removed entry ${field} from log ${key}`;
    }
    case "counter": {
      return `Cannot remove from counter ${key} — use store-set to adjust`;
    }
  }
}

export async function storeDump(cwd: string, name: string, namespace?: string): Promise<string> {
  const key = storeKey(namespace ?? "default", name);
  const spec = await storeGetSpec(cwd, name, namespace);
  if (!spec) throw new Error(`Store "${key}" not found`);
  const data = await loadStoreData(cwd, key);
  return JSON.stringify({ spec, data }, null, 2);
}
