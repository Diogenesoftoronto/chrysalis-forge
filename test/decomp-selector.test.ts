import { describe, expect, test } from "bun:test";

import {
  priorityToPhenotype,
  computeDecompPhenotype,
  binKeyForDecomp,
  selectPatternForPhenotype
} from "../ts/core/decomp-selector.js";
import { type DecompositionArchive, type DecompPhenotype, type DecompositionPattern } from "../ts/core/types.js";

describe("decomp-selector", () => {
  test("priorityToPhenotype returns known phenotypes", () => {
    const fast = priorityToPhenotype("fast");
    expect(fast.depth).toBe(1);
    expect(fast.parallelism).toBe(3);

    const best = priorityToPhenotype("best");
    expect(best.depth).toBe(3);
    expect(best.toolDiversity).toBe(4);
  });

  test("computeDecompPhenotype derives from pattern", () => {
    const pattern: DecompositionPattern = {
      id: "p1",
      name: "test",
      steps: [
        { id: "s0", description: "read", toolHints: ["researcher"], dependencies: [] },
        { id: "s1", description: "write", toolHints: ["editor"], dependencies: [0] },
        { id: "s2", description: "verify", toolHints: ["all"], dependencies: [1] }
      ],
      metadata: {}
    };
    const pheno = computeDecompPhenotype(pattern);
    expect(pheno.complexity).toBe(3);
    expect(pheno.toolDiversity).toBe(3);
    expect(pheno.depth).toBe(2);
  });

  test("binKeyForDecomp classifies phenotypes", () => {
    const shallow: DecompPhenotype = { depth: 1, parallelism: 0, toolDiversity: 1, complexity: 2 };
    expect(binKeyForDecomp(shallow)).toBe("shallow:serial:mono");

    const deep: DecompPhenotype = { depth: 3, parallelism: 3, toolDiversity: 4, complexity: 5 };
    expect(binKeyForDecomp(deep)).toBe("deep:parallel:diverse");
  });

  test("selectPatternForPhenotype returns null for empty archive", () => {
    const empty: DecompositionArchive = { taskType: "general", archive: {}, pointCloud: [], defaultId: null };
    const result = selectPatternForPhenotype(empty, { depth: 1, parallelism: 1, toolDiversity: 1, complexity: 1 });
    expect(result).toBeNull();
  });

  test("selectPatternForPhenotype picks nearest pattern", () => {
    const pattern1: DecompositionPattern = {
      id: "p1", name: "far", steps: [
        { id: "s0", description: "a", toolHints: ["editor"], dependencies: [] }
      ], metadata: {}
    };
    const pattern2: DecompositionPattern = {
      id: "p2", name: "near", steps: [
        { id: "s0", description: "b", toolHints: ["researcher"], dependencies: [] },
        { id: "s1", description: "c", toolHints: ["editor"], dependencies: [] }
      ], metadata: {}
    };
    const archive: DecompositionArchive = {
      taskType: "general",
      archive: {
        "e1": { score: 5, pattern: pattern1 },
        "e2": { score: 8, pattern: pattern2 }
      },
      pointCloud: [
        { phenotype: computeDecompPhenotype(pattern1), pattern: pattern1 },
        { phenotype: computeDecompPhenotype(pattern2), pattern: pattern2 }
      ],
      defaultId: "e2"
    };
    const target: DecompPhenotype = { depth: 2, parallelism: 1, toolDiversity: 2, complexity: 2 };
    const selected = selectPatternForPhenotype(archive, target);
    expect(selected).not.toBeNull();
    expect(selected!.steps.length).toBe(2);
  });
});
