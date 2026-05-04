import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { JUDGE_TOOL_DEFINITIONS, executeJudgeTool, judgeWithLLM } from "../ts/core/tools/judge-tools.js";

describe("judge-tools", () => {
  test("JUDGE_TOOL_DEFINITIONS has use_llm_judge and judge_quality", () => {
    const names = JUDGE_TOOL_DEFINITIONS.map(d => d.name);
    expect(names).toContain("use_llm_judge");
    expect(names).toContain("judge_quality");
  });

  test("use_llm_judge requires content", async () => {
    const result = await executeJudgeTool("/tmp", "use_llm_judge", { content: "" });
    expect(result).toContain("Error");
  });

  test("use_llm_judge falls back to heuristic and returns structured result", async () => {
    const result = await executeJudgeTool("/tmp", "use_llm_judge", {
      content: "function add(a: number, b: number): number { return a + b; } // addition",
      criteria: "correctness, readability",
      threshold: 5.0
    });
    const parsed = JSON.parse(result);
    expect(parsed.score).toBeGreaterThanOrEqual(0);
    expect(parsed.score).toBeLessThanOrEqual(10);
    expect(parsed).toHaveProperty("passed");
    expect(parsed).toHaveProperty("verdict");
    expect(parsed).toHaveProperty("reasoning");
    expect(parsed).toHaveProperty("model");
  });

  test("judge_quality requires code", async () => {
    const result = await executeJudgeTool("/tmp", "judge_quality", { code: "" });
    expect(result).toContain("Error");
  });

  test("judge_quality returns structured result with heuristic fallback", async () => {
    const result = await executeJudgeTool("/tmp", "judge_quality", {
      code: "try { doStuff(); } catch (e) { handle(e); }",
      language: "typescript"
    });
    const parsed = JSON.parse(result);
    expect(parsed.score).toBeGreaterThanOrEqual(0);
    expect(parsed.model).toBeTruthy();
  });

  test("heuristic scoring rewards code with types, comments, error handling", async () => {
    const goodCode = [
      "function add(a: number, b: number): number {",
      "  // adds two numbers",
      "  try { return a + b; } catch (e) { throw new Error(e); }",
      "}",
      "test('add works', () => { expect(add(1,2)).toBe(3); });"
    ].join("\n");

    const badCode = "var x=1";

    const goodResult = await judgeWithLLM(goodCode, "quality", "general", 5.0);
    const badResult = await judgeWithLLM(badCode, "quality", "general", 5.0);

    expect(goodResult.score).toBeGreaterThan(badResult.score);
    expect(goodResult.reasoning).toContain("documentation");
    expect(goodResult.reasoning).toContain("error handling");
  });

  test("unknown judge tool returns error", async () => {
    const result = await executeJudgeTool("/tmp", "nonexistent_judge", {});
    expect(result).toContain("Unknown");
  });
});
