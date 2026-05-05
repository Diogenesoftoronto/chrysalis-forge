import { appendFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";

import { ensureChrysalisDirs, traceStorePath } from "../paths.js";
import { type TraceRecord } from "../types.js";

export async function logTrace(cwd: string, record: Omit<TraceRecord, "ts">): Promise<void> {
  await ensureChrysalisDirs(cwd);
  const path = traceStorePath(cwd);
  const entry: TraceRecord = { ...record, ts: Math.floor(Date.now() / 1000) };
  await appendFile(path, `${JSON.stringify(entry)}\n`, "utf8");
}
