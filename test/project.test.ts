import { describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { loadEvolutionState } from "../ts/core/evolution.js";
import { loadProfileState, saveProfileState, writeTaskPlanArtifact } from "../ts/core/project.js";

describe("project scaffold", () => {
  test("profile state persists and plan artifacts are written", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-project-"));
    const previousKey = process.env.OPENAI_API_KEY;
    delete process.env.OPENAI_API_KEY;

    try {
      const initial = await loadProfileState(cwd);
      expect(initial.activeProfile).toBe("best");

      const updated = await saveProfileState(cwd, "fast", "matched speed-oriented language");
      expect(updated.activeProfile).toBe("fast");

      const artifact = await writeTaskPlanArtifact(cwd, "migrate the terminal flow to pi");
      const contents = await readFile(artifact.planPath, "utf8");
      expect(contents).toContain("recommended_profile");
      expect(contents).toContain("migration");
      expect(artifact.plan.mode).toBe("heuristic");

      const evolution = await loadEvolutionState(cwd);
      expect(evolution.autonomousRuns).toBeGreaterThanOrEqual(1);
      expect(evolution.lastAutonomousRunAt).toBeTruthy();
    } finally {
      if (previousKey) process.env.OPENAI_API_KEY = previousKey;
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
