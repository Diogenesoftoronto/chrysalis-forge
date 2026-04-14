import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  fileBackup,
  fileRollback,
  fileRollbackList,
  clearRollbackHistory,
  rollbackHistorySize
} from "../../ts/core/stores/rollback-store.js";

describe("rollback-store", () => {
  test("backup and rollback a file", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-rollback-"));
    const filePath = join(cwd, "test.txt");
    try {
      await writeFile(filePath, "version 1");
      await fileBackup(cwd, filePath);

      await writeFile(filePath, "version 2");

      const result = await fileRollback(cwd, filePath, 1);
      expect(result.ok).toBe(true);

      const { readFile } = await import("node:fs/promises");
      const content = await readFile(filePath, "utf8");
      expect(content).toBe("version 1");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("rollback list and clear history", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-rollback-"));
    const filePath = join(cwd, "test.txt");
    try {
      await writeFile(filePath, "a");
      await fileBackup(cwd, filePath);
      await writeFile(filePath, "b");
      await fileBackup(cwd, filePath);

      const list = await fileRollbackList(cwd, filePath);
      expect(list.length).toBeGreaterThanOrEqual(2);

      const size = await rollbackHistorySize(cwd);
      expect(size.files).toBeGreaterThanOrEqual(2);

      await clearRollbackHistory(cwd, filePath);
      const afterClear = await rollbackHistorySize(cwd);
      expect(afterClear.files).toBe(0);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("rollback fails gracefully for missing file", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-rollback-"));
    try {
      const result = await fileRollback(cwd, "/nonexistent/path.txt", 1);
      expect(result.ok).toBe(false);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
