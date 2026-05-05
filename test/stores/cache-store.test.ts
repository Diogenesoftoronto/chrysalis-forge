import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  cacheGet,
  cacheSet,
  cacheInvalidate,
  cacheInvalidateByTag,
  cacheCleanup,
  cacheClear,
  cacheStats
} from "../../ts/core/stores/cache-store.js";

describe("cache-store", () => {
  test("get/set/invalidate and stats", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-cache-"));
    try {
      const missing = await cacheGet(cwd, "nope");
      expect(missing).toBeNull();

      await cacheSet(cwd, "key1", "value1", 86400, ["api", "fetch"]);
      await cacheSet(cwd, "key2", "value2", 86400, ["api"]);

      const val = await cacheGet(cwd, "key1");
      expect(val).toBe("value1");

      const stats = await cacheStats(cwd);
      expect(stats.total).toBe(2);
      expect(stats.valid).toBe(2);
      expect(stats.tags["api"]).toBe(2);

      await cacheInvalidate(cwd, "key1");
      const afterInv = await cacheGet(cwd, "key1");
      expect(afterInv).toBeNull();
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("invalidate by tag and cleanup", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-cache-"));
    try {
      await cacheSet(cwd, "a", "1", 86400, ["api"]);
      await cacheSet(cwd, "b", "2", 86400, ["api"]);
      await cacheSet(cwd, "c", "3", 86400, ["cdn"]);

      const result = await cacheInvalidateByTag(cwd, "api");
      expect(result).toContain("2");

      const stats = await cacheStats(cwd);
      expect(stats.total).toBe(1);

      await cacheClear(cwd);
      const afterClear = await cacheStats(cwd);
      expect(afterClear.total).toBe(0);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("expired entries are skipped on get", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-cache-"));
    try {
      await cacheSet(cwd, "short", "data", 1);
      await new Promise((r) => setTimeout(r, 1100));
      const stats = await cacheStats(cwd);
      expect(stats.expired).toBe(1);
      expect(stats.valid).toBe(0);

      const val = await cacheGet(cwd, "short");
      expect(val).toBeNull();

      await cacheCleanup(cwd);
      const after = await cacheStats(cwd);
      expect(after.total).toBe(0);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
