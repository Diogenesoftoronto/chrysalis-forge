import { readFile, writeFile, copyFile, unlink, readdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join } from "node:path";

import { ensureChrysalisDirs, rollbackDir } from "../paths.js";
import { type RollbackEntry } from "../types.js";

const DEFAULT_MAX_ROLLBACKS = 10;

function backupFilename(path: string, timestamp: number): string {
  const name = path.replace(/^.*[\\/]/, "");
  const hashSuffix = path.split("").reduce((h, c) => ((h << 5) - h + c.charCodeAt(0)) | 0, 0).toString(16).slice(0, 8);
  return `${name}.${timestamp}.${hashSuffix}.bak`;
}

export async function fileBackup(cwd: string, path: string, maxRollbacks = DEFAULT_MAX_ROLLBACKS): Promise<string | null> {
  if (!existsSync(path)) return null;
  await ensureChrysalisDirs(cwd);
  const dir = rollbackDir(cwd);
  const ts = Date.now();
  const backupName = backupFilename(path, ts);
  const backupPath = join(dir, backupName);
  await copyFile(path, backupPath);

  const indexPath = join(dir, "index.json");
  let index: Record<string, RollbackEntry[]> = {};
  try {
    index = JSON.parse(await readFile(indexPath, "utf8"));
  } catch {}

  const existing = index[path] ?? [];
  const updated = [{ timestamp: ts, backupPath }, ...existing].slice(0, maxRollbacks);
  index[path] = updated;

  for (const old of existing.slice(maxRollbacks - 1)) {
    try { await unlink(old.backupPath); } catch {}
  }

  await writeFile(indexPath, `${JSON.stringify(index, null, 2)}\n`, "utf8");
  return backupPath;
}

export async function fileRollback(cwd: string, path: string, steps = 1): Promise<{ ok: boolean; message: string }> {
  await ensureChrysalisDirs(cwd);
  const dir = rollbackDir(cwd);
  const indexPath = join(dir, "index.json");
  let index: Record<string, RollbackEntry[]> = {};
  try {
    index = JSON.parse(await readFile(indexPath, "utf8"));
  } catch {}

  const history = index[path] ?? [];
  if (history.length === 0) return { ok: false, message: "No rollback history for this file" };
  if (steps > history.length) return { ok: false, message: `Only ${history.length} rollback(s) available` };

  const entry = history[steps - 1];
  if (!existsSync(entry.backupPath)) return { ok: false, message: "Backup file missing" };

  await fileBackup(cwd, path);
  await copyFile(entry.backupPath, path);
  return { ok: true, message: `Restored to version from ${new Date(entry.timestamp * 1000).toISOString()}` };
}

export async function fileRollbackList(cwd: string, path: string): Promise<Array<{ step: number; timestamp: number; backupPath: string; size: number }>> {
  await ensureChrysalisDirs(cwd);
  const dir = rollbackDir(cwd);
  const indexPath = join(dir, "index.json");
  let index: Record<string, RollbackEntry[]> = {};
  try {
    index = JSON.parse(await readFile(indexPath, "utf8"));
  } catch {}

  const history = index[path] ?? [];
  return history.map((entry, i) => ({
    step: i + 1,
    timestamp: entry.timestamp,
    backupPath: entry.backupPath,
    size: existsSync(entry.backupPath) ? stat(entry.backupPath).then((s) => s.size).catch(() => 0) : 0
  })).map((e) => ({ ...e, size: 0 }));
}

export async function clearRollbackHistory(cwd: string, path?: string): Promise<void> {
  await ensureChrysalisDirs(cwd);
  const dir = rollbackDir(cwd);
  const indexPath = join(dir, "index.json");
  let index: Record<string, RollbackEntry[]> = {};
  try {
    index = JSON.parse(await readFile(indexPath, "utf8"));
  } catch {}

  if (path) {
    for (const entry of index[path] ?? []) {
      try { await unlink(entry.backupPath); } catch {}
    }
    delete index[path];
  } else {
    for (const entries of Object.values(index)) {
      for (const entry of entries) {
        try { await unlink(entry.backupPath); } catch {}
      }
    }
    index = {};
  }

  await writeFile(indexPath, `${JSON.stringify(index, null, 2)}\n`, "utf8");
}

export async function rollbackHistorySize(cwd: string): Promise<{ files: number; bytes: number }> {
  await ensureChrysalisDirs(cwd);
  const dir = rollbackDir(cwd);
  const indexPath = join(dir, "index.json");
  let index: Record<string, RollbackEntry[]> = {};
  try {
    index = JSON.parse(await readFile(indexPath, "utf8"));
  } catch {}

  let totalFiles = 0;
  let totalBytes = 0;
  for (const entries of Object.values(index)) {
    totalFiles += entries.length;
    for (const entry of entries) {
      try {
        const s = await stat(entry.backupPath);
        totalBytes += s.size;
      } catch {}
    }
  }
  return { files: totalFiles, bytes: totalBytes };
}
