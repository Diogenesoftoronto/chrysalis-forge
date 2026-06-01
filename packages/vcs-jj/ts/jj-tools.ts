import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export const JJ_TOOL_DEFINITIONS = [
  {
    name: "jj_status",
    description: "Show working copy and staging area status.",
    parameters: { type: "object", properties: {}, required: [] }
  },
  {
    name: "jj_log",
    description: "Show revision log. Returns recent commit history in jj format.",
    parameters: {
      type: "object",
      properties: {
        count: { type: "integer", description: "Number of revisions to show (default 10)" }
      },
      required: []
    }
  },
  {
    name: "jj_diff",
    description: "Show diff of the working copy or a specific revision.",
    parameters: {
      type: "object",
      properties: {
        revision: { type: "string", description: "Revision to diff (omit for working copy)" },
        stat: { type: "boolean", description: "Show stat summary instead of full diff" }
      },
      required: []
    }
  },
  {
    name: "jj_undo",
    description: "Undo the last operation.",
    parameters: { type: "object", properties: {}, required: [] }
  },
  {
    name: "jj_op_log",
    description: "Show the operation log.",
    parameters: {
      type: "object",
      properties: {
        count: { type: "integer", description: "Number of operations to show (default 10)" }
      },
      required: []
    }
  },
  {
    name: "jj_op_restore",
    description: "Restore the repo to a previous operation.",
    parameters: {
      type: "object",
      properties: {
        operation: { type: "string", description: "Operation ID to restore to" }
      },
      required: ["operation"]
    }
  },
  {
    name: "jj_workspace_add",
    description: "Add a workspace.",
    parameters: {
      type: "object",
      properties: {
        name: { type: "string", description: "Workspace name" }
      },
      required: ["name"]
    }
  },
  {
    name: "jj_workspace_list",
    description: "List workspaces.",
    parameters: { type: "object", properties: {}, required: [] }
  },
  {
    name: "jj_describe",
    description: "Set the description of a revision.",
    parameters: {
      type: "object",
      properties: {
        revision: { type: "string", description: "Revision to describe (default @)" },
        message: { type: "string", description: "New description" }
      },
      required: ["message"]
    }
  },
  {
    name: "jj_new",
    description: "Create a new revision on top of the current one.",
    parameters: {
      type: "object",
      properties: {
        message: { type: "string", description: "Description for the new revision" }
      },
      required: []
    }
  }
];

async function jj(cwd: string, ...args: string[]): Promise<string> {
  try {
    const { stdout } = await execFileAsync("jj", args, { cwd, maxBuffer: 5 * 1024 * 1024 });
    return stdout || "(no output)";
  } catch (err: any) {
    if (err.stderr) return `Error: ${err.stderr.trim()}`;
    return `Error: ${err.message}`;
  }
}

export async function executeJjTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "jj_status":
      return jj(cwd, "status");
    case "jj_log": {
      const count = String(Number(args.count ?? 10));
      return jj(cwd, "log", "-n", count);
    }
    case "jj_diff": {
      const revision = args.revision ? String(args.revision) : undefined;
      const stat = Boolean(args.stat);
      const diffArgs = ["diff"];
      if (revision) diffArgs.push("-r", revision);
      if (stat) diffArgs.push("--stat");
      return jj(cwd, ...diffArgs);
    }
    case "jj_undo":
      return jj(cwd, "undo");
    case "jj_op_log": {
      const count = String(Number(args.count ?? 10));
      return jj(cwd, "op", "log", "-n", count);
    }
    case "jj_op_restore": {
      const operation = String(args.operation ?? "");
      return jj(cwd, "op", "restore", operation);
    }
    case "jj_workspace_add": {
      const name_ = String(args.name ?? "");
      return jj(cwd, "workspace", "add", name_);
    }
    case "jj_workspace_list":
      return jj(cwd, "workspace", "list");
    case "jj_describe": {
      const revision = args.revision ? ["-r", String(args.revision)] : [];
      const message = String(args.message ?? "");
      return jj(cwd, "describe", ...revision, "-m", message);
    }
    case "jj_new": {
      const message = args.message ? ["-m", String(args.message)] : [];
      return jj(cwd, "new", ...message);
    }
    default:
      return `Unknown jj tool: ${name}`;
  }
}
