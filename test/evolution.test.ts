import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import {
  evolveHarnessStrategy,
  instructionNoveltyScore,
  recordEvolutionEvaluation,
  selectEliteEntry,
  loadEvolutionState,
  suggestProfileFromStats
} from "../ts/core/evolution.js";

describe("evolution", () => {
  test("novelty scoring prefers distinct prompts and archive selection picks the nearest elite", () => {
    expect(instructionNoveltyScore(["use tools carefully"], "use tools carefully")).toBe(0);
    expect(instructionNoveltyScore(["use tools carefully"], "prefer terminal-first workflows")).toBeGreaterThan(0.2);

    const archive = [
      {
        id: "a",
        family: "prompt" as const,
        taskFamily: "build",
        content: "alpha",
        score: 4,
        phenotype: { accuracy: 4, latency: 1, cost: 1, usage: 1 },
        binKey: "cheap:fast:compact",
        createdAt: new Date().toISOString(),
        active: true,
        model: "heuristic",
        metadata: {}
      },
      {
        id: "b",
        family: "prompt" as const,
        taskFamily: "build",
        content: "beta",
        score: 9,
        phenotype: { accuracy: 9, latency: 8, cost: 8, usage: 8 },
        binKey: "premium:slow:verbose",
        createdAt: new Date().toISOString(),
        active: true,
        model: "heuristic",
        metadata: {}
      }
    ];

    const selected = selectEliteEntry(archive, { accuracy: 8.5, latency: 7.5, cost: 7.5, usage: 7.5 });
    expect(selected?.id).toBe("b");
  });

  test("harness evolution and profile stats persist under .chrysalis", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-evolution-"));
    try {
      const initial = await loadEvolutionState(cwd);
      expect(initial.harness.executionPriority).toBe("best");

      const next = await evolveHarnessStrategy(cwd, "make this cheaper and more cost sensitive", "best");
      expect(next.harness.executionPriority).toBe("cheap");

      await recordEvolutionEvaluation(cwd, {
        ts: Date.now(),
        taskId: "task-1",
        success: true,
        profile: "fast",
        taskType: "build",
        toolsUsed: ["read", "bash"],
        durationMs: 1200,
        feedback: "worked",
        evalStage: "default",
        model: "openai",
        score: 9,
        latencyMs: 4,
        costUsd: 0.02,
        binKey: "cheap:fast:compact"
      });

      const suggested = await suggestProfileFromStats(cwd, "build");
      expect(suggested.profile).toBe("fast");
      expect(suggested.score).toBeGreaterThan(0);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
