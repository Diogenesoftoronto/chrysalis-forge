import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { PRIORITY_TOOL_DEFINITIONS, executePriorityTool } from "../ts/core/tools/priority-tools.js";

describe("priority-tools", () => {
  test("PRIORITY_TOOL_DEFINITIONS has set_priority, get_priority, suggest_priority", () => {
    const names = PRIORITY_TOOL_DEFINITIONS.map(d => d.name);
    expect(names).toContain("set_priority");
    expect(names).toContain("get_priority");
    expect(names).toContain("suggest_priority");
  });

  test("set_priority saves and get_priority retrieves the active profile", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-pt-"));
    try {
      const setResult = await executePriorityTool(cwd, "set_priority", {
        profile: "fast",
        reason: "running tests"
      });
      const setParsed = JSON.parse(setResult);
      expect(setParsed.profile).toBe("fast");

      const getResult = await executePriorityTool(cwd, "get_priority", {});
      const getParsed = JSON.parse(getResult);
      expect(getParsed.activeProfile).toBe("fast");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("set_priority interprets natural language phrases", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-pt-"));
    try {
      const result = await executePriorityTool(cwd, "set_priority", {
        profile: "make it cheap"
      });
      const parsed = JSON.parse(result);
      expect(parsed.profile).toBe("cheap");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("suggest_priority maps task types to profiles", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-pt-"));
    try {
      const debugResult = await executePriorityTool(cwd, "suggest_priority", { task_type: "debug" });
      expect(JSON.parse(debugResult).suggestedProfile).toBe("fast");

      const implResult = await executePriorityTool(cwd, "suggest_priority", { task_type: "implement" });
      expect(JSON.parse(implResult).suggestedProfile).toBe("best");

      const researchResult = await executePriorityTool(cwd, "suggest_priority", { task_type: "research" });
      expect(JSON.parse(researchResult).suggestedProfile).toBe("cheap");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("suggest_priority analyzes natural language tasks", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-pt-"));
    try {
      const result = await executePriorityTool(cwd, "suggest_priority", {
        task: "make this run as fast as possible"
      });
      const parsed = JSON.parse(result);
      expect(parsed.suggestedProfile).toBe("fast");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("get_priority returns default profile when none set", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-pt-"));
    try {
      const result = await executePriorityTool(cwd, "get_priority", {});
      const parsed = JSON.parse(result);
      expect(parsed.activeProfile).toBe("best");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("unknown priority tool returns error", async () => {
    const result = await executePriorityTool("/tmp", "nonexistent_priority", {});
    expect(result).toContain("Unknown");
  });
});
