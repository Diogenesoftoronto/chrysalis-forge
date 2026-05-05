import architect from "@pi/prompts/architect.md?raw";
import review from "@pi/prompts/review.md?raw";
import ship from "@pi/prompts/ship.md?raw";
import axWorkflows from "@pi/skills/ax-workflows/SKILL.md?raw";
import terminalFirst from "@pi/skills/terminal-first/SKILL.md?raw";

export interface PromptEntry {
  id: string;
  title: string;
  body: string;
}

export const prompts: PromptEntry[] = [
  { id: "architect", title: "Architect", body: architect },
  { id: "review", title: "Review", body: review },
  { id: "ship", title: "Ship", body: ship },
];

export const skills: PromptEntry[] = [
  { id: "ax-workflows", title: "Ax Workflows", body: axWorkflows },
  { id: "terminal-first", title: "Terminal First", body: terminalFirst },
];

export function buildSystemPrompt(promptId: string, task: string): string {
  const p = prompts.find((x) => x.id === promptId) ?? prompts[0];
  return p.body.replace("$@", task || "(see user message)");
}

export function stripFrontmatter(md: string): string {
  if (!md.startsWith("---")) return md;
  const end = md.indexOf("\n---", 3);
  if (end === -1) return md;
  return md.slice(end + 4).replace(/^\s+/, "");
}
