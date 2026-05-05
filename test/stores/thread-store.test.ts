import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  threadCreate,
  threadFind,
  threadList,
  threadSwitch,
  threadContinue,
  threadSpawnChild,
  threadGetActive,
  threadGetRelations,
  threadUpdate
} from "../../ts/core/stores/thread-store.js";

describe("thread-store", () => {
  test("create, find, list, switch threads", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-thread-"));
    try {
      const id = await threadCreate(cwd, "First thread", "my-project");
      expect(id.startsWith("T-")).toBe(true);

      const found = await threadFind(cwd, id);
      expect(found?.title).toBe("First thread");
      expect(found?.project).toBe("my-project");

      const list = await threadList(cwd);
      expect(list.length).toBe(1);
      expect(list[0].id).toBe(id);

      await threadSwitch(cwd, id);
      const active = await threadGetActive(cwd);
      expect(active).toBe(id);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("continue and spawn child create relations", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-thread-"));
    try {
      const parentId = await threadCreate(cwd, "Parent thread");
      const childId = await threadSpawnChild(cwd, parentId, "Child task");
      expect(childId.startsWith("T-")).toBe(true);

      const relations = await threadGetRelations(cwd, childId);
      expect(relations.length).toBe(1);
      expect(relations[0].type).toBe("child_of");
      expect(relations[0].to).toBe(parentId);

      const continueId = await threadContinue(cwd, parentId, "Continued thread");
      const contRels = await threadGetRelations(cwd, continueId);
      expect(contRels.some((r) => r.type === "continues_from")).toBe(true);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("update thread title and status", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-thread-"));
    try {
      const id = await threadCreate(cwd, "Original");
      await threadUpdate(cwd, id, { title: "Updated", status: "done" });
      const updated = await threadFind(cwd, id);
      expect(updated?.title).toBe("Updated");
      expect(updated?.status).toBe("done");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
