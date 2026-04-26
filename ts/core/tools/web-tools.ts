import { readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";

import { ensureChrysalisDirs, cacheStorePath } from "../paths.js";

const DEFAULT_TTL = 86400;

async function readJsonFile<T>(path: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch {
    return fallback;
  }
}

async function writeJsonFile(path: string, value: unknown): Promise<void> {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function loadCache(cwd: string): Promise<Record<string, any>> {
  await ensureChrysalisDirs(cwd);
  return readJsonFile(cacheStorePath(cwd), {});
}

async function saveCache(cwd: string, cache: Record<string, any>): Promise<void> {
  await ensureChrysalisDirs(cwd);
  await writeJsonFile(cacheStorePath(cwd), cache);
}

export const WEB_TOOL_DEFINITIONS = [
  {
    name: "web_fetch",
    description: "Fetch content from a URL. Returns the response body as text. Supports HTTP/HTTPS. Results are cached with TTL.",
    parameters: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to fetch" },
        method: { type: "string", description: "HTTP method (default GET)" },
        headers: { type: "object", description: "Additional headers as key-value pairs" },
        cache_ttl: { type: "integer", description: "Cache TTL in seconds (0 to disable, default 3600)" }
      },
      required: ["url"]
    }
  },
  {
    name: "web_search",
    description: "Search the web using the Exa API. Requires EXA_API_KEY environment variable. Returns search results with titles, URLs, and snippets.",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query" },
        count: { type: "integer", description: "Number of results (default 5, max 10)" }
      },
      required: ["query"]
    }
  }
];

export async function executeWebTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "web_fetch": {
      const url = String(args.url ?? "");
      if (!url) return "Error: url is required";

      const cacheTtl = Number(args.cache_ttl ?? 3600);
      if (cacheTtl > 0) {
        const cache = await loadCache(cwd);
        const cached = cache[`web:${url}`];
        if (cached && Date.now() / 1000 < cached.createdAt + cached.ttl) {
          return cached.value;
        }
      }

      try {
        const method = String(args.method ?? "GET").toUpperCase();
        const headers: Record<string, string> = args.headers && typeof args.headers === "object"
          ? Object.fromEntries(Object.entries(args.headers as Record<string, unknown>).map(([k, v]) => [k, String(v)]))
          : {};

        const response = await fetch(url, {
          method,
          headers: { "User-Agent": "Chrysalis-Forge/1.0", ...headers },
          signal: AbortSignal.timeout(30000)
        });

        const body = await response.text();
        const result = JSON.stringify({ status: response.status, url: response.url, body: body.slice(0, 50000) }, null, 2);

        if (cacheTtl > 0) {
          const cache = await loadCache(cwd);
          cache[`web:${url}`] = { value: result, createdAt: Math.floor(Date.now() / 1000), ttl: Math.min(cacheTtl, 604800), tags: ["web"] };
          await saveCache(cwd, cache);
        }

        return result;
      } catch (err: any) {
        return `Error fetching ${url}: ${err.message}`;
      }
    }
    case "web_search": {
      const query = String(args.query ?? "");
      if (!query) return "Error: query is required";

      const cache = await loadCache(cwd);
      const cacheKey = `search:${query}`;
      const cached = cache[cacheKey];
      if (cached && Date.now() / 1000 < cached.createdAt + cached.ttl) {
        return cached.value;
      }

      const apiKey = process.env.EXA_API_KEY;
      if (!apiKey) {
        return "Error: EXA_API_KEY environment variable not set. Set it to enable web search.";
      }

      const count = Math.min(Number(args.count ?? 5), 10);
      try {
        const response = await fetch("https://api.exa.ai/search", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey
          },
          body: JSON.stringify({
            query,
            numResults: count,
            type: "auto",
            contents: { text: { maxCharacters: 500 } }
          }),
          signal: AbortSignal.timeout(30000)
        });

        const data = await response.json() as any;
        const results = (data.results ?? []).map((r: any) => ({
          title: r.title,
          url: r.url,
          snippet: r.text?.slice(0, 500) ?? ""
        }));
        const result = JSON.stringify(results, null, 2);

        cache[cacheKey] = { value: result, createdAt: Math.floor(Date.now() / 1000), ttl: DEFAULT_TTL, tags: ["web", "search"] };
        await saveCache(cwd, cache);

        return result;
      } catch (err: any) {
        return `Error searching: ${err.message}`;
      }
    }
    default:
      return `Unknown web tool: ${name}`;
  }
}
