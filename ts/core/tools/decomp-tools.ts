import { classifyTask, suggestProfileForSubtask, runDecomposition, shouldVote } from "../decomp-planner.js";
import { tallyVotes, STAKES_PRESETS, selectStakes } from "../decomp-voter.js";

export const DECOMP_TOOL_DEFINITIONS = [
  {
    name: "decompose_task",
    description: "Decompose a task into subtasks with dependency ordering and profile hints. Uses LLM-backed decomposition with heuristic fallback.",
    parameters: {
      type: "object",
      properties: {
        task: { type: "string", description: "Task description to decompose" },
        task_type: { type: "string", description: "Override task type classification (refactor/implement/debug/research/test/document/general)" }
      },
      required: ["task"]
    }
  },
  {
    name: "classify_task",
    description: "Classify a task description into a type: refactor, implement, debug, research, test, document, or general.",
    parameters: {
      type: "object",
      properties: {
        task: { type: "string", description: "Task description" }
      },
      required: ["task"]
    }
  },
  {
    name: "decomp_vote",
    description: "Run first-to-K voting on decomposition alternatives. Requires 3+ proposals, reaches consensus at K matching votes.",
    parameters: {
      type: "object",
      properties: {
        task: { type: "string", description: "Task being voted on" },
        proposals: { type: "array", items: { type: "string" }, description: "List of decomposition proposals to vote on" },
        k: { type: "integer", description: "Consensus threshold (default 2)" }
      },
      required: ["task", "proposals"]
    }
  }
];

export async function executeDecompTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "decompose_task": {
      const task = String(args.task ?? "");
      if (!task) return "Error: task is required";
      const taskType = String(args.task_type ?? classifyTask(task));
      const { subtasks, patternId } = await runDecomposition(cwd, task, taskType);
      return JSON.stringify({ patternId, taskType, subtasks }, null, 2);
    }
    case "classify_task": {
      const task = String(args.task ?? "");
      if (!task) return "Error: task is required";
      return classifyTask(task);
    }
    case "decomp_vote": {
      const task = String(args.task ?? "");
      const proposals = Array.isArray(args.proposals) ? args.proposals.map(String) : [];
      const k = Number(args.k ?? 2);
      if (!task) return "Error: task is required";
      if (proposals.length < 2) return "Error: at least 2 proposals required";
      const stakes = selectStakes(task);
      const config = { ...STAKES_PRESETS[stakes], kThreshold: k };
      const result = tallyVotes(proposals, config);
      return JSON.stringify({ stakes, consensus: result.consensus, winner: result.winner, margin: result.margin }, null, 2);
    }
    default:
      return `Unknown decomp tool: ${name}`;
  }
}
