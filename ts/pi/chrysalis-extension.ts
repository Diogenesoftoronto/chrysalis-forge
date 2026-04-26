import { relative } from "node:path";

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
    pi.registerTool({
      name: def.name,
      label: def.name.replace(/_/g, " "),
      description: def.description,
      parameters: def.parameters,
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
    description: "List Chrysalis sessions.",
    handler: async (_args: string[], ctx: any) => {
      const { names, active } = await sessionList(ctx.cwd);
      if (names.length === 0) {
        notify(ctx, "No sessions yet.");
        return;
      }
      for (const name of names) {
        notify(ctx, `${name === active ? "* " : "  "}${name}`);
      }
    }
  });

  pi.registerCommand("session", {
    description: "Switch to a Chrysalis session by name.",
    handler: async (args: string[], ctx: any) => {
      const name = textFromArgs(args);
      if (!name) {
        notify(ctx, "Usage: /session <name>");
        return;
      }
      await sessionSwitch(ctx.cwd, name);
      notify(ctx, `Switched to session: ${name}`);
    }
  });

  pi.registerCommand("threads", {
    description: "List Chrysalis threads.",
    handler: async (_args: string[], ctx: any) => {
      const threads = await threadList(ctx.cwd);
      if (threads.length === 0) {
        notify(ctx, "No threads yet.");
        return;
      }
      for (const t of threads) {
        notify(ctx, `${t.id} ${t.status} ${t.title}`);
      }
    }
  });

  pi.registerCommand("thread", {
    description: "Switch to a Chrysalis thread by ID.",
    handler: async (args: string[], ctx: any) => {
      const id = textFromArgs(args);
      if (!id) {
        notify(ctx, "Usage: /thread <id>");
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

  pi.registerCommand("store", {
    description: "Manage dynamic stores: create, delete, get, set, rm, dump.",
    handler: async (args: string[], ctx: any) => {
      const parts = Array.isArray(args) ? args : String(args ?? "").split(/\s+/);
      const [sub, name, ...rest] = parts;
      if (!sub) {
        notify(ctx, "Usage: /store <create|delete|get|set|rm|dump> <name> ...");
        return;
      }
      try {
        switch (sub) {
          case "create": {
            const [kind, ns, ...descParts] = rest;
            if (!name || !kind) { notify(ctx, "Usage: /store create <name> <kv|log|set|counter> [namespace] [description]"); return; }
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
            if (!field) { notify(ctx, "Usage: /store get <name> <field> [namespace]"); return; }
            notify(ctx, await storeGet(ctx.cwd, name, field, ns || undefined));
            return;
          }
          case "set": {
            const [field, value, ns] = rest;
            if (!field || value === undefined) { notify(ctx, "Usage: /store set <name> <field> <value> [namespace]"); return; }
            notify(ctx, await storeSet(ctx.cwd, name, field, value, ns || undefined));
            return;
          }
          case "rm": {
            const [field, ns] = rest;
            if (!field) { notify(ctx, "Usage: /store rm <name> <field> [namespace]"); return; }
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
    const state = await loadProfileState(ctx.cwd);
    const evolution = await loadEvolutionState(ctx.cwd);
    const toolCount = ALL_TOOL_GROUPS.reduce((n, g) => n + g.definitions.length, 0);
    notify(
      ctx,
      `Chrysalis loaded. ${toolCount} LLM tools registered. Autonomous evolution runs on session start and planning. Commands: /plan, /profile, /evolve, /meta-evolve, /harness, /archive, /stats, /outputs, /sessions, /session, /threads, /thread, /rollback, /cache-stats, /rdf-load, /rdf-query, /rdf-insert, /decomp, /stores, /store. Active profile: ${state.activeProfile}.`
    );
    for (const line of summarizeEvolutionState(evolution)) {
      notify(ctx, line);
    }
    void runAutonomousEvolution(ctx.cwd, { kind: "session_start", profile: state.activeProfile }).then((report) => {
      if (report.applied) {
        notify(ctx, `Autonomous evolution applied: ${report.decision.reason}`);
      }
    });
  });
}
