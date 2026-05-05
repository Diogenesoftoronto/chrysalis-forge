import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  storeCreate,
  storeDelete,
  storeList,
  storeGet,
  storeSet,
  storeRemove,
  storeDump,
  storeDescribe,
  storeGetSpec
} from "../../ts/core/stores/store-registry.js";

describe("store-registry", () => {
  test("create, list, delete stores across namespaces", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-registry-"));
    try {
      const spec = await storeCreate(cwd, "config", "kv", { namespace: "project", description: "Project config overrides" });
      expect(spec.name).toBe("config");
      expect(spec.namespace).toBe("project");
      expect(spec.kind).toBe("kv");

      await storeCreate(cwd, "events", "log", { namespace: "project" });
      await storeCreate(cwd, "tags", "set", { namespace: "default" });
      await storeCreate(cwd, "tasks", "counter", { description: "Task count" });

      const all = await storeList(cwd);
      expect(all.length).toBe(4);

      const projectStores = await storeList(cwd, { namespace: "project" });
      expect(projectStores.length).toBe(2);

      const kvStores = await storeList(cwd, { kind: "kv" });
      expect(kvStores.length).toBe(1);

      const desc = await storeDescribe(cwd);
      expect(desc).toContain("project/config (kv)");

      await storeDelete(cwd, "tags", "default");
      const after = await storeList(cwd);
      expect(after.length).toBe(3);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("kv store get/set/remove", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-registry-"));
    try {
      await storeCreate(cwd, "settings", "kv");
      await storeSet(cwd, "settings", "theme", '"dark"');
      await storeSet(cwd, "settings", "verbose", "true");

      const theme = await storeGet(cwd, "settings", "theme");
      expect(theme).toBe('"dark"');

      const verbose = await storeGet(cwd, "settings", "verbose");
      expect(verbose).toBe("true");

      const missing = await storeGet(cwd, "settings", "missing");
      expect(missing).toBe("null");

      await storeRemove(cwd, "settings", "theme");
      const after = await storeGet(cwd, "settings", "theme");
      expect(after).toBe("null");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("log store appends entries", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-registry-"));
    try {
      await storeCreate(cwd, "decisions", "log");
      await storeSet(cwd, "decisions", "choice", '"use-bun"');
      await storeSet(cwd, "decisions", "choice", '"use-deno"');

      const first = await storeGet(cwd, "decisions", "0");
      const parsed = JSON.parse(first);
      expect(parsed.choice).toBe("use-bun");

      const dump = await storeDump(cwd, "decisions");
      const dumpParsed = JSON.parse(dump);
      expect(dumpParsed.data.length).toBe(2);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("set store deduplicates and removes", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-registry-"));
    try {
      await storeCreate(cwd, "files", "set");
      await storeSet(cwd, "files", "entry", '"main.ts"');
      await storeSet(cwd, "files", "entry", '"util.ts"');
      await storeSet(cwd, "files", "entry", '"main.ts"');

      const dump = await storeDump(cwd, "files");
      const parsed = JSON.parse(dump);
      expect(parsed.data.length).toBe(2);

      await storeRemove(cwd, "files", '"main.ts"');
      const after = await storeDump(cwd, "files");
      const afterParsed = JSON.parse(after);
      expect(afterParsed.data.length).toBe(1);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("counter store increments", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-registry-"));
    try {
      await storeCreate(cwd, "runs", "counter");
      await storeSet(cwd, "runs", "value", "1");
      await storeSet(cwd, "runs", "value", "3");

      const val = await storeGet(cwd, "runs", "value");
      const parsed = JSON.parse(val);
      expect(parsed.value).toBe(4);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("duplicate create throws, missing store throws", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-registry-"));
    try {
      await storeCreate(cwd, "dup", "kv");
      await expect(storeCreate(cwd, "dup", "kv")).rejects.toThrow("already exists");
      await expect(storeGet(cwd, "nonexistent", "x")).rejects.toThrow("not found");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("invalid kind throws", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-registry-"));
    try {
      await expect(storeCreate(cwd, "bad", "invalid" as any)).rejects.toThrow("Invalid store kind");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
