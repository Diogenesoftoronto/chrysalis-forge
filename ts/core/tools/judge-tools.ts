import { ai, ax } from "@ax-llm/ax";

interface ProviderConfig {
  provider: string;
  apiKey: string;
  model?: string;
  baseURL?: string;
}

function resolveProviderConfig(preferredProvider?: string): ProviderConfig | null {
  const configs: Record<string, ProviderConfig | null> = {
    openai: process.env.OPENAI_API_KEY
      ? { provider: "openai", apiKey: process.env.OPENAI_API_KEY, model: process.env.OPENAI_MODEL ?? "gpt-5.4", baseURL: process.env.OPENAI_BASE_URL }
      : null,
    anthropic: process.env.ANTHROPIC_API_KEY
      ? { provider: "anthropic", apiKey: process.env.ANTHROPIC_API_KEY, model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-0" }
      : null,
    "google-gemini": process.env.GEMINI_API_KEY
      ? { provider: "google-gemini", apiKey: process.env.GEMINI_API_KEY, model: process.env.GEMINI_MODEL ?? "gemini-2.5-pro" }
      : null
  };
  if (preferredProvider && configs[preferredProvider]) return configs[preferredProvider];
  return configs.openai ?? configs.anthropic ?? configs["google-gemini"] ?? null;
}

async function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => { timer = setTimeout(() => reject(new Error(`Timed out after ${ms}ms`)), ms); })
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export const JUDGE_TOOL_DEFINITIONS = [
  {
    name: "use_llm_judge",
    description: "Evaluate code or text using an LLM-as-judge. The judge scores quality across configurable criteria and provides a pass/fail verdict with rationale. Falls back to heuristic scoring when LLM is unavailable.",
    parameters: {
      type: "object",
      properties: {
        content: { type: "string", description: "Code or text content to evaluate" },
        criteria: { type: "string", description: "Evaluation criteria (e.g., 'correctness, performance, readability')" },
        task_type: { type: "string", description: "Task type context (refactor/implement/debug/test/research/general)" },
        threshold: { type: "number", description: "Minimum score to pass (0-10, default 7.0)" },
        provider: { type: "string", description: "LLM provider override (openai/anthropic/google-gemini)" }
      },
      required: ["content", "criteria"]
    }
  },
  {
    name: "judge_quality",
    description: "Judge code quality using LLM evaluation. Provides structured feedback on correctness, maintainability, and best practices.",
    parameters: {
      type: "object",
      properties: {
        code: { type: "string", description: "Code to evaluate" },
        language: { type: "string", description: "Programming language" },
        focus: { type: "string", description: "Evaluation focus area (correctness/performance/readability/security)" }
      },
      required: ["code", "language"]
    }
  }
];

export interface JudgeResult {
  score: number;
  passed: boolean;
  verdict: string;
  reasoning: string;
  criteria: Record<string, number>;
  model: string;
}

function heuristicScore(content: string, criteria: string): { score: number; reasoning: string } {
  const lines = content.split("\n").filter(l => l.trim());
  const avgLineLength = lines.reduce((sum, l) => sum + l.length, 0) / Math.max(lines.length, 1);
  const hasComments = content.includes("//") || content.includes("/*") || content.includes("#");
  const hasTests = content.includes("test") || content.includes("Test") || content.includes("assert");
  const hasErrorHandling = content.includes("catch") || content.includes("try") || content.includes("error") || content.includes("Error");
  const hasTypes = content.includes(": string") || content.includes(": number") || content.includes(": boolean") || content.includes("interface") || content.includes("type ");
  
  let score = 5.0;
  if (avgLineLength > 20 && avgLineLength < 120) score += 1.0;
  if (hasComments) score += 0.5;
  if (hasTests) score += 1.0;
  if (hasErrorHandling) score += 1.0;
  if (hasTypes) score += 1.5;
  if (lines.length > 10) score += 0.5;
  
  const reasoning = [
    `Lines: ${lines.length}, Avg line length: ${avgLineLength.toFixed(0)} chars`,
    hasComments ? "Has documentation" : "Missing documentation",
    hasTests ? "Includes tests" : "No tests detected",
    hasErrorHandling ? "Has error handling" : "Missing error handling",
    hasTypes ? "Has type annotations" : "Untyped"
  ].join("; ");
  
  return { score: Math.min(10, Math.max(0, score)), reasoning };
}

export async function judgeWithLLM(
  content: string,
  criteria: string,
  taskType: string,
  threshold: number,
  providerOverride?: string
): Promise<JudgeResult> {
  const provider = resolveProviderConfig(providerOverride);
  if (!provider) {
    const { score, reasoning } = heuristicScore(content, criteria);
    return {
      score,
      passed: score >= threshold,
      verdict: score >= threshold ? "PASS" : "FAIL",
      reasoning: `Heuristic fallback: ${reasoning}`,
      criteria: { overall: score },
      model: "heuristic"
    };
  }

  try {
    const llm = ai({
      name: provider.provider,
      apiKey: provider.apiKey,
      ...(provider.model ? { model: provider.model } : {}),
      ...(provider.baseURL ? { baseURL: provider.baseURL } : {})
    } as any);

    const judge = ax(`
      content:string, criteria:string, taskType:string ->
      score:number,
      verdict:"PASS"|"FAIL",
      reasoning:string,
      criteria:{ correctness?:number, performance?:number, readability?:number, maintainability?:number, security?:number }
    `);

    const result = await withTimeout(
      judge.forward(llm as any, { content, criteria, taskType }),
      30000
    );

    return {
      score: result.score ?? 5.0,
      passed: (result.score ?? 5.0) >= threshold,
      verdict: result.verdict ?? (result.score ?? 5.0) >= threshold ? "PASS" : "FAIL",
      reasoning: result.reasoning ?? "No reasoning provided",
      criteria: result.criteria ?? { overall: result.score ?? 5.0 },
      model: provider.model ?? provider.provider
    };
  } catch (err) {
    const { score, reasoning } = heuristicScore(content, criteria);
    return {
      score,
      passed: score >= threshold,
      verdict: score >= threshold ? "PASS" : "FAIL",
      reasoning: `LLM error (${err instanceof Error ? err.message : "unknown"}), heuristic fallback: ${reasoning}`,
      criteria: { overall: score },
      model: "heuristic-fallback"
    };
  }
}

export async function executeJudgeTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "use_llm_judge": {
      const content = String(args.content ?? "");
      const criteria = String(args.criteria ?? "correctness, quality");
      const taskType = String(args.task_type ?? "general");
      const threshold = Number(args.threshold ?? 7.0);
      const provider = args.provider ? String(args.provider) : undefined;
      
      if (!content) return "Error: content is required";
      
      const result = await judgeWithLLM(content, criteria, taskType, threshold, provider);
      return JSON.stringify(result, null, 2);
    }
    case "judge_quality": {
      const code = String(args.code ?? "");
      const language = String(args.language ?? "unknown");
      const focus = String(args.focus ?? "correctness");
      
      if (!code) return "Error: code is required";
      
      const result = await judgeWithLLM(code, focus, `quality evaluation (${language})`, 7.0);
      return JSON.stringify(result, null, 2);
    }
    default:
      return `Unknown judge tool: ${name}`;
  }
}
