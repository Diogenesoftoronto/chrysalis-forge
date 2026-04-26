import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export const GIT_TOOL_DEFINITIONS = [
  {
    name: "git_status",
    description: "Show working tree status. Reports staged, unstaged, and untracked files.",
    parameters: {
      type: "object",
      properties: {
        short: { type: "boolean", description: "Use short format (default true)" }
      },
      required: []
    }
  },
  {
    name: "git_diff",
    description: "Show changes between commits, commit and working tree, etc. Returns diff output.",
    parameters: {
      type: "object",
      properties: {
        target: { type: "string", description: "What to diff: 'staged', 'unstaged', or a commit ref (default 'unstaged')" },
        path: { type: "string", description: "Limit diff to specific path" },
        stat: { type: "boolean", description: "Show stat summary instead of full diff" }
      },
      required: []
    }
  },
  {
    name: "git_log",
    description: "Show commit logs. Returns recent commit history.",
    parameters: {
      type: "object",
      properties: {
        count: { type: "integer", description: "Number of commits to show (default 10)" },
        oneline: { type: "boolean", description: "One line per commit (default true)" },
        path: { type: "string", description: "Limit to commits touching this path" }
      },
      required: []
    }
  },
  {
    name: "git_commit",
    description: "Record changes to the repository. Stages all tracked changes and commits.",
    parameters: {
      type: "object",
      properties: {
        message: { type: "string", description: "Commit message" },
        all: { type: "boolean", description: "Stage all tracked files (default true)" }
      },
      required: ["message"]
    }
  },
  {
    name: "git_checkout",
    description: "Switch branches or restore working tree files.",
    parameters: {
      type: "object",
      properties: {
        target: { type: "string", description: "Branch name or file path to restore" },
        create: { type: "boolean", description: "Create a new branch (default false)" }
      },
      required: ["target"]
    }
  },
  {
    name: "git_add",
    description: "Add file contents to the index.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path to add ('.' for all, default '.')" }
      },
      required: []
    }
  },
  {
    name: "git_branch",
    description: "List, create, or delete branches.",
    parameters: {
      type: "object",
      properties: {
        action: { type: "string", description: "'list' (default), 'create', or 'delete'" },
        name: { type: "string", description: "Branch name (for create/delete)" }
      },
      required: []
    }
  }
];

async function git(cwd: string, ...args: string[]): Promise<string> {
  try {
    const { stdout } = await execFileAsync("git", args, { cwd, maxBuffer: 5 * 1024 * 1024 });
    return stdout || "(no output)";
  } catch (err: any) {
    if (err.stderr) return `Error: ${err.stderr.trim()}`;
    return `Error: ${err.message}`;
  }
}

export async function executeGitTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "git_status": {
      const short = args.short !== false;
      return git(cwd, "status", short ? "--short" : "--porcelain");
    }
    case "git_diff": {
      const target = String(args.target ?? "unstaged");
      const path = args.path ? String(args.path) : undefined;
      const stat = Boolean(args.stat);
      const diffArgs = ["diff"];
      if (target === "staged") diffArgs.push("--cached");
      else if (target !== "unstaged") diffArgs.push(target);
      if (stat) diffArgs.push("--stat");
      if (path) diffArgs.push("--", path);
      return git(cwd, ...diffArgs);
    }
    case "git_log": {
      const count = String(Number(args.count ?? 10));
      const oneline = args.oneline !== false;
      const path = args.path ? String(args.path) : undefined;
      const logArgs = ["log", `-${count}`];
      if (oneline) logArgs.push("--oneline");
      if (path) logArgs.push("--", path);
      return git(cwd, ...logArgs);
    }
    case "git_commit": {
      const message = String(args.message ?? "");
      const all = args.all !== false;
      const commitArgs = ["commit"];
      if (all) commitArgs.push("-a");
      commitArgs.push("-m", message);
      return git(cwd, ...commitArgs);
    }
    case "git_checkout": {
      const target = String(args.target ?? "");
      const create = Boolean(args.create);
      const checkoutArgs = ["checkout"];
      if (create) checkoutArgs.push("-b");
      checkoutArgs.push(target);
      return git(cwd, ...checkoutArgs);
    }
    case "git_add": {
      const path = String(args.path ?? ".");
      return git(cwd, "add", path);
    }
    case "git_branch": {
      const action = String(args.action ?? "list");
      const branchName = String(args.name ?? "");
      if (action === "create" && branchName) {
        return git(cwd, "branch", branchName);
      }
      if (action === "delete" && branchName) {
        return git(cwd, "branch", "-D", branchName);
      }
      return git(cwd, "branch", "-a");
    }
    default:
      return `Unknown git tool: ${name}`;
  }
}
