import "dotenv/config";

import { relative } from "node:path";

import {
  evolveHarnessStrategy,
  evolveMetaPrompt,
  evolveSystemPrompt,
  loadEvolutionArchive,
  loadEvolutionState,
  summarizeEvolutionState,
  suggestProfileFromStats
} from "../core/evolution.js";
import { detectPiRuntime, launchPi } from "../runtime/pi.js";
import { ensureProjectScaffold, listArtifacts, loadProfileState, saveProfileState, writeTaskPlanArtifact } from "../core/project.js";
import { configPath, loadConfig } from "../core/config.js";
import { evolutionMetaPromptPath, evolutionSystemPromptPath } from "../core/paths.js";
import { interpretProfilePhrase } from "../core/priority.js";
import { loadSessionStats, getSessionStatsDisplay, formatTokens, formatCost } from "../core/stores/session-stats.js";
import { sessionList, sessionListWithMetadata, sessionCreate, sessionSwitch, sessionDelete, sessionGetActive } from "../core/stores/context-store.js";
import { threadList, threadCreate, threadSwitch, threadFind, threadContinue, threadSpawnChild, threadGetActive, threadGetRelations } from "../core/stores/thread-store.js";
import { fileBackup, fileRollback, fileRollbackList, rollbackHistorySize } from "../core/stores/rollback-store.js";
import { cacheStats, cacheCleanup } from "../core/stores/cache-store.js";
import { getProfileStats, getToolStats, suggestProfile as suggestEvalProfile } from "../core/stores/eval-store.js";
import { listArchives, archiveStats } from "../core/stores/decomp-archive.js";
import { executeRdfTool } from "../core/tools/rdf-tools.js";
import { classifyTask, decomposeTaskLLM, heuristicDecomposition, runDecomposition, shouldVote } from "../core/decomp-planner.js";
import { selectPatternForPriority, selectOrDecompose } from "../core/decomp-selector.js";
import { STAKES_PRESETS, selectStakes } from "../core/decomp-voter.js";
import { storeCreate, storeDelete, storeList, storeGet, storeSet, storeRemove, storeDump, storeDescribe } from "../core/stores/store-registry.js";

function usage(): void {
  console.log(`chrysalis commands:
  shell [initial prompt...]   Launch the Pi-powered terminal shell
  plan <task>                 Write a task plan artifact using Ax when configured
  decomp <task>               Decompose a task into subtasks (LLM-backed)
  profile [phrase]            Print or set the active Chrysalis profile
  evolve <feedback>           Force a system-prompt evolution pass
  meta-evolve <feedback>      Force an optimizer/meta-prompt evolution pass
  harness <feedback>          Force a harness-strategy mutation
  archive                     List archived evolution variants
  stats                       Print profile-learning statistics
  outputs                     List generated artifacts under .chrysalis/outputs
  sessions                    List sessions
  session <name>              Switch to a session
  threads                     List threads
  thread <id>                 Switch to a thread
  rollback <path> [steps]     Rollback a file (default: 1 step)
  cache-stats                 Show cache statistics
  rdf-load <path> <id>        Load triples into an RDF graph
  rdf-query <query> [id]      Query the RDF knowledge graph
  rdf-insert <s> <p> <o> [g] Insert a triple into the RDF store
  stores [ns]                 List dynamic stores (optional namespace filter)
  store create <n> <kind>    Create a store (kv|log|set|counter)
  store delete <n> [ns]       Delete a dynamic store
  store get <n> <field> [ns]  Get a value from a store
  store set <n> <f> <v> [ns]  Set a value in a store
  store rm <n> <field> [ns]   Remove a field/entry from a store
  store dump <n> [ns]         Dump full store contents
  doctor                      Inspect Pi runtime and config resolution
  help                        Show this help
`);
}

