import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { EVOLVER_TOOL_DEFINITIONS, executeEvolverTool } from "../ts/core/tools/evolver-tools.js";
import { globalToolRegistry } from "../ts/core/tools/tool-registry.js";
import { saveToolEvolutionState, defaultToolEvolutionState, type ToolEvolutionState, type ToolVariant } from "../ts/core/tools/tool-evolution.js";

describe("evolver-tools", () => {
  test("EVOLVER_TOOL_DEFINITIONS has expected tools", () => {
    const names = EVOLVER_TOOL_DEFINITIONS.map(d => d.name);
    expect(names).toContain("evolve_tool");
    expect(names).toContain("list_tools");
    expect(names).toContain("tool_variants");
    expect(names).toContain("select_tool_variant");
    expect(names).toContain("enable_tool");
    expect(names).toContain("disable_tool");
    expect(names).toContain("tool_stats");
    expect(names).toContain("tool_evolution_stats");
  });

  test("evolve_tool requires tool_name and feedback", async () => {
    const result = await executeEvolverTool("/tmp", "evolve_tool", {});
    const parsed = JSON.parse(result);
    expect(parsed.error).toBeTruthy();
  });

  test("evolve_tool returns error for nonexistent tool", async () => {
    const result = await executeEvolverTool("/tmp", "evolve_tool", {
      tool_name: "nonexistent_tool_xyz",
      feedback: "make it better"
    });
    const parsed = JSON.parse(result);
    expect(parsed.error).toContain("not found");
  });

  test("list_tools returns registered tools", async () => {
    const FreshRegistry = globalToolRegistry.constructor as any;
    const registry = new FreshRegistry();
    registry.registerTool(
      { name: "listme", description: "List me", parameters: { type: "object", properties: {} } },
      async () => "ok"
    );

    const origSetCwd = globalToolRegistry.setCwd;
    globalToolRegistry.setCwd = registry.setCwd.bind(registry);
    (globalToolRegistry as any).tools = registry.tools;

    const result = await executeEvolverTool("/tmp", "list_tools", {});
    const parsed = JSON.parse(result);
    expect(parsed.total).toBeGreaterThanOrEqual(1);

    globalToolRegistry.setCwd = origSetCwd;
  });

  test("tool_stats returns counts", async () => {
    const result = await executeEvolverTool("/tmp", "tool_stats", {});
    const parsed = JSON.parse(result);
    expect(parsed).toHaveProperty("total");
    expect(parsed).toHaveProperty("enabled");
    expect(parsed).toHaveProperty("disabled");
  });

  test("tool_evolution_stats returns string summary", async () => {
    const result = await executeEvolverTool("/tmp", "tool_evolution_stats", {});
    expect(typeof result).toBe("string");
    expect(result).toContain("Tool Evolution");
  });

  test("tool_variants returns variant list", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-et-"));
    try {
      await mkdir(join(cwd, ".chrysalis", "state"), { recursive: true });
      const state: ToolEvolutionState = {
        variants: {
          my_tool: [{ id: "v1", toolName: "my_tool", description: "d", parameters: {}, active: true, score: 5, noveltyScore: 0.4, createdAt: new Date().toISOString(), model: "heuristic", feedback: "test" }]
        },
        fieldHistory: {},
        updatedAt: new Date().toISOString()
      };
      saveToolEvolutionState(cwd, state);

      const result = await executeEvolverTool(cwd, "tool_variants", { tool_name: "my_tool" });
      const parsed = JSON.parse(result);
      expect(parsed.count).toBe(1);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("enable_tool and disable_tool require tool_name", async () => {
    const enableResult = await executeEvolverTool("/tmp", "enable_tool", {});
    expect(JSON.parse(enableResult).error).toBeTruthy();

    const disableResult = await executeEvolverTool("/tmp", "disable_tool", {});
    expect(JSON.parse(disableResult).error).toBeTruthy();
  });

  test("select_tool_variant requires tool_name and variant_id", async () => {
    const result = await executeEvolverTool("/tmp", "select_tool_variant", {});
    const parsed = JSON.parse(result);
    expect(parsed.error).toBeTruthy();
  });

  test("unknown evolver tool returns error", async () => {
    const result = await executeEvolverTool("/tmp", "nonexistent_evolver", {});
    expect(result).toContain("Unknown");
  });
});
