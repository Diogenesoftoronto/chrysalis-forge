import { describe, expect, test } from "bun:test";
import fc from "fast-check";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { evolveHarnessStrategy, loadEvolutionState } from "../ts/core/evolution.js";
import { writeTaskPlanArtifact } from "../ts/core/project.js";

function benignWords(): fc.Arbitrary<string> {
  return fc
    .array(fc.constantFrom("alpha", "beta", "gamma", "delta", "omega", "kappa", "sigma"), {
      minLength: 0,
      maxLength: 6
    })
    .map((parts) => parts.join(" "));
}

describe("pi runtime", () => {
  test("harness mutation responds to prompt cues", async () => {
    await fc.assert(
      fc.asyncProperty(benignWords(), async (suffix) => {
        const cwd = await mkdtemp(join(tmpdir(), "chrysalis-pi-harness-"));
        try {
          const cheap = await evolveHarnessStrategy(cwd, `make this cheaper ${suffix}`, "best");
          expect(cheap.harness.executionPriority).toBe("cheap");

          const fast = await evolveHarnessStrategy(cwd, `make this fast ${suffix}`, "best");
          expect(fast.harness.executionPriority).toBe("fast");

          const review = await evolveHarnessStrategy(cwd, `please review this deeply ${suffix}`, "best");
          expect(review.harness.strategyType).toBe("cot");
          expect(review.harness.preferTools).toBe(true);
          expect(review.harness.demoSelection).toBe("similar");
        } finally {
          await rm(cwd, { recursive: true, force: true });
        }
      }),
      { numRuns: 12 }
    );
  });

  test("planning auto-triggers evolution without a manual command", async () => {
    const previousKey = process.env.OPENAI_API_KEY;
    delete process.env.OPENAI_API_KEY;

    await fc.assert(
      fc.asyncProperty(
        fc.array(fc.constantFrom("migrate", "terminal", "refactor", "pi", "runtime", "prompt", "flow"), {
          minLength: 2,
          maxLength: 7
        }),
        async (words) => {
          const cwd = await mkdtemp(join(tmpdir(), "chrysalis-pi-plan-"));
          try {
            const task = words.join(" ");
            const artifact = await writeTaskPlanArtifact(cwd, task);
            const contents = await readFile(artifact.planPath, "utf8");
            expect(contents).toContain(task.split(" ")[0]);
            expect(contents).toContain("## Harness");

            const state = await loadEvolutionState(cwd);
            expect(state.autonomousRuns).toBeGreaterThanOrEqual(1);
            expect(state.lastAutonomousRunAt).toBeTruthy();
            expect(state.harness.executionPriority).toMatch(/fast|cheap|best|verbose/);
          } finally {
            await rm(cwd, { recursive: true, force: true });
          }
        }
      ),
      { numRuns: 10 }
    );

    if (previousKey) process.env.OPENAI_API_KEY = previousKey;
  });
});
