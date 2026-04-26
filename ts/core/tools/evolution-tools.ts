import { evolveSystemPrompt, evolveMetaPrompt, evolveHarnessStrategy, loadEvolutionArchive, loadEvolutionState, summarizeEvolutionState, suggestProfileFromStats } from "../evolution.js";
import { logEval, getProfileStats, suggestProfile } from "../stores/eval-store.js";
import { loadProfileState } from "../project.js";

export const EVOLUTION_TOOL_DEFINITIONS = [
  {
    name: "evolve_system",
    description: "Evolve the system prompt using GEPA-style mutation. Provide feedback describing what should improve. The evolution engine rewrites the prompt, gates by novelty, and archives in MAP-Elites.",
    parameters: {
      type: "object",
      properties: {
        feedback: { type: "string", description: "Feedback describing desired improvement" }
      },
      required: ["feedback"]
    }
  },
  {
    name: "evolve_meta",
    description: "Evolve the meta/optimizer prompt. This mutates the prompt that governs how system prompts are evolved — meta-optimization.",
    parameters: {
      type: "object",
      properties: {
        feedback: { type: "string", description: "Feedback for meta-prompt evolution" }
      },
      required: ["feedback"]
    }
  },
  {
    name: "evolve_harness",
    description: "Mutate the harness strategy (12 evolvable fields) based on feedback. Harness controls execution priority, strategy type, subtask limits, and other runtime parameters.",
    parameters: {
      type: "object",
      properties: {
        feedback: { type: "string", description: "Feedback for harness mutation" }
      },
      required: ["feedback"]
    }
  },
  {
    name: "log_feedback",
    description: "Log task evaluation feedback. Records task success/failure, profile used, tools used, and duration for profile learning.",
    parameters: {
      type: "object",
      properties: {
        task_id: { type: "string", description: "Unique task identifier" },
        success: { type: "boolean", description: "Whether the task succeeded" },
        profile: { type: "string", description: "Profile used (fast/cheap/best/verbose)" },
        task_type: { type: "string", description: "Task type (refactor/implement/debug/research/test/document/general)" },
        tools_used: { type: "array", items: { type: "string" }, description: "List of tools used during task" },
        duration_ms: { type: "integer", description: "Task duration in milliseconds" },
        feedback: { type: "string", description: "Free-text feedback about the task outcome" }
      },
      required: ["task_id", "success", "profile", "task_type"]
    }
  },
  {
    name: "suggest_profile",
    description: "Suggest the best execution profile for a given task type, based on historical evaluation data.",
    parameters: {
      type: "object",
      properties: {
        task_type: { type: "string", description: "Task type to suggest a profile for" }
      },
      required: ["task_type"]
    }
  },
  {
    name: "profile_stats",
    description: "Get performance statistics for execution profiles. Shows success rates, task type breakdown, and tool usage frequency.",
    parameters: {
      type: "object",
      properties: {
        profile: { type: "string", description: "Profile name to inspect (omit for all profiles)" }
      },
      required: []
    }
  },
  {
    name: "archive_list",
    description: "List entries in the evolution archive. Each entry is a MAP-Elites archived prompt variant with phenotype, family, and bin key.",
    parameters: {
      type: "object",
      properties: {
        limit: { type: "integer", description: "Max entries to return (default 10)" }
      },
      required: []
    }
  },
  {
    name: "evolution_stats",
    description: "Get current evolution state summary: generation count, archive size, bandit model selection state.",
    parameters: {
      type: "object",
      properties: {},
      required: []
    }
  }
];

export async function executeEvolutionTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "evolve_system": {
      const profile = (await loadProfileState(cwd)).activeProfile;
      const result = await evolveSystemPrompt(cwd, String(args.feedback ?? ""), profile);
      return JSON.stringify({
        rejected: result.rejected ?? false,
        noveltyScore: result.noveltyScore,
        family: result.entry.family
      }, null, 2);
    }
    case "evolve_meta": {
      const profile = (await loadProfileState(cwd)).activeProfile;
      const result = await evolveMetaPrompt(cwd, String(args.feedback ?? ""), profile);
      return JSON.stringify({
        noveltyScore: result.noveltyScore,
        family: result.entry.family
      }, null, 2);
    }
    case "evolve_harness": {
      const profile = (await loadProfileState(cwd)).activeProfile;
      const result = await evolveHarnessStrategy(cwd, String(args.feedback ?? ""), profile);
      return JSON.stringify({
        executionPriority: result.harness.executionPriority,
        strategyType: result.harness.strategyType
      }, null, 2);
    }
    case "log_feedback": {
      await logEval(cwd, {
        taskId: String(args.task_id ?? ""),
        success: Boolean(args.success),
        profile: String(args.profile ?? "best"),
        taskType: String(args.task_type ?? "general"),
        toolsUsed: Array.isArray(args.tools_used) ? args.tools_used.map(String) : [],
        durationMs: Number(args.duration_ms ?? 0),
        feedback: String(args.feedback ?? ""),
        evalStage: "post_task"
      });
      return "Feedback logged.";
    }
    case "suggest_profile": {
      const result = await suggestProfile(cwd, String(args.task_type ?? "general"));
      return JSON.stringify(result, null, 2);
    }
    case "profile_stats": {
      const profile = args.profile ? String(args.profile) : undefined;
      const stats = await getProfileStats(cwd, profile);
      return JSON.stringify(stats, null, 2);
    }
    case "archive_list": {
      const limit = Number(args.limit ?? 10);
      const archive = await loadEvolutionArchive(cwd);
      const entries = archive.slice(0, limit).map((e) => ({
        id: e.id,
        family: e.family,
        binKey: e.binKey,
        phenotype: e.phenotype
      }));
      return JSON.stringify(entries, null, 2);
    }
    case "evolution_stats": {
      const state = await loadEvolutionState(cwd);
      return summarizeEvolutionState(state).join("\n");
    }
    default:
      return `Unknown evolution tool: ${name}`;
  }
}
