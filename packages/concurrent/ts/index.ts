import { SUB_AGENT_TOOL_DEFINITIONS, executeSubAgentTool } from "./sub-agent-tools.js";

export function register(pi: any): void {
  for (const def of SUB_AGENT_TOOL_DEFINITIONS) {
    pi.registerTool({
      name: def.name,
      label: def.name.replace(/_/g, " "),
      description: def.description,
      parameters: def.parameters,
      async execute(_toolCallId: string, params: any, _signal: any, _onUpdate: any, ctx: any): Promise<{ content: Array<{ type: string; text: string }> }> {
        try {
          const result = await executeSubAgentTool(ctx.cwd, def.name, params);
          return { content: [{ type: "text", text: result }] };
        } catch (err) {
          return { content: [{ type: "text", text: `Error: ${err instanceof Error ? err.message : String(err)}` }] };
        }
      }
    });
  }
}

export const toolGroup = { definitions: SUB_AGENT_TOOL_DEFINITIONS, execute: executeSubAgentTool };
export { SUB_AGENT_TOOL_DEFINITIONS, executeSubAgentTool };
