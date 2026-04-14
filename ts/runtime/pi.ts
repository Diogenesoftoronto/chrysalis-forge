import { existsSync, readFileSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, spawnSync } from "node:child_process";

import { loadConfig, mergePiDefaults } from "../core/config.js";
import { evolutionSystemPromptPath } from "../core/paths.js";
import { ensureProjectScaffold } from "../core/project.js";
import { sessionsDir } from "../core/paths.js";
import { BUNDLED_APP_VERSION, BUNDLED_FILES } from "./bundled-assets.generated.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

export interface PiRuntimeDetails {
  kind: "standalone" | "bundled";
  command: string;
  cliPath?: string;
}

export interface PiRuntimeReport {
  selected: PiRuntimeDetails | null;
  standalone: PiRuntimeDetails | null;
  embedded: PiRuntimeDetails | null;
}

interface ResourceLayout {
  packageDir?: string;
  extensionPath: string;
  promptDir: string;
  skillsDir: string;
  systemPromptPath: string;
}

const isBunBinary =
  import.meta.url.includes("$bunfs") ||
  import.meta.url.includes("~BUN") ||
  import.meta.url.includes("%7EBUN");

function sourcePackageRoot(): string {
  return join(__dirname, "..", "..", "..");
}

async function ensureBundledPackageDir(): Promise<string> {
  const baseRoot =
    process.env.CHRYSALIS_BUNDLED_DIR ??
    (process.platform === "win32"
      ? join(tmpdir(), "chrysalis-bundled")
      : join(homedir(), ".chrysalis", "bundled"));
  const packageDir = join(baseRoot, BUNDLED_APP_VERSION);
  await mkdir(packageDir, { recursive: true });
  for (const file of BUNDLED_FILES) {
    const targetPath = join(packageDir, file.path);
    await mkdir(dirname(targetPath), { recursive: true });
    const payload = file.encoding === "base64" ? Buffer.from(file.content, "base64") : file.content;
    await writeFile(targetPath, payload);
  }
  return packageDir;
}

async function resolveResourceLayout(cwd: string): Promise<ResourceLayout> {
  if (isBunBinary) {
    const packageDir = await ensureBundledPackageDir();
    const evolvedSystemPrompt = evolutionSystemPromptPath(cwd);
    process.env.PI_PACKAGE_DIR = packageDir;
    return {
      packageDir,
      extensionPath: join(packageDir, "ts", "pi", "chrysalis-extension.js"),
      promptDir: join(packageDir, "pi", "prompts"),
      skillsDir: join(packageDir, "pi", "skills"),
      systemPromptPath: existsSync(evolvedSystemPrompt) ? evolvedSystemPrompt : join(packageDir, "SYSTEM.md")
    };
  }

  const root = sourcePackageRoot();
  const evolvedSystemPrompt = evolutionSystemPromptPath(cwd);
  return {
    packageDir: root,
    extensionPath: join(root, "dist", "ts", "pi", "chrysalis-extension.js"),
    promptDir: join(root, "pi", "prompts"),
    skillsDir: join(root, "pi", "skills"),
    systemPromptPath: existsSync(evolvedSystemPrompt) ? evolvedSystemPrompt : join(root, "SYSTEM.md")
  };
}

function resolveStandalonePi(): PiRuntimeDetails | null {
  const result = spawnSync("which", ["pi"], { encoding: "utf8" });
  if (result.status === 0 && result.stdout.trim()) {
    return {
      kind: "standalone",
      command: result.stdout.trim()
    };
  }
  return null;
}

function resolveBundledPi(): PiRuntimeDetails {
  return {
    kind: "bundled",
    command: "bundled-sdk"
  };
}

export async function detectPiRuntime(cwd: string): Promise<PiRuntimeReport> {
  const config = await loadConfig(cwd);
  const standalone = resolveStandalonePi();
  const embedded = resolveBundledPi();
  let selected: PiRuntimeDetails | null = null;

  switch (config.pi.runtimePreference) {
    case "standalone-only":
      selected = standalone;
      break;
    case "prefer-standalone":
      selected = standalone ?? embedded;
      break;
    case "prefer-embedded":
      selected = embedded ?? standalone;
      break;
    case "embedded-only":
    default:
      selected = embedded;
      break;
  }

  return { selected, standalone, embedded };
}

export async function launchPi(cwd: string, args: string[]): Promise<number> {
  await ensureProjectScaffold(cwd);
  const config = await loadConfig(cwd);
  const runtime = await detectPiRuntime(cwd);
  if (!runtime.selected) {
    throw new Error("No Pi runtime found. Install dependencies with `bun install` or install `pi` separately.");
  }

  const resources = await resolveResourceLayout(cwd);
  if (!existsSync(resources.extensionPath)) {
    throw new Error(`Missing built extension: ${resources.extensionPath}. Run \`bun run build\` first.`);
  }

  const sharedArgs = mergePiDefaults(config, [
    "--session-dir",
    sessionsDir(cwd, config.artifacts.root),
    "--extension",
    resources.extensionPath,
    "--prompt-template",
    resources.promptDir,
    "--skill",
    resources.skillsDir,
    "--append-system-prompt",
    readFileSync(resources.systemPromptPath, "utf8"),
    "--tools",
    config.pi.tools.join(","),
    ...args
  ]);

  const child =
    runtime.selected.kind === "standalone"
      ? spawn(runtime.selected.command, sharedArgs, { cwd, stdio: "inherit", env: process.env })
      : null;

  if (child) {
    return await new Promise<number>((resolvePromise, reject) => {
      child.on("error", reject);
      child.on("exit", (code) => resolvePromise(code ?? 0));
    });
  }

  const previousCwd = process.cwd();
  try {
    if (previousCwd !== cwd) process.chdir(cwd);
    const { main } = await import("@mariozechner/pi-coding-agent");
    await main(sharedArgs);
    return 0;
  } finally {
    if (process.cwd() !== previousCwd) process.chdir(previousCwd);
  }
}
