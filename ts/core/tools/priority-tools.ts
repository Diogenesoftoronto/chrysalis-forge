import { interpretProfilePhrase } from "../priority.js";
import { loadProfileState, saveProfileState } from "../project.js";

export const PRIORITY_TOOL_DEFINITIONS = [
  {
    name: "set_priority",
    description: "Set the active Chrysalis execution profile. Convenience wrapper around the /profile command for LLM-initiated profile changes based on task context.",
    parameters: {
      type: "object",
      properties: {
        profile: { type: "string", description: "Profile to set (fast/cheap/best/verbose) or natural language phrase" },
        reason: { type: "string", description: "Reason for the priority change" }
      },
      required: ["profile"]
    }
  },
  {
    name: "get_priority",
    description: "Get the currently active execution profile.",
    parameters: {
      type: "object",
      properties: {}
    }
  },
  {
    name: "suggest_priority",
    description: "Suggest an appropriate profile based on task description or type.",
    parameters: {
      type: "object",
      properties: {
        task: { type: "string", description: "Task description to analyze" },
        task_type: { type: "string", description: "Task type override (refactor/implement/debug/research/test/general)" }
      },
      required: []
    }
  }
];

export async function executePriorityTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "set_priority": {
      const profilePhrase = String(args.profile ?? "best");
      const reason = String(args.reason ?? "");
      
      const interpretation = interpretProfilePhrase(profilePhrase);
      const state = await saveProfileState(cwd, interpretation.profile, reason || interpretation.reason);
      
      return JSON.stringify({
        profile: state.activeProfile,
        reason: reason || interpretation.reason,
        updatedAt: state.updatedAt
      }, null, 2);
    }
    case "get_priority": {
      const state = await loadProfileState(cwd);
      return JSON.stringify({
        activeProfile: state.activeProfile,
        reason: state.reason,
        updatedAt: state.updatedAt
      }, null, 2);
    }
    case "suggest_priority": {
      const task = String(args.task ?? "");
      const taskType = String(args.task_type ?? "");
      
      let phrase = "";
      if (taskType) {
        const typeToProfile: Record<string, string> = {
          debug: "fast",
          implement: "best",
          refactor: "best",
          research: "cheap",
          test: "fast",
          document: "cheap",
          general: "best"
        };
        phrase = typeToProfile[taskType] ?? "best";
      } else if (task) {
        phrase = task;
      }
      
      const interpretation = interpretProfilePhrase(phrase);
      return JSON.stringify({
        suggestedProfile: interpretation.profile,
        reason: interpretation.reason,
        taskAnalyzed: task || taskType || "none"
      }, null, 2);
    }
    default:
      return `Unknown priority tool: ${name}`;
  }
}
