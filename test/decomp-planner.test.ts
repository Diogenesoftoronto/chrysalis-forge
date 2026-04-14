import { describe, expect, test } from "bun:test";

import {
  classifyTask,
  heuristicDecomposition,
  suggestProfileForSubtask,
  shouldVote
} from "../ts/core/decomp-planner.js";

describe("decomp-planner", () => {
  test("classifyTask maps keywords to types", () => {
    expect(classifyTask("refactor the authentication module")).toBe("refactor");
    expect(classifyTask("implement a new API endpoint")).toBe("implement");
    expect(classifyTask("debug the login error")).toBe("debug");
    expect(classifyTask("find all uses of deprecated function")).toBe("research");
    expect(classifyTask("test the parser thoroughly")).toBe("test");
    expect(classifyTask("document the REST API")).toBe("document");
    expect(classifyTask("do something random")).toBe("general");
  });

  test("heuristicDecomposition produces structured subtasks", () => {
    const steps = heuristicDecomposition("implement user login", 4);
    expect(steps.length).toBeGreaterThanOrEqual(3);
    expect(steps[0].profileHint).toBe("researcher");
    expect(steps[0].dependencies).toEqual([]);

    const debugSteps = heuristicDecomposition("fix the null pointer bug", 4);
    expect(debugSteps.length).toBeGreaterThanOrEqual(3);

    const researchSteps = heuristicDecomposition("find the root cause", 4);
    expect(researchSteps.length).toBe(2);
    expect(researchSteps[0].profileHint).toBe("researcher");
  });

  test("suggestProfileForSubtask returns correct profiles", () => {
    expect(suggestProfileForSubtask("read the current code")).toBe("researcher");
    expect(suggestProfileForSubtask("write the implementation")).toBe("editor");
    expect(suggestProfileForSubtask("commit the changes")).toBe("vcs");
    expect(suggestProfileForSubtask("do something else")).toBe("all");
  });

  test("shouldVote detects review/audit tasks", () => {
    expect(shouldVote("review the code changes")).toBe(true);
    expect(shouldVote("audit the security model")).toBe(true);
    expect(shouldVote("validate the test results")).toBe(true);
    expect(shouldVote("implement a new feature")).toBe(false);
    expect(shouldVote("write a function")).toBe(false);
  });
});
