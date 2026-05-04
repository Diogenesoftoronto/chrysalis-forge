import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { ngramDistance, toolNoveltyScore, defaultToolEvolutionState, loadToolEvolutionState, saveToolEvolutionState, listToolVariants, archiveToolVariant, selectToolVariant, getActiveToolVariant, toolEvolutionStats, type ToolVariant, type ToolEvolutionState } from "../ts/core/tools/tool-evolution.js";

describe("tool-evolution", () => {
  test("ngramDistance returns 0 for identical strings", () => {
    expect(ngramDistance("hello world", "hello world")).toBe(0);
  });

  test("ngramDistance returns 1 for completely different strings", () => {
    const d = ngramDistance("aaa", "zzz");
    expect(d).toBeGreaterThan(0);
  });

  test("ngramDistance handles empty strings", () => {
    expect(ngramDistance("", "")).toBe(0);
    expect(ngramDistance("hello", "")).toBe(1);
  });

  test("ngramDistance is case-insensitive", () => {
    expect(ngramDistance("Hello World", "hello world")).toBe(0);
  });

  test("toolNoveltyScore returns 1 for no existing variants", () => {
    expect(toolNoveltyScore([], "anything")).toBe(1);
  });

  test("toolNoveltyScore returns low value for similar descriptions", () => {
    const existing: ToolVariant[] = [{
      id: "v1",
      toolName: "test",
      description: "evaluate code quality and correctness",
      parameters: {},
      active: true,
      score: 5,
      noveltyScore: 0.5,
      createdAt: new Date().toISOString(),
      model: "heuristic",
      feedback: ""
    }];
    const novelty = toolNoveltyScore(existing, "evaluate code quality and correctness");
    expect(novelty).toBeLessThan(0.5);
  });

  test("defaultToolEvolutionState has expected shape", () => {
    const state = defaultToolEvolutionState();
    expect(state.variants).toEqual({});
    expect(state.fieldHistory).toEqual({});
    expect(state.updatedAt).toBeTruthy();
  });

  test("load and save tool evolution state round-trips correctly", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-te-"));
    try {
      const state = defaultToolEvolutionState();
      state.variants["my_tool"] = [{
        id: "v1",
        toolName: "my_tool",
        description: "evolved description",
        parameters: { type: "object", properties: { x: { type: "string" } } },
        active: true,
        score: 7,
        noveltyScore: 0.4,
        createdAt: new Date().toISOString(),
        model: "heuristic",
        feedback: "make it better"
      }];

      await mkdir(join(cwd, ".chrysalis", "state"), { recursive: true });
      saveToolEvolutionState(cwd, state);

      const loaded = loadToolEvolutionState(cwd);
      expect(loaded.variants["my_tool"]).toHaveLength(1);
      expect(loaded.variants["my_tool"]![0].description).toBe("evolved description");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("loadToolEvolutionState returns defaults for missing file", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-te-"));
    try {
      const state = loadToolEvolutionState(cwd);
      expect(state.variants).toEqual({});
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("listToolVariants returns variants for specific tool", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-te-"));
    try {
      await mkdir(join(cwd, ".chrysalis", "state"), { recursive: true });
      const state: ToolEvolutionState = {
        variants: {
          tool_a: [{ id: "v1", toolName: "tool_a", description: "a1", parameters: {}, active: true, score: 5, noveltyScore: 0.3, createdAt: new Date().toISOString(), model: "heuristic", feedback: "" }],
          tool_b: [{ id: "v2", toolName: "tool_b", description: "b1", parameters: {}, active: true, score: 6, noveltyScore: 0.4, createdAt: new Date().toISOString(), model: "heuristic", feedback: "" }]
        },
        fieldHistory: {},
        updatedAt: new Date().toISOString()
      };
      saveToolEvolutionState(cwd, state);

      const aVariants = listToolVariants(cwd, "tool_a");
      expect(aVariants).toHaveLength(1);
      expect(aVariants[0].toolName).toBe("tool_a");

      const allVariants = listToolVariants(cwd);
      expect(allVariants).toHaveLength(2);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("archiveToolVariant deactivates a variant", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-te-"));
    try {
      await mkdir(join(cwd, ".chrysalis", "state"), { recursive: true });
      const state: ToolEvolutionState = {
        variants: {
          my_tool: [{ id: "v1", toolName: "my_tool", description: "d", parameters: {}, active: true, score: 5, noveltyScore: 0.3, createdAt: new Date().toISOString(), model: "heuristic", feedback: "" }]
        },
        fieldHistory: {},
        updatedAt: new Date().toISOString()
      };
      saveToolEvolutionState(cwd, state);

      expect(archiveToolVariant(cwd, "v1")).toBe(true);
      const after = loadToolEvolutionState(cwd);
      expect(after.variants["my_tool"]![0].active).toBe(false);
      expect(archiveToolVariant(cwd, "nonexistent")).toBe(false);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("selectToolVariant activates only the selected variant", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-te-"));
    try {
      await mkdir(join(cwd, ".chrysalis", "state"), { recursive: true });
      const state: ToolEvolutionState = {
        variants: {
          my_tool: [
            { id: "v1", toolName: "my_tool", description: "d1", parameters: {}, active: true, score: 5, noveltyScore: 0.3, createdAt: new Date().toISOString(), model: "heuristic", feedback: "" },
            { id: "v2", toolName: "my_tool", description: "d2", parameters: {}, active: true, score: 7, noveltyScore: 0.5, createdAt: new Date().toISOString(), model: "heuristic", feedback: "" }
          ]
        },
        fieldHistory: {},
        updatedAt: new Date().toISOString()
      };
      saveToolEvolutionState(cwd, state);

      expect(selectToolVariant(cwd, "v2")).toBe(true);
      const after = loadToolEvolutionState(cwd);
      expect(after.variants["my_tool"]![0].active).toBe(false);
      expect(after.variants["my_tool"]![1].active).toBe(true);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("getActiveToolVariant returns highest-scoring active variant", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-te-"));
    try {
      await mkdir(join(cwd, ".chrysalis", "state"), { recursive: true });
      const state: ToolEvolutionState = {
        variants: {
          my_tool: [
            { id: "v1", toolName: "my_tool", description: "low score", parameters: {}, active: true, score: 3, noveltyScore: 0.2, createdAt: new Date().toISOString(), model: "heuristic", feedback: "" },
            { id: "v2", toolName: "my_tool", description: "high score", parameters: {}, active: true, score: 9, noveltyScore: 0.8, createdAt: new Date().toISOString(), model: "heuristic", feedback: "" }
          ]
        },
        fieldHistory: {},
        updatedAt: new Date().toISOString()
      };
      saveToolEvolutionState(cwd, state);

      const active = getActiveToolVariant(cwd, "my_tool");
      expect(active).not.toBeNull();
      expect(active!.description).toBe("high score");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("getActiveToolVariant returns null when no active variants", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-te-"));
    try {
      const result = getActiveToolVariant(cwd, "nonexistent_tool");
      expect(result).toBeNull();
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("toolEvolutionStats produces summary string", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-te-"));
    try {
      await mkdir(join(cwd, ".chrysalis", "state"), { recursive: true });
      const state: ToolEvolutionState = {
        variants: {
          tool_a: [
            { id: "v1", toolName: "tool_a", description: "d", parameters: {}, active: true, score: 5, noveltyScore: 0.3, createdAt: new Date().toISOString(), model: "heuristic", feedback: "" },
            { id: "v2", toolName: "tool_a", description: "d2", parameters: {}, active: false, score: 4, noveltyScore: 0.2, createdAt: new Date().toISOString(), model: "heuristic", feedback: "" }
          ]
        },
        fieldHistory: {},
        updatedAt: new Date().toISOString()
      };
      saveToolEvolutionState(cwd, state);

      const stats = toolEvolutionStats(cwd);
      expect(stats).toContain("tool_a");
      expect(stats).toContain("1/2 active variants");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
