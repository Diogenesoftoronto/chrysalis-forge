import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { TEST_TOOL_DEFINITIONS, executeTestTool } from "../ts/core/tools/test-tools.js";

describe("test-tools", () => {
  test("TEST_TOOL_DEFINITIONS has generate_tests and generate_test_cases", () => {
    const names = TEST_TOOL_DEFINITIONS.map(d => d.name);
    expect(names).toContain("generate_tests");
    expect(names).toContain("generate_test_cases");
  });

  test("generate_tests requires file_path", async () => {
    const result = await executeTestTool("/tmp", "generate_tests", { file_path: "" });
    expect(result).toContain("Error");
  });

  test("generate_tests produces heuristic tests for nonexistent file", async () => {
    const result = await executeTestTool("/tmp", "generate_tests", {
      file_path: "nonexistent.ts"
    });
    const parsed = JSON.parse(result);
    expect(parsed.framework).toBe("vitest");
    expect(parsed.model).toBeTruthy();
  });

  test("generate_tests auto-detects framework from extension", async () => {
    const tsResult = await executeTestTool("/tmp", "generate_tests", { file_path: "foo.ts" });
    expect(JSON.parse(tsResult).framework).toBe("vitest");

    const pyResult = await executeTestTool("/tmp", "generate_tests", { file_path: "foo.py" });
    expect(JSON.parse(pyResult).framework).toBe("pytest");

    const goResult = await executeTestTool("/tmp", "generate_tests", { file_path: "foo.go" });
    expect(JSON.parse(goResult).framework).toBe("golang");
  });

  test("generate_tests reads actual file content when present", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-tt-"));
    try {
      await writeFile(join(cwd, "example.ts"), "function add(a: number, b: number) { return a + b; }");
      const result = await executeTestTool(cwd, "generate_tests", { file_path: "example.ts" });
      const parsed = JSON.parse(result);
      expect(parsed.testCount).toBeGreaterThan(0);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("generate_test_cases requires function_signature and code_context", async () => {
    const result = await executeTestTool("/tmp", "generate_test_cases", {});
    expect(result).toContain("Error");
  });

  test("generate_test_cases produces heuristic test cases", async () => {
    const result = await executeTestTool("/tmp", "generate_test_cases", {
      function_signature: "add(a: number, b: number): number",
      code_context: "function add(a, b) { return a + b; }"
    });
    const parsed = JSON.parse(result);
    expect(parsed.tests).toBeDefined();
    expect(parsed.model).toBeTruthy();
  });

  test("generate_tests respects framework parameter", async () => {
    const result = await executeTestTool("/tmp", "generate_tests", {
      file_path: "foo.ts",
      framework: "jest"
    });
    expect(JSON.parse(result).framework).toBe("jest");
  });

  test("unknown test tool returns error", async () => {
    const result = await executeTestTool("/tmp", "nonexistent_test", {});
    expect(result).toContain("Unknown");
  });

  test("coverage_target parameter name is correct in definition", () => {
    const genTestsDef = TEST_TOOL_DEFINITIONS.find(d => d.name === "generate_tests");
    expect(genTestsDef).toBeDefined();
    const props = genTestsDef!.parameters.properties as Record<string, any>;
    expect(props).toHaveProperty("coverage_target");
    expect(props).not.toHaveProperty("覆盖率_target");
  });
});
