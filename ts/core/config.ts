import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { type ChrysalisConfig, type ChrysalisProfile, type PiRuntimePreference } from "./types.js";

export const DEFAULT_CONFIG: ChrysalisConfig = {
  pi: {
    runtimePreference: "prefer-embedded",
    defaultProvider: "openai",
    defaultModel: "gpt-5.4",
    defaultThinking: "medium",
    tools: ["read", "bash", "edit", "write", "grep", "find", "ls"]
  },
  profiles: {
    default: "best"
  },
  artifacts: {
    root: ".chrysalis"
  }
};

export function configPath(cwd: string): string {
  return resolve(cwd, "chrysalis.config.json");
}

function sanitizeRuntimePreference(value: unknown): PiRuntimePreference {
  switch (value) {
    case "embedded-only":
    case "prefer-embedded":
    case "standalone-only":
    case "prefer-standalone":
      return value;
    default:
      return DEFAULT_CONFIG.pi.runtimePreference;
  }
}

function sanitizeProfile(value: unknown): ChrysalisProfile {
  switch (value) {
    case "fast":
    case "cheap":
    case "best":
    case "verbose":
      return value;
    default:
      return DEFAULT_CONFIG.profiles.default;
  }
}

function sanitizeString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function sanitizeTools(value: unknown): string[] {
  if (!Array.isArray(value)) return [...DEFAULT_CONFIG.pi.tools];
  const tools = value.filter((entry): entry is string => typeof entry === "string" && entry.trim().length > 0);
  return tools.length > 0 ? tools : [...DEFAULT_CONFIG.pi.tools];
}

export async function loadConfig(cwd: string): Promise<ChrysalisConfig> {
  try {
    const raw = JSON.parse(await readFile(configPath(cwd), "utf8")) as Partial<ChrysalisConfig>;
    return {
      pi: {
        runtimePreference: sanitizeRuntimePreference(raw.pi?.runtimePreference),
        defaultProvider: sanitizeString(raw.pi?.defaultProvider) ?? DEFAULT_CONFIG.pi.defaultProvider,
        defaultModel: sanitizeString(raw.pi?.defaultModel) ?? DEFAULT_CONFIG.pi.defaultModel,
        defaultThinking: sanitizeString(raw.pi?.defaultThinking) ?? DEFAULT_CONFIG.pi.defaultThinking,
        tools: sanitizeTools(raw.pi?.tools)
      },
      profiles: {
        default: sanitizeProfile(raw.profiles?.default)
      },
      artifacts: {
        root: sanitizeString(raw.artifacts?.root) ?? DEFAULT_CONFIG.artifacts.root
      }
    };
  } catch {
    return DEFAULT_CONFIG;
  }
}

export async function ensureConfig(cwd: string): Promise<void> {
  const path = configPath(cwd);
  if (!existsSync(path)) {
    await writeFile(path, `${JSON.stringify(DEFAULT_CONFIG, null, 2)}\n`, "utf8");
  }
}

export function mergePiDefaults(config: ChrysalisConfig, args: string[]): string[] {
  const merged = [...args];
  if (!merged.includes("--provider") && config.pi.defaultProvider) {
    merged.unshift(config.pi.defaultProvider);
    merged.unshift("--provider");
  }
  if (!merged.includes("--model") && config.pi.defaultModel) {
    merged.unshift(config.pi.defaultModel);
    merged.unshift("--model");
  }
  if (!merged.includes("--thinking") && config.pi.defaultThinking) {
    merged.unshift(config.pi.defaultThinking);
    merged.unshift("--thinking");
  }
  return merged;
}
