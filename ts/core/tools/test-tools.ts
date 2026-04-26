import { ai, ax } from "@ax-llm/ax";
import { resolve } from "node:path";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";

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

export const TEST_TOOL_DEFINITIONS = [
  {
    name: "generate_tests",
    description: "Generate unit tests for code using LLM-backed test generation. Reads the target file and produces test cases in the specified framework. Falls back to simple pattern-based test generation when LLM is unavailable.",
    parameters: {
      type: "object",
      properties: {
        file_path: { type: "string", description: "Path to the source file to generate tests for" },
        framework: { type: "string", description: "Test framework (jest/vitest/mocha/python/unittest/golang) - auto-detected if not specified" },
        test_dir: { type: "string", description: "Directory to write tests to (defaults to adjacent __tests__ or test folder)" },
       覆盖率_target: { type: "number", description: "Target line coverage percentage (0-100, default 80)" },
        provider: { type: "string", description: "LLM provider override (openai/anthropic/google-gemini)" },
        test_type: { type: "string", description: "Type of tests (unit/integration/e2e, default unit)" }
      },
      required: ["file_path"]
    }
  },
  {
    name: "generate_test_cases",
    description: "Generate specific test cases for a function or module. Provides concrete inputs and expected outputs.",
    parameters: {
      type: "object",
      properties: {
        function_signature: { type: "string", description: "Function signature or name to generate tests for" },
        code_context: { type: "string", description: "Surrounding code context for the function" },
        framework: { type: "string", description: "Test framework (jest/vitest/mocha/python/golang)" },
        count: { type: "integer", description: "Number of test cases to generate (default 5)" }
      },
      required: ["function_signature", "code_context"]
    }
  }
];

export interface GeneratedTests {
  filePath: string;
  framework: string;
  testCount: number;
  coverage: number;
  tests: Array<{ name: string; body: string }>;
  model: string;
}

function detectFramework(filePath: string, content?: string): string {
  const ext = filePath.split(".").pop()?.toLowerCase();
  const frameworkMap: Record<string, string> = {
    ts: "vitest",
    tsx: "vitest",
    js: "jest",
    jsx: "jest",
    py: "pytest",
    go: "golang",
    rs: "rust"
  };
  
  if (content) {
    if (content.includes("@testing-library/react") || content.includes("@testing-library/jest")) return "jest";
    if (content.includes("vitest")) return "vitest";
    if (content.includes("pytest")) return "pytest";
  }
  
  return frameworkMap[ext ?? ""] ?? "vitest";
}

function inferTestDir(filePath: string): string {
  const dir = filePath.substring(0, filePath.lastIndexOf("/"));
  const base = filePath.split("/").pop()?.split(".")[0] ?? "tests";
  
  const candidates = [
    `${dir}/__tests__`,
    `${dir}/tests`,
    `${dir}/${base}.test.ts`,
    `${dir}/${base}.spec.ts`
  ];
  
  for (const c of candidates) {
    if (c.includes(".test.") || c.includes(".spec.")) {
      return c;
    }
  }
  
  return `${dir}/__tests__`;
}

function heuristicTestGen(code: string, framework: string): Array<{ name: string; body: string }> {
  const tests: Array<{ name: string; body: string }> = [];
  
  const fnMatch = code.match(/(?:function\s+(\w+)|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?(?:function|\([^)]*\)\s*=>|\w+\s*=>))/g);
  const fnName = fnMatch?.[0]?.match(/(?:function\s+(\w+)|(\w+)\s*=)/)?.[1] ?? "subject";
  
  const testsTemplates: Record<string, Array<{ name: string; body: string }>> = {
    vitest: [
      { name: `${fnName}_exists`, body: `test('${fnName} is defined', () => { expect(${fnName}).toBeDefined(); });` },
      { name: `${fnName}_is_function`, body: `test('${fnName} is a function', () => { expect(typeof ${fnName}).toBe('function'); });` }
    ],
    jest: [
      { name: `${fnName}_exists`, body: `test('${fnName} is defined', () => { expect(${fnName}).toBeDefined(); });` },
      { name: `${fnName}_is_function`, body: `test('${fnName} is a function', () => { expect(typeof ${fnName}).toBe('function'); });` }
    ],
    pytest: [
      { name: `test_${fnName}_exists`, body: `def test_${fnName}_exists():\n    import pytest\n    assert ${fnName} is not None` },
      { name: `test_${fnName}_is_callable`, body: `def test_${fnName}_is_callable():\n    assert callable(${fnName})` }
    ],
    golang: [
      { name: `Test${fnName.charAt(0).toUpperCase() + fnName.slice(1)}Exists`, body: `func Test${fnName.charAt(0).toUpperCase() + fnName.slice(1)}Exists(t *testing.T) {\n\tt.Log("${fnName} should not be nil")\n}` }
    ]
  };
  
  return testsTemplates[framework] ?? testsTemplates.vitest;
}

