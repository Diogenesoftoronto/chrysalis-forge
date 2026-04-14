import { readFile, writeFile, rename } from "node:fs/promises";
import { existsSync } from "node:fs";
import { randomBytes } from "node:crypto";

import { ensureChrysalisDirs, contextStorePath } from "../paths.js";
import { type SessionContext, type SessionDB, type SessionMetadata, type ChrysalisProfile } from "../types.js";

const DEFAULT_SYSTEM_PROMPT = "You are Chrysalis, a terminal-first coding agent.";

function defaultContext(): SessionContext {
  return {
    system: DEFAULT_SYSTEM_PROMPT,
    memory: "",
    toolHints: "",
    mode: "code",
    priority: "best",
    history: [],
    compactedSummary: ""
  };
}

function defaultDB(): SessionDB {
  return {
    active: "default",
    items: { default: defaultContext() },
    metadata: {}
  };
}

function generateSessionId(): string {
  const hex = (n: number) => randomBytes(n).toString("hex");
  return `${hex(4)}-${hex(2)}-${hex(2)}-${hex(2)}-${hex(6)}`;
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

async function loadDB(cwd: string): Promise<SessionDB> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile<SessionDB>(contextStorePath(cwd), defaultDB());
}

async function saveDB(cwd: string, db: SessionDB): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFileAtomic(contextStorePath(cwd), db);
}

export async function sessionCreate(
  cwd: string,
  name: string,
  opts?: { mode?: "ask" | "code"; id?: string; title?: string }
): Promise<SessionDB> {
  const db = await loadDB(cwd);
  if (db.items[name]) throw new Error(`Session "${name}" already exists`);
  const sessionId = opts?.id ?? generateSessionId();
  const now = Math.floor(Date.now() / 1000);
  db.items[name] = { ...defaultContext(), mode: opts?.mode ?? "code" };
  db.metadata[name] = { id: sessionId, title: opts?.title ?? null, createdAt: now, updatedAt: now };
  await saveDB(cwd, db);
  return db;
}

export async function sessionSwitch(cwd: string, name: string): Promise<SessionDB> {
  const db = await loadDB(cwd);
  if (!db.items[name]) throw new Error(`Session "${name}" not found`);
  db.active = name;
  db.metadata[name] = { ...db.metadata[name] ?? { id: name, createdAt: 0 }, updatedAt: Math.floor(Date.now() / 1000) };
  await saveDB(cwd, db);
  return db;
}

export async function sessionList(cwd: string): Promise<{ names: string[]; active: string }> {
  const db = await loadDB(cwd);
  return { names: Object.keys(db.items), active: db.active };
}

export async function sessionListWithMetadata(cwd: string): Promise<Array<SessionMetadata & { name: string; isActive: boolean }>> {
  const db = await loadDB(cwd);
  return Object.keys(db.items).map((name) => {
    const meta = db.metadata[name] ?? { id: name, createdAt: 0, updatedAt: 0 };
    return { name, ...meta, isActive: name === db.active };
  });
}

export async function sessionDelete(cwd: string, name: string): Promise<SessionDB> {
  const db = await loadDB(cwd);
  if (name === db.active) throw new Error("Cannot delete active session");
  if (!db.items[name]) throw new Error(`Session "${name}" not found`);
  delete db.items[name];
  delete db.metadata[name];
  await saveDB(cwd, db);
  return db;
}

export async function sessionGetActive(cwd: string): Promise<SessionContext> {
  const db = await loadDB(cwd);
  return db.items[db.active] ?? defaultContext();
}

export async function sessionGetMetadata(cwd: string, name: string): Promise<SessionMetadata | null> {
  const db = await loadDB(cwd);
  return db.metadata[name] ?? null;
}

export async function sessionGetLast(cwd: string): Promise<string | null> {
  const sessions = await sessionListWithMetadata(cwd);
  if (sessions.length === 0) return null;
  const sorted = [...sessions].sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0));
  return sorted[0].id;
}

export async function sessionResumeById(cwd: string, sessionId: string): Promise<string | null> {
  const sessions = await sessionListWithMetadata(cwd);
  const found = sessions.find((s) => s.id === sessionId);
  if (!found) return null;
  await sessionSwitch(cwd, found.name);
  return found.name;
}

export async function sessionUpdateTitle(cwd: string, name: string, title: string): Promise<void> {
  const db = await loadDB(cwd);
  if (!db.metadata[name]) db.metadata[name] = { id: name, createdAt: 0, updatedAt: 0 };
  db.metadata[name].title = title;
  db.metadata[name].updatedAt = Math.floor(Date.now() / 1000);
  await saveDB(cwd, db);
}
