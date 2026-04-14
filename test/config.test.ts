import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { ensureConfig, loadConfig, mergePiDefaults } from "../ts/core/config.js";

describe("config", () => {
  test("ensureConfig writes defaults and mergePiDefaults injects runtime flags", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-config-"));
    try {
      await ensureConfig(cwd);
      const config = await loadConfig(cwd);
      expect(config.pi.runtimePreference).toBe("prefer-embedded");
      expect(mergePiDefaults(config, ["--tools", "read"]).slice(0, 6)).toEqual([
        "--thinking",
        "medium",
        "--model",
        "gpt-5.4",
        "--provider",
        "openai"
      ]);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