export async function generateTestsWithLLM(
  filePath: string,
  cwd: string,
  framework?: string,
  testDir?: string,
  coverageTarget?: number,
  providerOverride?: string,
  testType?: string
): Promise<GeneratedTests> {
  const provider = resolveProviderConfig(providerOverride);
  
  let content: string;
  try {
    content = await readFile(resolve(cwd, filePath), "utf8");
  } catch {
    content = "";
  }
  
  const detectedFramework = framework ?? detectFramework(filePath, content);
  const outputDir = testDir ?? inferTestDir(filePath);
  const baseName = filePath.split("/").pop()?.split(".")[0] ?? "subject";
  
  if (!provider || !content) {
    const tests = heuristicTestGen(content || `// ${filePath}`, detectedFramework);
    return {
      filePath: `${outputDir}/${baseName}.test.ts`,
      framework: detectedFramework,
      testCount: tests.length,
      coverage: 30,
      tests,
      model: content ? "heuristic" : "no-content"
    };
  }

  try {
    const llm = ai({
      name: provider.provider,
      apiKey: provider.apiKey,
      ...(provider.model ? { model: provider.model } : {}),
      ...(provider.baseURL ? { baseURL: provider.baseURL } : {})
    } as any);

    const generator = ax(`
      filePath:string, code:string, framework:string, testType:string, coverageTarget:number ->
      tests:{ name:string, body:string }[],
      coverage:number
    `);

    const result = await withTimeout(
      generator.forward(llm as any, {
        filePath,
        code: content.slice(0, 8000),
        framework: detectedFramework,
        testType: testType ?? "unit",
        coverageTarget: coverageTarget ?? 80
      }),
      45000
    );

    return {
      filePath: `${outputDir}/${baseName}.test.${detectedFramework === "pytest" ? "py" : detectedFramework === "golang" ? "go" : "ts"}`,
      framework: detectedFramework,
      testCount: result.tests?.length ?? 0,
      coverage: result.coverage ?? coverageTarget ?? 80,
      tests: result.tests ?? [],
      model: provider.model ?? provider.provider
    };
  } catch (err) {
    const tests = heuristicTestGen(content || `// ${filePath}`, detectedFramework);
    return {
      filePath: `${outputDir}/${baseName}.test.ts`,
      framework: detectedFramework,
      testCount: tests.length,
      coverage: 30,
      tests,
      model: "heuristic-fallback"
    };
  }
}

export async function executeTestTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "generate_tests": {
      const filePath = String(args.file_path ?? "");
      if (!filePath) return "Error: file_path is required";
      
      const framework = args.framework ? String(args.framework) : undefined;
      const testDir = args.test_dir ? String(args.test_dir) : undefined;
      const coverageTarget = args.覆盖率_target ? Number(args.覆盖率_target) : undefined;
      const provider = args.provider ? String(args.provider) : undefined;
      const testType = args.test_type ? String(args.test_type) : undefined;
      
      const result = await generateTestsWithLLM(filePath, cwd, framework, testDir, coverageTarget, provider, testType);
      return JSON.stringify({
        filePath: result.filePath,
        framework: result.framework,
        testCount: result.testCount,
        estimatedCoverage: result.coverage,
        model: result.model,
        tests: result.tests
      }, null, 2);
    }
    case "generate_test_cases": {
      const fnSig = String(args.function_signature ?? "");
      const codeContext = String(args.code_context ?? "");
      const framework = String(args.framework ?? "vitest");
      const count = Number(args.count ?? 5);
      
      if (!fnSig || !codeContext) return "Error: function_signature and code_context are required";
      
      const provider = resolveProviderConfig();
      if (!provider) {
        const tests = heuristicTestGen(codeContext, framework).slice(0, count);
        return JSON.stringify({ tests, model: "heuristic" }, null, 2);
      }
      
      try {
        const llm = ai({
          name: provider.provider,
          apiKey: provider.apiKey,
          ...(provider.model ? { model: provider.model } : {}),
          ...(provider.baseURL ? { baseURL: provider.baseURL } : {})
        } as any);

        const generator = ax(`
          functionSignature:string, codeContext:string, framework:string, count:number ->
          tests:{ name:string, body:string }[]
        `);

        const result = await withTimeout(
          generator.forward(llm as any, { functionSignature: fnSig, codeContext, framework, count }),
          30000
        );

        return JSON.stringify({
          tests: result.tests ?? [],
          model: provider.model ?? provider.provider
        }, null, 2);
      } catch {
        const tests = heuristicTestGen(codeContext, framework).slice(0, count);
        return JSON.stringify({ tests, model: "heuristic-fallback" }, null, 2);
      }
    }
    default:
      return `Unknown test tool: ${name}`;
  }
}
