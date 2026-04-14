import { existsSync } from "node:fs";
import { readFile, readdir, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { createTaskPlan } from "./ax.js";
import { evolveHarnessStrategy, runAutonomousEvolution } from "./evolution.js";
import { ensureEvolutionBootstrap } from "./evolution.js";
import { DEFAULT_CONFIG, ensureConfig, loadConfig } from "./config.js";
import { ensureChrysalisDirs, outputsDir, plansDir, profilePath } from "./paths.js";
import { slugify } from "./util.js";
import { type ChrysalisProfile, type ProfileState, type TaskPlan } from "./types.js";

export async function ensureProjectScaffold(cwd: string): Promise<void> {
  const config = await loadConfig(cwd).catch(() => DEFAULT_CONFIG);
  await ensureChrysalisDirs(cwd, config.artifacts.root);
  await ensureConfig(cwd);
  await loadProfileState(cwd);
  await ensureEvolutionBootstrap(cwd);
}

export async function loadProfileState(cwd: string): Promise<ProfileState> {
  const config = await loadConfig(cwd);
  await ensureChrysalisDirs(cwd, config.artifacts.root);
  await ensureConfig(cwd);
  const path = profilePath(cwd, config.artifacts.root);
  try {
    const parsed = JSON.parse(await readFile(path, "utf8")) as ProfileState;
    if (parsed.activeProfile) return parsed;
  } catch {}

  const fallback: ProfileState = {
    activeProfile: config.profiles.default,
    updatedAt: new Date().toISOString(),
    reason: "initialized from configuration defaults"
  };
  await writeFile(path, `${JSON.stringify(fallback, null, 2)}\n`, "utf8");
  return fallback;
}

export async function saveProfileState(cwd: string, activeProfile: ChrysalisProfile, reason: string): Promise<ProfileState> {
  const config = await loadConfig(cwd);
  await ensureChrysalisDirs(cwd, config.artifacts.root);
  await ensureConfig(cwd);
  const state: ProfileState = {
    activeProfile,
    updatedAt: new Date().toISOString(),
    reason
  };
  await writeFile(profilePath(cwd, config.artifacts.root), `${JSON.stringify(state, null, 2)}\n`, "utf8");
  return state;
}

function planToMarkdown(task: string, plan: TaskPlan): string {
  const sections = [
    `# ${task}`,
    "",
    `- mode: ${plan.mode}`,
    `- task_type: ${plan.taskType}`,
    `- recommended_profile: ${plan.recommendedProfile}`,
    "",
    "## Summary",
    "",
    plan.summary,
    "",
    "## Deliverables",
    "",
    ...plan.deliverables.map((item) => `- ${item}`),
    "",
    "## Risks",
    "",
    ...plan.risks.map((item) => `- ${item}`),
    "",
    "## First Steps",
    "",
    ...plan.firstSteps.map((item) => `- ${item}`),
    ""
  ];

  if (plan.harness) {
    sections.push(
      "## Harness",
      "",
      `- executionPriority: ${plan.harness.executionPriority}`,
      `- strategyType: ${plan.harness.strategyType}`,
      `- contextBudget: ${plan.harness.contextBudget.toFixed(2)}`,
      `- compactionThreshold: ${plan.harness.compactionThreshold.toFixed(2)}`,
      `- demoSelection: ${plan.harness.demoSelection}`,
      `- mutationRate: ${plan.harness.mutationRate.toFixed(2)}`,
      ""
    );
  }

  return sections.join("\n");
}

export async function writeTaskPlanArtifact(cwd: string, task: string): Promise<{ planPath: string; plan: TaskPlan }> {
  await ensureProjectScaffold(cwd);
  const config = await loadConfig(cwd);
  const profile = await loadProfileState(cwd);
  const plan = await createTaskPlan(task, cwd, profile.activeProfile);
  const harnessResult = await evolveHarnessStrategy(cwd, task, profile.activeProfile);
  const enrichedPlan: TaskPlan = {
    ...plan,
    harness: harnessResult.harness
  };
  const planPath = join(plansDir(cwd, config.artifacts.root), `${slugify(task)}.md`);
  await writeFile(planPath, planToMarkdown(task, enrichedPlan), "utf8");
  await runAutonomousEvolution(cwd, {
    kind: "task_plan",
    task,
    taskType: plan.taskType,
    profile: profile.activeProfile,
    planSummary: plan.summary
  });
  return { planPath, plan: enrichedPlan };
}

export async function listArtifacts(cwd: string): Promise<Array<{ label: string; path: string }>> {
  await ensureProjectScaffold(cwd);
  const config = await loadConfig(cwd);
  const root = outputsDir(cwd, config.artifacts.root);
  const artifacts: Array<{ label: string; path: string; mtime: number }> = [];

  async function walk(dir: string): Promise<void> {
    const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);
    for (const entry of entries) {
      const fullPath = join(dir, entry.name);
      if (entry.isDirectory()) {
        await walk(fullPath);
      } else if (entry.isFile()) {
        const info = await stat(fullPath);
        artifacts.push({
          label: fullPath.replace(`${cwd}/`, ""),
          path: fullPath,
          mtime: info.mtimeMs
        });
      }
    }
  }

  if (existsSync(root)) await walk(root);
  return artifacts.sort((left, right) => right.mtime - left.mtime).map(({ label, path }) => ({ label, path }));
}
