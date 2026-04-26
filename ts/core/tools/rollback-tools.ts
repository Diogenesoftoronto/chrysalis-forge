import { fileRollback, fileRollbackList, rollbackHistorySize, clearRollbackHistory } from "../stores/rollback-store.js";

export const ROLLBACK_TOOL_DEFINITIONS = [
  {
    name: "file_rollback",
    description: "Rollback a file to a previous version. Restores the file from the backup history maintained by Chrysalis.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path to the file to rollback" },
        steps: { type: "integer", description: "Number of versions to go back (default 1)" }
      },
      required: ["path"]
    }
  },
  {
    name: "file_rollback_list",
    description: "List available rollback versions for a file. Shows timestamp and step number for each backup.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path to check rollback history for" }
      },
      required: ["path"]
    }
  }
];

export async function executeRollbackTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "file_rollback": {
      const path = String(args.path ?? "");
      if (!path) return "Error: path is required";
      const steps = Number(args.steps ?? 1);
      const result = await fileRollback(cwd, path, steps);
      return result.ok ? `OK: ${result.message}` : `FAIL: ${result.message}`;
    }
    case "file_rollback_list": {
      const path = String(args.path ?? "");
      if (!path) return "Error: path is required";
      const list = await fileRollbackList(cwd, path);
      return JSON.stringify(list, null, 2);
    }
    default:
      return `Unknown rollback tool: ${name}`;
  }
}
