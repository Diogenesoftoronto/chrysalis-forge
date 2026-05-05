import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  loadSessionStats,
  addTurn,
  addTokens,
  addCost,
  recordToolUse,
  recordFileOp,
  resetSessionStats,
  formatTokens,
  formatCost,
  getSessionStatsDisplay
} from "../../ts/core/stores/session-stats.js";

describe("session-stats", () => {
  test("loadSessionStats returns defaults and addTurn increments", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-stats-"));
    try {
      const stats = await loadSessionStats(cwd);
      expect(stats.turns).toBe(0);
      expect(stats.tokensIn).toBe(0);
      expect(stats.totalCost).toBe(0);

      const after = await addTurn(cwd, { tokensIn: 100, tokensOut: 50, cost: 0.01 });
      expect(after.turns).toBe(1);
      expect(after.tokensIn).toBe(100);
      expect(after.tokensOut).toBe(50);
      expect(after.totalCost).toBe(0.01);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("addTokens and addCost accumulate", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-stats-"));
    try {
      await addTokens(cwd, 200, 100);
      await addTokens(cwd, 50, 25);
      const stats = await loadSessionStats(cwd);
      expect(stats.tokensIn).toBe(250);
      expect(stats.tokensOut).toBe(125);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("recordToolUse counts and recordFileOp deduplicates", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-stats-"));
    try {
      await recordToolUse(cwd, "bash");
      await recordToolUse(cwd, "bash");
      await recordToolUse(cwd, "read");
      const stats = await loadSessionStats(cwd);
      expect(stats.toolsUsed["bash"]).toBe(2);
      expect(stats.toolsUsed["read"]).toBe(1);

      await recordFileOp(cwd, "foo.ts", "write");
      await recordFileOp(cwd, "foo.ts", "write");
      await recordFileOp(cwd, "bar.ts", "read");
      const after = await loadSessionStats(cwd);
      expect(after.filesWritten).toEqual(["foo.ts"]);
      expect(after.filesRead).toEqual(["bar.ts"]);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("resetSessionStats clears and format helpers work", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-stats-"));
    try {
      await addTurn(cwd, { tokensIn: 5000, tokensOut: 2000, cost: 0.5 });
      const reset = await resetSessionStats(cwd);
      expect(reset.turns).toBe(0);

      expect(formatTokens(1500)).toBe("1.5k");
      expect(formatTokens(2000000)).toBe("2.0M");
      expect(formatTokens(42)).toBe("42");
      expect(formatCost(0.005)).toBe("$0.0050");
      expect(formatCost(0.5)).toBe("$0.500");
      expect(formatCost(10)).toBe("$10.00");

      const display = getSessionStatsDisplay(reset);
      expect(display.turns).toBe(0);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
