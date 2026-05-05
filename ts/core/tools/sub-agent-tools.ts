import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { resolve, join } from "node:path";
import { readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { ensureChrysalisDirs, stateDir } from "../paths.js";

const execFileAsync = promisify(execFile);

interface SubTask {
  id: string;
  description: string;
  profile: string;
  status: "pending" | "running" | "done" | "failed";
  pid?: number;
  output?: string;
  exitCode?: number;
  startedAt?: number;
  finishedAt?: number;
}

async function loadTasks(cwd: string): Promise<Record<string, SubTask>> {
  await ensureChrysalisDirs(cwd);
  const path = join(stateDir(cwd), "sub-tasks.json");
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch {
    return {};
  }
}

async function saveTasks(cwd: string, tasks: Record<string, SubTask>): Promise<void> {
  await ensureChrysalisDirs(cwd);
  const path = join(stateDir(cwd), "sub-tasks.json");
  await writeFile(path, `${JSON.stringify(tasks, null, 2)}\n`, "utf8");
}

function taskId(): string {
  return `T-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

export const SUB_AGENT_TOOL_DEFINITIONS = [
  {
    name: "spawn_task",
    description: "Spawn a sub-agent task. The task runs as a separate Chrysalis process with a specific tool profile. Returns a task ID for tracking.",
    parameters: {
      type: "object",
      properties: {
        description: { type: "string", description: "Task description for the sub-agent" },
        profile: { type: "string", description: "Tool profile: 'editor' (file ops), 'researcher' (read-only), 'vcs' (git/jj), or 'all' (default 'all')" }
      },
      required: ["description"]
    }
  },
  {
    name: "await_task",
    description: "Wait for a spawned task to complete and return its output. Blocks until the task finishes or times out.",
    parameters: {
      type: "object",
      properties: {
        task_id: { type: "string", description: "Task ID returned by spawn_task" },
        timeout_ms: { type: "integer", description: "Timeout in milliseconds (default 60000)" }
      },
      required: ["task_id"]
    }
  },
  {
    name: "task_status",
    description: "Check the status of a spawned task without waiting. Returns current status and any partial output.",
    parameters: {
      type: "object",
      properties: {
        task_id: { type: "string", description: "Task ID to check" }
      },
      required: ["task_id"]
    }
  }
];

export async function executeSubAgentTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "spawn_task": {
      const description = String(args.description ?? "");
      if (!description) return "Error: description is required";

      const profile = String(args.profile ?? "all");
      const id = taskId();

      const tasks = await loadTasks(cwd);
      tasks[id] = {
        id,
        description,
        profile,
        status: "running",
        startedAt: Math.floor(Date.now() / 1000)
      };

      const cmd = `chrysalis shell --prompt "${description.replace(/"/g, '\\"')}" --profile ${profile} --non-interactive`;
      const child = execFile("sh", ["-c", cmd], { cwd, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
        void (async () => {
          const tasks = await loadTasks(cwd);
          if (tasks[id]) {
            tasks[id].status = err ? "failed" : "done";
            tasks[id].output = stdout?.slice(0, 50000) ?? "";
            tasks[id].exitCode = err ? 1 : 0;
            tasks[id].finishedAt = Math.floor(Date.now() / 1000);
            if (stderr) tasks[id].output += `\n--- stderr ---\n${stderr.slice(0, 10000)}`;
            await saveTasks(cwd, tasks);
          }
        })();
      });

      tasks[id].pid = child.pid;
      await saveTasks(cwd, tasks);

      return JSON.stringify({ task_id: id, status: "running" }, null, 2);
    }
    case "await_task": {
      const taskId_ = String(args.task_id ?? "");
      if (!taskId_) return "Error: task_id is required";
      const timeoutMs = Number(args.timeout_ms ?? 60000);

      const startTime = Date.now();
      while (Date.now() - startTime < timeoutMs) {
        const tasks = await loadTasks(cwd);
        const task = tasks[taskId_];
        if (!task) return `Error: task ${taskId_} not found`;
        if (task.status === "done" || task.status === "failed") {
          return JSON.stringify({
            task_id: task.id,
            status: task.status,
            exit_code: task.exitCode,
            duration_s: (task.finishedAt ?? 0) - (task.startedAt ?? 0),
            output: task.output?.slice(0, 50000)
          }, null, 2);
        }
        await new Promise((r) => setTimeout(r, 1000));
      }

      const tasks = await loadTasks(cwd);
      const task = tasks[taskId_];
      return JSON.stringify({
        task_id: taskId_,
        status: task?.status ?? "unknown",
        output: task?.output?.slice(0, 50000),
        timed_out: true
      }, null, 2);
    }
    case "task_status": {
      const taskId_ = String(args.task_id ?? "");
      if (!taskId_) return "Error: task_id is required";

      const tasks = await loadTasks(cwd);
      const task = tasks[taskId_];
      if (!task) return `Error: task ${taskId_} not found`;

      return JSON.stringify({
        task_id: task.id,
        status: task.status,
        profile: task.profile,
        started_at: task.startedAt,
        finished_at: task.finishedAt,
        output: task.status === "done" || task.status === "failed" ? task.output?.slice(0, 50000) : undefined
      }, null, 2);
    }
    default:
      return `Unknown sub-agent tool: ${name}`;
  }
}
