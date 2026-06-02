import { CACHE_TOOL_DEFINITIONS, executeCacheTool } from "./cache-tools.js";
import { cacheStats, cacheCleanup, cacheClear, cacheGet, cacheSet, cacheInvalidate, cacheInvalidateByTag } from "./cache-store.js";

export function register(pi: any): void {
  for (const def of CACHE_TOOL_DEFINITIONS) {
    pi.registerTool({
      name: def.name,
      label: def.name.replace(/_/g, " "),
      description: def.description,
      parameters: def.parameters,
      async execute(_toolCallId: string, params: any, _signal: any, _onUpdate: any, ctx: any): Promise<{ content: Array<{ type: string; text: string }> }> {
        try {
          const result = await executeCacheTool(ctx.cwd, def.name, params);
          return { content: [{ type: "text", text: result }] };
        } catch (err) {
          return { content: [{ type: "text", text: `Error: ${err instanceof Error ? err.message : String(err)}` }] };
        }
      }
    });
  }
}

export const commands = [
  {
    name: "cache-stats",
    description: "Show web cache statistics.",
    handler: async (_args: string | string[], ctx: any): Promise<void> => {
      const stats = await cacheStats(ctx.cwd);
      ctx.ui.notify(`cache: total=${stats.total} valid=${stats.valid} expired=${stats.expired}`, "info");
    }
  }
];

export const toolGroup = { definitions: CACHE_TOOL_DEFINITIONS, execute: executeCacheTool };
export { CACHE_TOOL_DEFINITIONS, executeCacheTool };
export { cacheStats, cacheCleanup, cacheClear, cacheGet, cacheSet, cacheInvalidate, cacheInvalidateByTag };
