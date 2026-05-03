import { relative } from "node:path";
import { homedir } from "node:os";

import {
  evolveHarnessStrategy,
  evolveMetaPrompt,
  evolveSystemPrompt,
  loadEvolutionArchive,
  loadEvolutionState,
  runAutonomousEvolution,
  summarizeEvolutionState,
  suggestProfileFromStats
} from "../core/evolution.js";
import { listArtifacts, loadProfileState, saveProfileState, writeTaskPlanArtifact } from "../core/project.js";
import { evolutionMetaPromptPath, evolutionSystemPromptPath } from "../core/paths.js";
import { interpretProfilePhrase } from "../core/priority.js";
import { getSessionStatsDisplay, loadSessionStats } from "../core/stores/session-stats.js";
import { sessionList, sessionSwitch } from "../core/stores/context-store.js";
import { threadList, threadSwitch } from "../core/stores/thread-store.js";
import { fileRollback } from "../core/stores/rollback-store.js";
import { cacheStats } from "../core/stores/cache-store.js";
import { executeRdfTool } from "../core/tools/rdf-tools.js";
import { classifyTask, runDecomposition } from "../core/decomp-planner.js";
import { storeCreate, storeDelete, storeList, storeGet, storeSet, storeRemove, storeDump, storeDescribe } from "../core/stores/store-registry.js";
import { EVOLUTION_TOOL_DEFINITIONS, executeEvolutionTool } from "../core/tools/evolution-tools.js";
import { GIT_TOOL_DEFINITIONS, executeGitTool } from "../core/tools/git-tools.js";
import { JJ_TOOL_DEFINITIONS, executeJjTool } from "../core/tools/jj-tools.js";
import { WEB_TOOL_DEFINITIONS, executeWebTool } from "../core/tools/web-tools.js";
import { SUB_AGENT_TOOL_DEFINITIONS, executeSubAgentTool } from "../core/tools/sub-agent-tools.js";
import { STORE_TOOL_DEFINITIONS, executeStoreTool } from "../core/tools/store-tools.js";
import { ROLLBACK_TOOL_DEFINITIONS, executeRollbackTool } from "../core/tools/rollback-tools.js";
import { CACHE_TOOL_DEFINITIONS, executeCacheTool } from "../core/tools/cache-tools.js";
import { DECOMP_TOOL_DEFINITIONS, executeDecompTool } from "../core/tools/decomp-tools.js";
import { RDF_TOOL_DEFINITIONS } from "../core/tools/rdf-tools.js";
import { JUDGE_TOOL_DEFINITIONS, executeJudgeTool } from "../core/tools/judge-tools.js";
import { TEST_TOOL_DEFINITIONS, executeTestTool } from "../core/tools/test-tools.js";
import { PRIORITY_TOOL_DEFINITIONS, executePriorityTool } from "../core/tools/priority-tools.js";
import { EVOLVER_TOOL_DEFINITIONS, executeEvolverTool } from "../core/tools/evolver-tools.js";
import { globalToolRegistry } from "../core/tools/tool-registry.js";
import { listToolVariants } from "../core/tools/tool-evolution.js";

