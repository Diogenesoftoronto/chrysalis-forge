import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  sessionCreate,
  sessionSwitch,
  sessionList,
  sessionDelete,
  sessionGetActive,
  sessionUpdateTitle,
  sessionResumeById
} from "../../ts/core/stores/context-store.js";

describe("context-store", () => {
  test("create, switch, list, delete sessions", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-ctx-"));
    try {
      const db = await sessionCreate(cwd, "work", { title: "Work session" });
      expect(db.items["work"]).toBeDefined();
      expect(db.metadata["work"].title).toBe("Work session");

      const { names, active } = await sessionList(cwd);
      expect(names).toContain("default");
      expect(names).toContain("work");
      expect(active).toBe("default");

      await sessionSwitch(cwd, "work");
      const after = await sessionList(cwd);
      expect(after.active).toBe("work");

      const activeCtx = await sessionGetActive(cwd);
      expect(activeCtx.mode).toBe("code");

      await sessionSwitch(cwd, "default");
      await sessionDelete(cwd, "work");
      const afterDel = await sessionList(cwd);
      expect(afterDel.names).not.toContain("work");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("cannot delete active session and cannot create duplicate", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-ctx-"));
    try {
      await expect(sessionDelete(cwd, "default")).rejects.toThrow("Cannot delete active session");
      await expect(sessionCreate(cwd, "default")).rejects.toThrow("already exists");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("update title and resume by ID", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-ctx-"));
    try {
      const db = await sessionCreate(cwd, "test", { id: "sess-123", title: "Original" });
      expect(db.metadata["test"].title).toBe("Original");

      await sessionUpdateTitle(cwd, "test", "Updated");
      const db2 = await sessionCreate(cwd, "other"); // reload happens internally
      expect(db2.metadata["test"].title).toBe("Updated");

      const resumed = await sessionResumeById(cwd, "sess-123");
      expect(resumed).toBe("test");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