async function run(): Promise<void> {
  const [command = "shell", ...args] = process.argv.slice(2);
  const cwd = process.cwd();

  switch (command) {
    case "shell": {
      const exitCode = await launchPi(cwd, args);
      process.exitCode = exitCode;
      return;
    }
    case "plan": {
      const task = args.join(" ").trim();
      if (!task) throw new Error("plan requires a task description.");
      const artifact = await writeTaskPlanArtifact(cwd, task);
      console.log(relative(cwd, artifact.planPath));
      return;
    }
    case "profile": {
      await ensureProjectScaffold(cwd);
      if (args.length === 0) {
        const state = await loadProfileState(cwd);
        console.log(`${state.activeProfile} ${state.updatedAt}${state.reason ? ` ${state.reason}` : ""}`);
        return;
      }
      const phrase = args.join(" ");
      const next = interpretProfilePhrase(phrase);
      const state = await saveProfileState(cwd, next.profile, next.reason);
      console.log(`${state.activeProfile} ${state.updatedAt} ${state.reason}`);
      return;
    }
    case "evolve": {
      await ensureProjectScaffold(cwd);
      const feedback = args.join(" ").trim();
      if (!feedback) throw new Error("evolve requires feedback text.");
      const profile = (await loadProfileState(cwd)).activeProfile;
      const result = await evolveSystemPrompt(cwd, feedback, profile);
      console.log(`saved ${relative(cwd, evolutionSystemPromptPath(cwd))}${result.rejected ? " (low novelty)" : ""}`);
      console.log(`novelty=${result.noveltyScore.toFixed(3)}`);
      return;
    }
    case "meta-evolve": {
      await ensureProjectScaffold(cwd);
      const feedback = args.join(" ").trim();
      if (!feedback) throw new Error("meta-evolve requires feedback text.");
      const profile = (await loadProfileState(cwd)).activeProfile;
      const result = await evolveMetaPrompt(cwd, feedback, profile);
      console.log(`saved ${relative(cwd, evolutionMetaPromptPath(cwd))}`);
      console.log(`novelty=${result.noveltyScore.toFixed(3)}`);
      return;
    }
    case "harness": {
      await ensureProjectScaffold(cwd);
      const feedback = args.join(" ").trim();
      if (!feedback) throw new Error("harness requires feedback text.");
      const profile = (await loadProfileState(cwd)).activeProfile;
      const result = await evolveHarnessStrategy(cwd, feedback, profile);
      console.log(JSON.stringify(result.harness, null, 2));
      return;
    }
    case "archive": {
      await ensureProjectScaffold(cwd);
      const archive = await loadEvolutionArchive(cwd);
      for (const entry of archive.slice(0, 20)) {
        console.log(`${entry.createdAt} ${entry.family} ${entry.binKey} score=${entry.score.toFixed(2)} ${entry.id}`);
      }
      return;
    }
    case "stats": {
      await ensureProjectScaffold(cwd);
      const state = await loadEvolutionState(cwd);
      const { profile } = await suggestProfileFromStats(cwd, "build");
      for (const line of summarizeEvolutionState(state)) {
        console.log(line);
      }
      console.log(`suggested_profile=${profile}`);
      return;
    }
    case "outputs": {
      await ensureProjectScaffold(cwd);
      const artifacts = await listArtifacts(cwd);
      for (const artifact of artifacts) {
        console.log(relative(cwd, artifact.path));
      }
      return;
    }
    case "decomp": {
      const task = args.join(" ").trim();
      if (!task) throw new Error("decomp requires a task description.");
      const { subtasks, patternId } = await runDecomposition(cwd, task, classifyTask(task));
      console.log(`pattern=${patternId} type=${classifyTask(task)} subtasks=${subtasks.length}`);
      for (const s of subtasks) {
        console.log(`  [${s.dependencies.join(",")}] ${s.profileHint}: ${s.description}`);
      }
      return;
    }
    case "sessions": {
      await ensureProjectScaffold(cwd);
      const { names, active } = await sessionList(cwd);
      for (const name of names) {
        console.log(`${name === active ? "* " : "  "}${name}`);
      }
      return;
    }
    case "session": {
      await ensureProjectScaffold(cwd);
      const name = args[0];
      if (!name) throw new Error("session requires a name.");
      await sessionSwitch(cwd, name);
      console.log(`Switched to session: ${name}`);
      return;
    }
    case "threads": {
      await ensureProjectScaffold(cwd);
      const threads = await threadList(cwd);
      for (const t of threads) {
        console.log(`${t.id} ${t.status} ${t.title}`);
      }
      return;
    }
    case "thread": {
      await ensureProjectScaffold(cwd);
      const id = args[0];
      if (!id) throw new Error("thread requires an ID.");
      await threadSwitch(cwd, id);
      console.log(`Switched to thread: ${id}`);
      return;
    }
    case "rollback": {
      await ensureProjectScaffold(cwd);
      const path = args[0];
      if (!path) throw new Error("rollback requires a file path.");
      const steps = args[1] ? parseInt(args[1], 10) : 1;
      const result = await fileRollback(cwd, path, steps);
      console.log(result.ok ? `OK: ${result.message}` : `FAIL: ${result.message}`);
      return;
    }
    case "cache-stats": {
      await ensureProjectScaffold(cwd);
      const stats = await cacheStats(cwd);
      console.log(`total=${stats.total} valid=${stats.valid} expired=${stats.expired}`);
      return;
    }
    case "rdf-load": {
      await ensureProjectScaffold(cwd);
      const [path, id] = args;
      if (!path || !id) throw new Error("rdf-load requires <path> <id>.");
      console.log(await executeRdfTool(cwd, "rdf_load", { path, id }));
      return;
    }
    case "rdf-query": {
      await ensureProjectScaffold(cwd);
      const query = args.join(" ").trim();
      if (!query) throw new Error("rdf-query requires a query string.");
      console.log(await executeRdfTool(cwd, "rdf_query", { query }));
      return;
    }
    case "rdf-insert": {
      await ensureProjectScaffold(cwd);
      const [subject, predicate, object, graph] = args;
      if (!subject || !predicate || !object) throw new Error("rdf-insert requires <subject> <predicate> <object> [graph].");
      console.log(await executeRdfTool(cwd, "rdf_insert", { subject, predicate, object, graph: graph ?? "default" }));
      return;
    }
    case "stores": {
      await ensureProjectScaffold(cwd);
      const specs = await storeList(cwd, args[0] ? { namespace: args[0] } : undefined);
      if (specs.length === 0) { console.log("No dynamic stores."); return; }
      for (const s of specs) {
        console.log(`${s.namespace}/${s.name} (${s.kind}) ${s.description || ""}`);
      }
      return;
    }
    case "store": {
      await ensureProjectScaffold(cwd);
      const [sub, name, ...rest] = args;
      if (!sub) throw new Error("store requires a subcommand: create, delete, get, set, rm, dump");
      switch (sub) {
        case "create": {
          const [kind, ns, ...descParts] = rest;
          if (!name || !kind) throw new Error("store create <name> <kind> [namespace] [description]");
          const spec = await storeCreate(cwd, name, kind as any, { namespace: ns || undefined, description: descParts.join(" ") || undefined });
          console.log(`Created ${spec.namespace}/${spec.name} (${spec.kind})`);
          return;
        }
        case "delete": {
          const [ns] = rest;
          console.log(await storeDelete(cwd, name, ns || undefined));
          return;
        }
        case "get": {
          const [field, ns] = rest;
          if (!field) throw new Error("store get <name> <field> [namespace]");
          console.log(await storeGet(cwd, name, field, ns || undefined));
          return;
        }
        case "set": {
          const [field, value, ns] = rest;
          if (!field || value === undefined) throw new Error("store set <name> <field> <value> [namespace]");
          console.log(await storeSet(cwd, name, field, value, ns || undefined));
          return;
        }
        case "rm": {
          const [field, ns] = rest;
          if (!field) throw new Error("store rm <name> <field> [namespace]");
          console.log(await storeRemove(cwd, name, field, ns || undefined));
          return;
        }
        case "dump": {
          const [ns] = rest;
          console.log(await storeDump(cwd, name, ns || undefined));
          return;
        }
        default:
          throw new Error(`Unknown store subcommand: ${sub}`);
      }
    }
    case "doctor": {
      await ensureProjectScaffold(cwd);
      const config = await loadConfig(cwd);
      const runtime = await detectPiRuntime(cwd);
      console.log(`config_path=${configPath(cwd)}`);
      console.log(`pi_runtime_preference=${config.pi.runtimePreference}`);
      console.log(`pi_default_provider=${config.pi.defaultProvider ?? "unset"}`);
      console.log(`pi_default_model=${config.pi.defaultModel ?? "unset"}`);
      console.log(`pi_default_thinking=${config.pi.defaultThinking ?? "unset"}`);
      console.log(`profile_default=${config.profiles.default}`);
      console.log("autonomous_evolution=enabled");
      for (const line of summarizeEvolutionState(await loadEvolutionState(cwd))) {
        console.log(line);
      }
      const sessionStats = await loadSessionStats(cwd);
      const display = getSessionStatsDisplay(sessionStats);
      console.log(`session_turns=${display.turns} tokens=${formatTokens(Number(display.totalTokens))} cost=${formatCost(Number(display.totalCost))}`);
      const cacheStat = await cacheStats(cwd);
      console.log(`cache_total=${cacheStat.total} cache_valid=${cacheStat.valid}`);
      console.log(`pi_standalone=${runtime.standalone ? runtime.standalone.command : "missing"}`);
      console.log(`pi_embedded=${runtime.embedded ? runtime.embedded.cliPath ?? runtime.embedded.command : "missing"}`);
      console.log(`pi_selected=${runtime.selected ? runtime.selected.kind : "missing"}`);
      return;
    }
    case "help":
    case "--help":
    case "-h": {
      usage();
      return;
    }
    default:
      throw new Error(`Unknown command: ${command}`);
  }
}

run().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
