import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { globalToolRegistry } from "../ts/core/tools/tool-registry.js";

describe("tool-registry", () => {
  test("register, enable, disable, and list tools", () => {
    const registry = new (globalToolRegistry.constructor as any)();

    registry.registerTool(
      { name: "test_tool", description: "A test tool", parameters: { type: "object", properties: {} } },
      async () => "ok"
    );

    const tools = registry.listTools();
    expect(tools).toHaveLength(1);
    expect(tools[0].name).toBe("test_tool");
    expect(tools[0].enabled).toBe(true);

    registry.disableTool("test_tool");
    expect(registry.listTools()[0].enabled).toBe(false);

    registry.enableTool("test_tool");
    expect(registry.listTools()[0].enabled).toBe(true);
  });

  test("unregister removes a tool", () => {
    const registry = new (globalToolRegistry.constructor as any)();
    registry.registerTool(
      { name: "removable", description: "To be removed", parameters: { type: "object", properties: {} } },
      async () => "ok"
    );
    expect(registry.hasTool("removable")).toBe(true);
    expect(registry.unregisterTool("removable")).toBe(true);
    expect(registry.hasTool("removable")).toBe(false);
  });

  test("re-registering a tool increments version", () => {
    const registry = new (globalToolRegistry.constructor as any)();
    registry.registerTool(
      { name: "versioned", description: "v1", parameters: { type: "object", properties: {} } },
      async () => "ok"
    );
    registry.registerTool(
      { name: "versioned", description: "v2", parameters: { type: "object", properties: {} } },
      async () => "ok2"
    );
    const tool = registry.getTool("versioned");
    expect(tool.version).toBe(2);
    expect(tool.definition.description).toBe("v2");
  });

  test("getToolCount tracks enabled and disabled", () => {
    const registry = new (globalToolRegistry.constructor as any)();
    registry.registerTool(
      { name: "a", description: "A", parameters: { type: "object", properties: {} } },
      async () => "ok"
    );
    registry.registerTool(
      { name: "b", description: "B", parameters: { type: "object", properties: {} } },
      async () => "ok"
    );
    registry.disableTool("a");

    const counts = registry.getToolCount();
    expect(counts.total).toBe(2);
    expect(counts.enabled).toBe(1);
    expect(counts.disabled).toBe(1);
  });

  test("execute calls the tool executor", async () => {
    const registry = new (globalToolRegistry.constructor as any)();
    registry.registerTool(
      { name: "adder", description: "Adds", parameters: { type: "object", properties: { a: { type: "number" }, b: { type: "number" } } } },
      async (_cwd: string, _name: string, args: Record<string, unknown>) => String(Number(args.a) + Number(args.b))
    );

    const result = await registry.execute("adder", { a: 3, b: 4 });
    expect(result).toBe("7");
  });

  test("execute throws for missing tool", async () => {
    const registry = new (globalToolRegistry.constructor as any)();
    expect(registry.execute("missing", {})).rejects.toThrow("not found");
  });

  test("execute throws for disabled tool", async () => {
    const registry = new (globalToolRegistry.constructor as any)();
    registry.registerTool(
      { name: "off", description: "Off", parameters: { type: "object", properties: {} } },
      async () => "ok"
    );
    registry.disableTool("off");
    expect(registry.execute("off", {})).rejects.toThrow("disabled");
  });

  test("emits events on register, enable, disable", () => {
    const registry = new (globalToolRegistry.constructor as any)();
    const events: string[] = [];
    registry.on("tool:registered", () => events.push("registered"));
    registry.on("tool:enabled", () => events.push("enabled"));
    registry.on("tool:disabled", () => events.push("disabled"));

    registry.registerTool(
      { name: "evt", description: "Evt", parameters: { type: "object", properties: {} } },
      async () => "ok"
    );
    registry.disableTool("evt");
    registry.enableTool("evt");

    expect(events).toEqual(["registered", "disabled", "enabled"]);
  });

  test("setCwd updates the working directory", () => {
    const registry = new (globalToolRegistry.constructor as any)();
    registry.setCwd("/some/path");
    expect(registry.cwd).toBe("/some/path");
  });

  test("enableTool and disableTool return false for missing tools", () => {
    const registry = new (globalToolRegistry.constructor as any)();
    expect(registry.enableTool("missing")).toBe(false);
    expect(registry.disableTool("missing")).toBe(false);
  });
});