const CHRYSALIS_VERSION = "0.4.0";
const ANSI_RE = /\x1b\[[0-9;]*[a-zA-Z]/g;

const CHRYSALIS_ASCII_LOGO = [
  "   ________                         __          ___     ",
  "  / ____/ /_  _______  _________ _/ /_  ____ _/ (_)____",
  " / /   / __ \\/ ___/ / / / ___/ __ `/ / / / / / / / ___/",
  "/ /___/ / / / /  / /_/ (__  ) /_/ / /_/ / /_/ / (__  ) ",
  "\\____/_/ /_/_/   \\__, /____/\\__,_/\\__, /\\__, /_/____/  ",
  "                /____/           /____//____/           "
];

const CHRYSALIS_SUBTITLE_LINES = [
  "Self-evolving terminal coding agent",
  "Plan, decompose, store context, roll back, and evolve the harness."
];

const CHRYSALIS_COMMAND_SECTIONS = [
  {
    title: "Planning",
    commands: [
      { usage: "/plan <task>", description: "Generate a task plan artifact." },
      { usage: "/decomp <task>", description: "Decompose work into dependency-aware subtasks." },
      { usage: "/profile [text]", description: "Show or set the active execution profile." },
      { usage: "/outputs", description: "Browse generated Chrysalis artifacts." }
    ]
  },
  {
    title: "Evolution",
    commands: [
      { usage: "/evolve <feedback>", description: "Evolve the active system prompt." },
      { usage: "/meta-evolve <feedback>", description: "Evolve the optimizer meta-prompt." },
      { usage: "/harness <feedback>", description: "Mutate the harness strategy." },
      { usage: "/evolve-tool <name> <feedback>", description: "Evolve a tool definition." },
      { usage: "/archive", description: "Inspect archived variants." },
      { usage: "/stats", description: "Show evolution and profile-learning statistics." }
    ]
  },
  {
    title: "Memory",
    commands: [
      { usage: "/sessions [name]", description: "List sessions or switch to one by name." },
      { usage: "/threads [id]", description: "List threads or switch to one by ID." },
      { usage: "/stores [subcommand] ...", description: "List or manage dynamic key/value, log, set, and counter stores." }
    ]
  },
  {
    title: "Recovery",
    commands: [
      { usage: "/rollback <path>", description: "Restore a file from backup history." },
      { usage: "/cache-stats", description: "Show web cache statistics." },
      { usage: "/rdf-load", description: "Load triples into the RDF graph." },
      { usage: "/rdf-query <query>", description: "Query RDF knowledge." },
      { usage: "/rdf-insert ...", description: "Insert a triple into the RDF store." }
    ]
  }
];

function visibleWidth(text: string): number {
  return text.replace(ANSI_RE, "").length;
}

function padVisible(text: string, width: number): string {
  const vw = visibleWidth(text);
  return vw >= width ? text : text + " ".repeat(width - vw);
}

function truncatePlain(text: string, width: number): string {
  if (text.length <= width) return text;
  if (width <= 1) return text.slice(0, Math.max(0, width));
  return `${text.slice(0, width - 1)}…`;
}

function centerPlain(text: string, width: number): string {
  const truncated = truncatePlain(text, width);
  const gap = Math.max(0, width - truncated.length);
  const left = Math.floor(gap / 2);
  return `${" ".repeat(left)}${truncated}${" ".repeat(gap - left)}`;
}

function wrapWords(text: string, maxWidth: number): string[] {
  const width = Math.max(1, maxWidth);
  const words = text.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let current = "";

  for (const raw of words) {
    const word = truncatePlain(raw, width);
    const next = current ? `${current} ${word}` : word;
    if (current && next.length > width) {
      lines.push(current);
      current = word;
    } else {
      current = next;
    }
  }

  if (current) lines.push(current);
  return lines.length > 0 ? lines : [""];
}

function formatHeaderPath(path: string): string {
  const home = homedir();
  return path.startsWith(home) ? `~${path.slice(home.length)}` : path;
}

function getCurrentModelLabel(ctx: any): string {
  if (typeof ctx?.model === "string" && ctx.model.trim()) return ctx.model.trim();
  if (ctx?.model?.provider && ctx?.model?.id) return `${ctx.model.provider}/${ctx.model.id}`;

  const branch = ctx?.sessionManager?.getBranch?.();
  if (Array.isArray(branch)) {
    for (let index = branch.length - 1; index >= 0; index -= 1) {
      const entry = branch[index];
      if (entry?.type === "model_change" && entry.provider && entry.modelId) {
        return `${entry.provider}/${entry.modelId}`;
      }
    }
  }

  return "not set";
}

function getSessionLabel(ctx: any): string {
  const manager = ctx?.sessionManager;
  return manager?.getSessionName?.()?.trim() || manager?.getSessionId?.() || "new session";
}

function summarizeLastActivity(ctx: any): string {
  const branch = ctx?.sessionManager?.getBranch?.();
  if (!Array.isArray(branch)) return "";

  for (let index = branch.length - 1; index >= 0; index -= 1) {
    const entry = branch[index];
    if (entry?.type !== "message") continue;
    const message = entry.message;
    const role = message?.role === "assistant" ? "agent" : message?.role === "user" ? "you" : message?.role;
    const content = message?.content;
    const text = typeof content === "string"
      ? content
      : Array.isArray(content)
        ? content.map((item: any) => item?.text ?? (item?.name ? `[${item.name}]` : "")).filter(Boolean).join(" ")
        : "";
    const compact = text.replace(/\s+/g, " ").trim();
    if (compact) return `${role ?? "message"}: ${compact}`;
  }

  return "";
}

function notify(ctx: any, message: string): void {
  ctx.ui.notify(message, "info");
}

function textFromArgs(args: string | string[]): string {
  return (Array.isArray(args) ? args.join(" ") : String(args ?? "")).trim();
}

const ALL_TOOL_GROUPS: Array<{
  definitions: Array<{ name: string; description: string; parameters: any }>;
  execute: (cwd: string, name: string, args: Record<string, unknown>) => Promise<string>;
}> = [
  { definitions: EVOLUTION_TOOL_DEFINITIONS, execute: executeEvolutionTool },
  { definitions: GIT_TOOL_DEFINITIONS, execute: executeGitTool },
  { definitions: JJ_TOOL_DEFINITIONS, execute: executeJjTool },
  { definitions: WEB_TOOL_DEFINITIONS, execute: executeWebTool },
  { definitions: SUB_AGENT_TOOL_DEFINITIONS, execute: executeSubAgentTool },
  { definitions: STORE_TOOL_DEFINITIONS, execute: executeStoreTool },
  { definitions: ROLLBACK_TOOL_DEFINITIONS, execute: executeRollbackTool },
  { definitions: CACHE_TOOL_DEFINITIONS, execute: executeCacheTool },
  { definitions: RDF_TOOL_DEFINITIONS, execute: executeRdfTool },
  { definitions: DECOMP_TOOL_DEFINITIONS, execute: executeDecompTool },
  { definitions: JUDGE_TOOL_DEFINITIONS, execute: executeJudgeTool },
  { definitions: TEST_TOOL_DEFINITIONS, execute: executeTestTool },
  { definitions: PRIORITY_TOOL_DEFINITIONS, execute: executePriorityTool },
  { definitions: EVOLVER_TOOL_DEFINITIONS, execute: executeEvolverTool }
];

function registerToolGroup(pi: any, group: typeof ALL_TOOL_GROUPS[number]): void {
  for (const def of group.definitions) {
    const evolvedDef = globalToolRegistry.getActiveDefinition(def.name) ?? def;
    pi.registerTool({
      name: evolvedDef.name,
      label: evolvedDef.name.replace(/_/g, " "),
      description: evolvedDef.description,
      parameters: evolvedDef.parameters,
      async execute(_toolCallId: string, params: any, _signal: any, _onUpdate: any, ctx: any): Promise<{ content: Array<{ type: string; text: string }> }> {
        try {
          const result = await group.execute(ctx.cwd, def.name, params);
          return { content: [{ type: "text", text: result }] };
        } catch (err) {
          return { content: [{ type: "text", text: `Error: ${err instanceof Error ? err.message : String(err)}` }] };
        }
      }
    });
  }
}

function createChrysalisWelcomeComponent(pi: any, ctx: any, state: Awaited<ReturnType<typeof loadProfileState>>, evolution: Awaited<ReturnType<typeof loadEvolutionState>>): (tui: any, theme: any) => any {
  const registeredToolCount = ALL_TOOL_GROUPS.reduce((sum, group) => sum + group.definitions.length, 0);
  const commandCount = CHRYSALIS_COMMAND_SECTIONS.reduce((sum, section) => sum + section.commands.length, 0);
  const evolutionSummary = summarizeEvolutionState(evolution);

  return (_tui: any, theme: any): any => {
    const t = theme.fg.bind(theme);
    const b = theme.bold.bind(theme);
    const border = (text: string) => t("borderMuted", text);
    const dim = (text: string) => t("dim", text);
    const accent = (text: string) => t("accent", text);
    const heading = (text: string) => b(t("mdHeading", text));
    const text = (value: string) => t("text", value);

    return {
      render(width: number): string[] {
        const maxWidth = Math.max(width - 2, 1);
        const cardWidth = Math.min(maxWidth, 122);
        const innerWidth = Math.max(cardWidth - 2, 1);
        const contentWidth = Math.max(innerWidth - 2, 1);
        const outerPad = " ".repeat(Math.max(0, Math.floor((width - cardWidth) / 2)));
        const lines: string[] = [];
        const push = (line: string) => lines.push(`${outerPad}${line}`);
        const row = (content: string) => `${border("│")} ${padVisible(content, contentWidth)} ${border("│")}`;
        const emptyRow = () => `${border("│")}${" ".repeat(innerWidth)}${border("│")}`;
        const separator = () => `${border("├")}${border("─".repeat(innerWidth))}${border("┤")}`;
        const useWideLayout = contentWidth >= 74;

        push("");
        if (cardWidth >= 74) {
          const logoWidth = Math.max(...CHRYSALIS_ASCII_LOGO.map(line => line.length));
          const logoPad = " ".repeat(Math.max(0, Math.floor((cardWidth - logoWidth) / 2)));
          const palette = ["accent", "accent", "mdHeading", "mdHeading", "text", "text"];
          for (let index = 0; index < CHRYSALIS_ASCII_LOGO.length; index += 1) {
            push(b(t(palette[index] ?? "text", `${logoPad}${CHRYSALIS_ASCII_LOGO[index]}`)));
          }
          push("");
        }

        const versionTag = ` v${CHRYSALIS_VERSION} `;
        const versionGap = Math.max(0, innerWidth - versionTag.length);
        const versionLeft = Math.floor(versionGap / 2);
        push(
          border(`╭${"─".repeat(versionLeft)}`) +
            dim(versionTag) +
            border(`${"─".repeat(versionGap - versionLeft)}╮`),
        );

        if (useWideLayout) {
          const leftWidth = Math.min(40, Math.floor(contentWidth * 0.36));
          const dividerWidth = 3;
          const rightWidth = contentWidth - leftWidth - dividerWidth;
          const leftValueWidth = Math.max(1, leftWidth - 11);
          const commandNameWidth = 26;
          const commandDescWidth = Math.max(12, rightWidth - commandNameWidth - 2);
          const leftLines: string[] = [""];
          const rightLines: string[] = ["", heading("Chrysalis Workflows")];
          const leftLabel = (label: string, value: string, color: "text" | "dim") => {
            const wrapped = wrapWords(value, leftValueWidth);
            leftLines.push(`${dim(label.padEnd(10))} ${color === "text" ? text(wrapped[0]!) : dim(wrapped[0]!)}`);
            for (const line of wrapped.slice(1)) {
              leftLines.push(`${" ".repeat(11)}${color === "text" ? text(line) : dim(line)}`);
            }
          };
          const listBlock = (label: string, values: string[]) => {
            if (values.length === 0) return;
            leftLines.push("");
            leftLines.push(accent(b(label)));
            for (const value of values) {
              for (const line of wrapWords(value, leftWidth)) {
                leftLines.push(dim(line));
              }
            }
          };

          leftLabel("model", getCurrentModelLabel(ctx), "text");
          leftLabel("directory", formatHeaderPath(ctx.cwd), "text");
          leftLabel("session", getSessionLabel(ctx), "dim");
          leftLabel("profile", state.activeProfile, "text");
          leftLines.push("");
          leftLines.push(dim(`${pi.getAllTools?.().length ?? registeredToolCount} tools · ${commandCount} commands`));
          listBlock("Purpose", CHRYSALIS_SUBTITLE_LINES);
          listBlock("Evolution", evolutionSummary.slice(2, 6));
          listBlock("Last Activity", [truncatePlain(summarizeLastActivity(ctx), leftWidth * 2)].filter(Boolean));

          for (const section of CHRYSALIS_COMMAND_SECTIONS) {
            rightLines.push("");
            rightLines.push(accent(b(section.title)));
            for (const command of section.commands) {
              const wrapped = wrapWords(command.description, commandDescWidth);
              rightLines.push(`${accent(command.usage.padEnd(commandNameWidth))}${dim(wrapped[0]!)}`);
              for (const line of wrapped.slice(1)) {
                rightLines.push(`${" ".repeat(commandNameWidth)}${dim(line)}`);
              }
            }
          }

          const maxRows = Math.max(leftLines.length, rightLines.length);
          for (let index = 0; index < maxRows; index += 1) {
            push(row(
              `${padVisible(leftLines[index] ?? "", leftWidth)}` +
              `${border(" │ ")}` +
              `${padVisible(rightLines[index] ?? "", rightWidth)}`,
            ));
          }
        } else {
          push(emptyRow());
          push(row(heading(centerPlain(CHRYSALIS_SUBTITLE_LINES[0] ?? "Chrysalis", contentWidth))));
          push(row(dim(centerPlain(`profile: ${state.activeProfile}`, contentWidth))));
          push(row(dim(centerPlain(`${pi.getAllTools?.().length ?? registeredToolCount} tools · ${commandCount} commands`, contentWidth))));
          push(emptyRow());
          push(separator());
          for (const section of CHRYSALIS_COMMAND_SECTIONS) {
            push(row(accent(b(section.title))));
            for (const command of section.commands) {
              const descWidth = Math.max(1, contentWidth - 26);
              push(row(`${accent(command.usage.padEnd(25))}${dim(truncatePlain(command.description, descWidth))}`));
            }
          }
        }

        push(border(`╰${"─".repeat(innerWidth)}╯`));
        push("");
        return lines;
      },
      invalidate(): void {},
      dispose(): void {}
    };
  };
}

let welcomeShown = false;

export default function chrysalisExtension(pi: any): void {
  // Register all LLM-callable tools
  for (const group of ALL_TOOL_GROUPS) {
    registerToolGroup(pi, group);
  }

  // Slash commands (human-initiated, same as before)
  pi.registerCommand("plan", {
    description: "Generate a Chrysalis task plan artifact and open it in the editor.",
    handler: async (args: string[], ctx: any) => {
      const task = textFromArgs(args);
      if (!task) {
        notify(ctx, "Usage: /plan <task>");
        return;
      }
      const artifact = await writeTaskPlanArtifact(ctx.cwd, task);
      ctx.ui.setEditorText(`read ${relative(ctx.cwd, artifact.planPath)}`);
      notify(ctx, `Planned with ${artifact.plan.mode.toUpperCase()} and wrote ${relative(ctx.cwd, artifact.planPath)}`);
    }
  });

  pi.registerCommand("profile", {
    description: "Show or set the active Chrysalis execution profile.",
    handler: async (args: string[], ctx: any) => {
      const phrase = textFromArgs(args);
      if (!phrase) {
        const state = await loadProfileState(ctx.cwd);
        notify(ctx, `Current profile: ${state.activeProfile}`);
        return;
      }
      const next = interpretProfilePhrase(phrase);
      const state = await saveProfileState(ctx.cwd, next.profile, next.reason);
      notify(ctx, `Profile set to ${state.activeProfile}: ${next.reason}`);
    }
  });

  pi.registerCommand("outputs", {
    description: "Browse Chrysalis artifacts written under .chrysalis/outputs.",
    handler: async (_args: string[], ctx: any) => {
      const artifacts = await listArtifacts(ctx.cwd);
      if (artifacts.length === 0) {
        notify(ctx, "No artifacts yet. Use /plan first.");
        return;
      }
      const selected = await ctx.ui.select("Chrysalis Outputs", artifacts.map((artifact) => artifact.label));
      const artifact = artifacts.find((entry) => entry.label === selected);
      if (artifact) {
        ctx.ui.setEditorText(`read ${relative(ctx.cwd, artifact.path)}`);
      }
    }
  });

  pi.registerCommand("evolve", {
    description: "Evolve the active Chrysalis system prompt from feedback.",
    handler: async (args: string[], ctx: any) => {
      const feedback = textFromArgs(args);
      if (!feedback) {
        notify(ctx, "Usage: /evolve <feedback>");
        return;
      }
      const profile = (await loadProfileState(ctx.cwd)).activeProfile;
      const result = await evolveSystemPrompt(ctx.cwd, feedback, profile);
      notify(
        ctx,
        `System prompt evolved and saved to ${relative(ctx.cwd, evolutionSystemPromptPath(ctx.cwd))}${
          result.rejected ? " (low novelty)" : ""
        }.`
      );
    }
  });

  pi.registerCommand("meta-evolve", {
    description: "Evolve the optimizer meta-prompt from feedback.",
    handler: async (args: string[], ctx: any) => {
      const feedback = textFromArgs(args);
      if (!feedback) {
        notify(ctx, "Usage: /meta-evolve <feedback>");
        return;
      }
      const profile = (await loadProfileState(ctx.cwd)).activeProfile;
      await evolveMetaPrompt(ctx.cwd, feedback, profile);
      notify(ctx, `Meta prompt saved to ${relative(ctx.cwd, evolutionMetaPromptPath(ctx.cwd))}.`);
    }
  });

  pi.registerCommand("harness", {
    description: "Mutate the harness strategy from feedback.",
    handler: async (args: string[], ctx: any) => {
      const feedback = textFromArgs(args);
      if (!feedback) {
        notify(ctx, "Usage: /harness <feedback>");
        return;
      }
      const profile = (await loadProfileState(ctx.cwd)).activeProfile;
      const result = await evolveHarnessStrategy(ctx.cwd, feedback, profile);
      notify(ctx, `Harness updated: ${result.harness.executionPriority}/${result.harness.strategyType}`);
    }
  });

  pi.registerCommand("evolve-tool", {
    description: "Evolve a registered tool's definition from feedback.",
    handler: async (args: string[], ctx: any) => {
      const parts = (Array.isArray(args) ? args : String(args ?? "").split(/\s+/));
      const [toolName, ...feedbackParts] = parts;
      const feedback = feedbackParts.join(" ");
      if (!toolName || !feedback) {
        notify(ctx, "Usage: /evolve-tool <tool_name> <feedback>");
        return;
      }
      globalToolRegistry.setCwd(ctx.cwd);
      const result = await globalToolRegistry.evolveToolDefinition(toolName, feedback);
      if (!result.success) {
        notify(ctx, `Error: ${result.error}`);
        return;
      }
      notify(ctx, `Tool '${toolName}' evolved: variant=${result.variant?.id} novelty=${result.variant?.noveltyScore?.toFixed(2)} active=${result.variant?.active}`);
    }
  });

  pi.registerCommand("archive", {
    description: "List archived evolution variants.",
    handler: async (_args: string[], ctx: any) => {
      const archive = await loadEvolutionArchive(ctx.cwd);
      if (archive.length === 0) {
        notify(ctx, "No evolution archive entries yet.");
        return;
      }
      const selected = await ctx.ui.select(
        "Chrysalis Archive",
        archive.slice(0, 20).map((entry) => `${entry.family} ${entry.binKey} ${entry.id}`)
      );
      const entry = archive.find((candidate) => `${candidate.family} ${candidate.binKey} ${candidate.id}` === selected);
      if (entry) {
        ctx.ui.setEditorText(entry.content);
      }
    }
  });

  pi.registerCommand("stats", {
    description: "Show evolution and profile-learning statistics.",
    handler: async (_args: string[], ctx: any) => {
      const state = await loadEvolutionState(ctx.cwd);
      const { profile } = await suggestProfileFromStats(ctx.cwd, "build");
      for (const line of summarizeEvolutionState(state)) {
        notify(ctx, line);
      }
      notify(ctx, `suggested_profile=${profile}`);
    }
  });

  pi.registerCommand("sessions", {
    description: "List sessions or switch to one by name.",
    handler: async (args: string[], ctx: any) => {
      const name = textFromArgs(args);
      if (!name) {
        const { names, active } = await sessionList(ctx.cwd);
        if (names.length === 0) {
          notify(ctx, "No sessions yet.");
          return;
        }
        for (const n of names) {
          notify(ctx, `${n === active ? "* " : "  "}${n}`);
        }
        return;
      }
      await sessionSwitch(ctx.cwd, name);
      notify(ctx, `Switched to session: ${name}`);
    }
  });

  pi.registerCommand("threads", {
    description: "List threads or switch to one by ID.",
    handler: async (args: string[], ctx: any) => {
      const id = textFromArgs(args);
      if (!id) {
        const threads = await threadList(ctx.cwd);
        if (threads.length === 0) {
          notify(ctx, "No threads yet.");
          return;
        }
        for (const t of threads) {
          notify(ctx, `${t.id} ${t.status} ${t.title}`);
        }
        return;
      }
      await threadSwitch(ctx.cwd, id);
      notify(ctx, `Switched to thread: ${id}`);
    }
  });

  pi.registerCommand("rollback", {
    description: "Rollback a file to a previous version.",
    handler: async (args: string[], ctx: any) => {
      const parts = (Array.isArray(args) ? args : String(args ?? "").split(/\s+/));
      const path = parts[0];
      if (!path) {
        notify(ctx, "Usage: /rollback <path> [steps]");
        return;
      }
      const steps = parts[1] ? parseInt(parts[1], 10) : 1;
      const result = await fileRollback(ctx.cwd, path, steps);
      notify(ctx, result.ok ? `OK: ${result.message}` : `FAIL: ${result.message}`);
    }
  });

  pi.registerCommand("cache-stats", {
    description: "Show web cache statistics.",
    handler: async (_args: string[], ctx: any) => {
      const stats = await cacheStats(ctx.cwd);
      notify(ctx, `cache: total=${stats.total} valid=${stats.valid} expired=${stats.expired}`);
    }
  });

  pi.registerCommand("rdf-load", {
    description: "Load N-triples file into an RDF named graph.",
    handler: async (args: string[], ctx: any) => {
      const parts = (Array.isArray(args) ? args : String(args ?? "").split(/\s+/));
      const [path, id] = parts;
      if (!path || !id) {
        notify(ctx, "Usage: /rdf-load <path> <id>");
        return;
      }
      const result = await executeRdfTool(ctx.cwd, "rdf_load", { path, id });
      notify(ctx, String(result));
    }
  });

  pi.registerCommand("rdf-query", {
    description: "Query the RDF knowledge graph.",
    handler: async (args: string[], ctx: any) => {
      const query = textFromArgs(args);
      if (!query) {
        notify(ctx, "Usage: /rdf-query <query>");
        return;
      }
      const result = await executeRdfTool(ctx.cwd, "rdf_query", { query });
      notify(ctx, String(result));
    }
  });

  pi.registerCommand("rdf-insert", {
    description: "Insert a triple into the RDF store.",
    handler: async (args: string[], ctx: any) => {
      const parts = (Array.isArray(args) ? args : String(args ?? "").split(/\s+/));
      const [subject, predicate, object, graph] = parts;
      if (!subject || !predicate || !object) {
        notify(ctx, "Usage: /rdf-insert <subject> <predicate> <object> [graph]");
        return;
      }
      const result = await executeRdfTool(ctx.cwd, "rdf_insert", { subject, predicate, object, graph: graph ?? "default" });
      notify(ctx, String(result));
    }
  });

  pi.registerCommand("decomp", {
    description: "Decompose a task into subtasks using the decomposition planner.",
    handler: async (args: string[], ctx: any) => {
      const task = textFromArgs(args);
      if (!task) {
        notify(ctx, "Usage: /decomp <task>");
        return;
      }
      const { subtasks, patternId } = await runDecomposition(ctx.cwd, task, classifyTask(task));
      notify(ctx, `pattern=${patternId} type=${classifyTask(task)} subtasks=${subtasks.length}`);
      for (const s of subtasks) {
        notify(ctx, `  [${s.dependencies.join(",")}] ${s.profileHint}: ${s.description}`);
      }
    }
  });

  pi.registerCommand("stores", {
    description: "List dynamic stores or filter by namespace.",
    handler: async (args: string[], ctx: any) => {
      const ns = textFromArgs(args) || undefined;
      const specs = await storeList(ctx.cwd, ns ? { namespace: ns } : undefined);
      if (specs.length === 0) {
        notify(ctx, "No dynamic stores. Use /store create to make one.");
        return;
      }
      for (const s of specs) {
        notify(ctx, `${s.namespace}/${s.name} (${s.kind}) — ${s.description || "no description"}`);
      }
    }
  });

  pi.registerCommand("stores", {
    description: "List or manage dynamic stores.",
    handler: async (args: string[], ctx: any) => {
      const parts = Array.isArray(args) ? args : String(args ?? "").split(/\s+/);
      const [sub, name, ...rest] = parts;
      if (!sub) {
        const specs = await storeList(ctx.cwd);
        if (specs.length === 0) {
          notify(ctx, "No stores yet.");
          return;
        }
        for (const s of specs) {
          notify(ctx, `${s.namespace ? s.namespace + "/" : ""}${s.name} (${s.kind})`);
        }
        return;
      }
      try {
        switch (sub) {
          case "create": {
            const [kind, ns, ...descParts] = rest;
            if (!name || !kind) { notify(ctx, "Usage: /stores create <name> <kv|log|set|counter> [namespace] [description]"); return; }
            const spec = await storeCreate(ctx.cwd, name, kind as any, { namespace: ns || undefined, description: descParts.join(" ") || undefined });
            notify(ctx, `Created ${spec.namespace}/${spec.name} (${spec.kind})`);
            return;
          }
          case "delete": {
            const [ns] = rest;
            notify(ctx, await storeDelete(ctx.cwd, name, ns || undefined));
            return;
          }
          case "get": {
            const [field, ns] = rest;
            if (!field) { notify(ctx, "Usage: /stores get <name> <field> [namespace]"); return; }
            notify(ctx, await storeGet(ctx.cwd, name, field, ns || undefined));
            return;
          }
          case "set": {
            const [field, value, ns] = rest;
            if (!field || value === undefined) { notify(ctx, "Usage: /stores set <name> <field> <value> [namespace]"); return; }
            notify(ctx, await storeSet(ctx.cwd, name, field, value, ns || undefined));
            return;
          }
          case "rm": {
            const [field, ns] = rest;
            if (!field) { notify(ctx, "Usage: /stores rm <name> <field> [namespace]"); return; }
            notify(ctx, await storeRemove(ctx.cwd, name, field, ns || undefined));
            return;
          }
          case "dump": {
            const [ns] = rest;
            notify(ctx, await storeDump(ctx.cwd, name, ns || undefined));
            return;
          }
          default:
            notify(ctx, `Unknown store subcommand: ${sub}`);
        }
      } catch (err) {
        notify(ctx, `Error: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
  });

  pi.on("session_start", async (_event: any, ctx: any) => {
    globalToolRegistry.setCwd(ctx.cwd);

    const state = await loadProfileState(ctx.cwd);
    const evolution = await loadEvolutionState(ctx.cwd);
    const toolCount = ALL_TOOL_GROUPS.reduce((n, g) => n + g.definitions.length, 0);
    if (!welcomeShown) {
      welcomeShown = true;
      if (ctx.hasUI !== false && typeof ctx.ui.setHeader === "function") {
        ctx.ui.setHeader(createChrysalisWelcomeComponent(pi, ctx, state, evolution));
      } else if (typeof ctx.ui.setWidget === "function") {
        ctx.ui.setWidget("chrysalis-welcome", createChrysalisWelcomeComponent(pi, ctx, state, evolution));
      }
    }
    notify(
      ctx,
      `Chrysalis loaded. ${toolCount} LLM tools registered. Active profile: ${state.activeProfile}.`
    );
    for (const line of summarizeEvolutionState(evolution)) {
      notify(ctx, line);
    }
    void runAutonomousEvolution(ctx.cwd, { kind: "session_start", profile: state.activeProfile }).then((report) => {
      if (report.applied) {
        notify(ctx, `Autonomous evolution applied: ${report.decision.reason}`);
      }
    });

    globalToolRegistry.on("tool:evolved", ({ name, variant, rejected }: any) => {
      notify(ctx, `Tool '${name}' evolved: novelty=${variant.noveltyScore?.toFixed(2)} ${rejected ? "(low novelty)" : "(active)"}`);
    });
    globalToolRegistry.on("tool:enabled", ({ name }: any) => {
      notify(ctx, `Tool '${name}' enabled`);
    });
    globalToolRegistry.on("tool:disabled", ({ name }: any) => {
      notify(ctx, `Tool '${name}' disabled`);
    });
    globalToolRegistry.on("tool:variant-selected", ({ name, variantId }: any) => {
      notify(ctx, `Tool '${name}' variant ${variantId} selected`);
    });
  });
}
