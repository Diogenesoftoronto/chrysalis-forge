import { readFile, writeFile, rename } from "node:fs/promises";
import { randomBytes } from "node:crypto";

import { ensureChrysalisDirs, threadStorePath } from "../paths.js";
import {
  type ThreadData,
  type ThreadRelation,
  type ContextNode,
  type ThreadsDB
} from "../types.js";

function defaultDB(): ThreadsDB {
  return { threads: {}, relations: [], contexts: {}, activeThread: null };
}

function generateThreadId(): string {
  const hex = (n: number) => randomBytes(n).toString("hex");
  return `T-${hex(4)}-${hex(2)}-${hex(2)}-${hex(2)}-${hex(6)}`;
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

async function loadDB(cwd: string): Promise<ThreadsDB> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile<ThreadsDB>(threadStorePath(cwd), defaultDB());
}

async function saveDB(cwd: string, db: ThreadsDB): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFileAtomic(threadStorePath(cwd), db);
}

export async function threadCreate(cwd: string, title: string, project?: string): Promise<string> {
  const db = await loadDB(cwd);
  const id = generateThreadId();
  const now = Math.floor(Date.now() / 1000);
  db.threads[id] = { id, title, project: project ?? null, status: "active", summary: null, sessionName: null, createdAt: now, updatedAt: now };
  await saveDB(cwd, db);
  return id;
}

export async function threadFind(cwd: string, id: string): Promise<ThreadData | null> {
  const db = await loadDB(cwd);
  return db.threads[id] ?? null;
}

export async function threadList(cwd: string, opts?: { project?: string; status?: string; limit?: number }): Promise<ThreadData[]> {
  const db = await loadDB(cwd);
  let all = Object.values(db.threads);
  if (opts?.project) all = all.filter((t) => t.project === opts.project);
  if (opts?.status) all = all.filter((t) => t.status === opts.status);
  const sorted = [...all].sort((a, b) => b.updatedAt - a.updatedAt);
  return sorted.slice(0, opts?.limit ?? 50);
}

export async function threadUpdate(cwd: string, id: string, updates: Partial<Pick<ThreadData, "title" | "status" | "summary">>): Promise<void> {
  const db = await loadDB(cwd);
  const thread = db.threads[id];
  if (!thread) return;
  if (updates.title !== undefined) thread.title = updates.title;
  if (updates.status !== undefined) thread.status = updates.status;
  if (updates.summary !== undefined) thread.summary = updates.summary;
  thread.updatedAt = Math.floor(Date.now() / 1000);
  await saveDB(cwd, db);
}

export async function threadGetActive(cwd: string): Promise<string | null> {
  const db = await loadDB(cwd);
  return db.activeThread;
}

export async function threadSetActive(cwd: string, id: string): Promise<void> {
  const db = await loadDB(cwd);
  db.activeThread = id;
  await saveDB(cwd, db);
}

export async function threadSwitch(cwd: string, id: string): Promise<void> {
  await threadSetActive(cwd, id);
}

export async function threadGetSession(cwd: string, threadId: string): Promise<string | null> {
  const thread = await threadFind(cwd, threadId);
  return thread?.sessionName ?? null;
}

export async function threadLinkSession(cwd: string, threadId: string, sessionName: string): Promise<void> {
  const db = await loadDB(cwd);
  const thread = db.threads[threadId];
  if (!thread) return;
  thread.sessionName = sessionName;
  thread.updatedAt = Math.floor(Date.now() / 1000);
  await saveDB(cwd, db);
}

export async function threadRelationCreate(cwd: string, fromId: string, toId: string, relationType: string): Promise<void> {
  const db = await loadDB(cwd);
  db.relations.push({ from: fromId, to: toId, type: relationType, createdAt: Math.floor(Date.now() / 1000) });
  await saveDB(cwd, db);
}

export async function threadGetRelations(cwd: string, threadId: string): Promise<ThreadRelation[]> {
  const db = await loadDB(cwd);
  return db.relations.filter((r) => r.from === threadId || r.to === threadId);
}

export async function threadContinue(cwd: string, fromId: string, title?: string): Promise<string> {
  const from = await threadFind(cwd, fromId);
  const newTitle = title ?? (from ? `Continues: ${from.title}` : "Untitled");
  const newId = await threadCreate(cwd, newTitle, from?.project ?? undefined);
  await threadRelationCreate(cwd, newId, fromId, "continues_from");
  if (from?.summary) await threadUpdate(cwd, newId, { summary: from.summary });
  return newId;
}

export async function threadSpawnChild(cwd: string, parentId: string, title: string): Promise<string> {
  const parent = await threadFind(cwd, parentId);
  const newId = await threadCreate(cwd, title, parent?.project ?? undefined);
  await threadRelationCreate(cwd, newId, parentId, "child_of");
  return newId;
}

export async function contextCreate(cwd: string, threadId: string, title: string, opts?: { parentId?: string; kind?: string; body?: string }): Promise<string> {
  const db = await loadDB(cwd);
  const id = `ctx-${Math.floor(Math.random() * 1e9)}`;
  const now = Math.floor(Date.now() / 1000);
  db.contexts[id] = { id, threadId, parentId: opts?.parentId ?? null, title, kind: opts?.kind ?? "note", body: opts?.body ?? null, createdAt: now, children: [] };
  await saveDB(cwd, db);
  return id;
}

export async function contextList(cwd: string, threadId: string): Promise<ContextNode[]> {
  const db = await loadDB(cwd);
  return Object.values(db.contexts).filter((c) => c.threadId === threadId);
}

export async function contextTree(cwd: string, threadId: string): Promise<ContextNode[]> {
  const nodes = await contextList(cwd, threadId);
  const childrenMap = new Map<string | null, ContextNode[]>();
  for (const node of nodes) {
    const key = node.parentId ?? null;
    const list = childrenMap.get(key) ?? [];
    list.push(node);
    childrenMap.set(key, list);
  }
  function buildSubtree(node: ContextNode): ContextNode {
    const children = (childrenMap.get(node.id) ?? []).map(buildSubtree);
    return { ...node, children };
  }
  return (childrenMap.get(null) ?? []).map(buildSubtree);
}
