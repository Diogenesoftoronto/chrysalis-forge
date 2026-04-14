import { describe, expect, test } from "bun:test";

import {
  tallyVotes,
  decorrelatePrompt,
  selectStakes,
  STAKES_PRESETS,
  executeWithVoting
} from "../ts/core/decomp-voter.js";

describe("decomp-voter", () => {
  test("tallyVotes identifies consensus", () => {
    const config = STAKES_PRESETS["MEDIUM"];
    const result = tallyVotes(
      ["use approach A", "use approach A", "use approach A", "use approach B", "use approach A"],
      config
    );
    expect(result.consensus).toBe(true);
    expect(result.winner).toBe("use approach A");
    expect(result.margin).toBeGreaterThanOrEqual(1);
  });

  test("tallyVotes with fuzzy matching groups similar responses", () => {
    const config = STAKES_PRESETS["LOW"];
    const result = tallyVotes(
      ["refactor the module completely", "refactor the module fully", "do something different"],
      config
    );
    expect(result.tally.size).toBeLessThanOrEqual(2);
  });

  test("tallyVotes no consensus when threshold not met", () => {
    const config = { nVoters: 5, kThreshold: 4, timeoutMs: 5000, decorrelate: false };
    const result = tallyVotes(["A", "A", "A", "B", "C"], config);
    expect(result.consensus).toBe(false);
  });

  test("decorrelatePrompt varies style hints", () => {
    const p0 = decorrelatePrompt("task", 0, 3);
    const p1 = decorrelatePrompt("task", 1, 3);
    expect(p0).toContain("voter 1 of 3");
    expect(p1).toContain("voter 2 of 3");
    expect(p0).not.toBe(p1);
  });

  test("selectStakes maps task keywords to presets", () => {
    expect(selectStakes("deploy to production")).toBe("CRITICAL");
    expect(selectStakes("audit the codebase")).toBe("HIGH");
    expect(selectStakes("refactor the module")).toBe("MEDIUM");
    expect(selectStakes("verify the test output")).toBe("LOW");
    expect(selectStakes("write a simple script")).toBe("NONE");
  });

  test("executeWithVoting with NONE stakes returns single result", async () => {
    const result = await executeWithVoting("simple task", async (prompt) => `result: ${prompt}`);
    expect(result.consensus).toBe(true);
    expect(result.winner).toContain("result:");
    expect(result.votes.length).toBe(1);
  });

  test("executeWithVoting runs multiple voters and tallies", async () => {
    const config = { nVoters: 3, kThreshold: 2, timeoutMs: 5000, decorrelate: false };
    let callCount = 0;
    const result = await executeWithVoting(
      "review the code",
      async (_prompt) => {
        callCount++;
        return "looks good";
      },
      config
    );
    expect(callCount).toBe(3);
    expect(result.consensus).toBe(true);
    expect(result.winner).toBe("looks good");
  });

  test("executeWithVoting handles voter failures gracefully", async () => {
    const config = { nVoters: 3, kThreshold: 2, timeoutMs: 5000, decorrelate: false };
    let callCount = 0;
    const result = await executeWithVoting(
      "test task",
      async () => {
        callCount++;
        if (callCount === 2) throw new Error("voter 2 failed");
        return "same answer";
      },
      config
    );
    expect(result.votes.length).toBe(2);
    expect(result.winner).toBe("same answer");
  });
});
