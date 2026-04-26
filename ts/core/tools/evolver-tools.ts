import { globalToolRegistry } from "./tool-registry.js";

export const EVOLVER_TOOL_DEFINITIONS = [
  {
    name: "evolve_tool",
    description: "Evolve a registered tool's description or parameters using feedback-driven mutation. The tool definition is modified, gated by novelty scoring, and archived as a variant. Part of the tool evolutionary harness.",
    parameters: {
      type: "object",
      properties: {
        tool_name: { type: "string", description: "Name of the tool to evolve" },
        feedback: { type: "string", description: "Feedback describing how the tool should improve" },
        field: { type: "string", description: "Which field to evolve: description, parameters, or both (default both)" },
        threshold: { type: "number", description: "Novelty threshold 0-1 (default 0.25)" }
      },
      required: ["tool_name", "feedback"]
    }
  },
  {
    name: "list_tools",
    description: "List all registered LLM-callable tools with their enabled/disabled status and evolution state.",
    parameters: {
      type: "object",
      properties: {
        filter: { type: "string", description: "Filter by tool name substring" }
      },
      required: []
    }
  },
  {
    name: "tool_variants",
    description: "List evolution variants for a specific tool or all tools.",
    parameters: {
      type: "object",
      properties: {
        tool_name: { type: "string", description: "Tool name to list variants for (omit for all)" },
        active_only: { type: "boolean", description: "Only show active variants" }
      },
      required: []
    }
  },
  {
    name: "select_tool_variant",
    description: "Select a specific variant as the active version of a tool.",
    parameters: {
      type: "object",
      properties: {
        tool_name: { type: "string", description: "Tool name" },
        variant_id: { type: "string", description: "Variant ID to activate" }
      },
      required: ["tool_name", "variant_id"]
    }
  },
  {
    name: "enable_tool",
    description: "Enable a previously disabled tool.",
    parameters: {
      type: "object",
      properties: {
        tool_name: { type: "string", description: "Tool name to enable" }
      },
      required: ["tool_name"]
    }
  },
  {
    name: "disable_tool",
    description: "Disable a tool (cannot be called while disabled).",
    parameters: {
      type: "object",
      properties: {
        tool_name: { type: "string", description: "Tool name to disable" }
      },
      required: ["tool_name"]
    }
  },
  {
    name: "tool_stats",
    description: "Get tool registry statistics: total tools, enabled/disabled counts, and evolution state.",
    parameters: {
      type: "object",
      properties: {}
    }
  },
  {
    name: "tool_evolution_stats",
    description: "Get detailed tool evolution statistics including variant counts per tool.",
    parameters: {
      type: "object",
      properties: {}
    }
  }
];

export async function executeEvolverTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  globalToolRegistry.setCwd(cwd);

  switch (name) {
    case "evolve_tool": {
      const toolName = String(args.tool_name ?? "");
      const feedback = String(args.feedback ?? "");
      const field = args.field ? String(args.field) as "description" | "parameters" | "both" : "both";
      const threshold = Number(args.threshold ?? 0.25);

      if (!toolName || !feedback) {
        return JSON.stringify({ error: "tool_name and feedback are required" }, null, 2);
      }

      const result = await globalToolRegistry.evolveToolDefinition(toolName, feedback, field, threshold);
      if (!result.success) {
        return JSON.stringify({ error: result.error }, null, 2);
      }

      return JSON.stringify({
        toolName,
        variantId: result.variant?.id,
        active: result.variant?.active,
        noveltyScore: result.variant?.noveltyScore,
        rejected: !result.variant?.active,
        model: result.variant?.model
      }, null, 2);
    }

    case "list_tools": {
      const filter = args.filter ? String(args.filter).toLowerCase() : "";
      const tools = globalToolRegistry.listTools();
      const filtered = filter
        ? tools.filter(t => t.name.toLowerCase().includes(filter))
        : tools;
      return JSON.stringify({
        total: filtered.length,
        tools: filtered
      }, null, 2);
    }

    case "tool_variants": {
      const toolName = args.tool_name ? String(args.tool_name) : undefined;
      const activeOnly = Boolean(args.active_only);
      const variants = globalToolRegistry.getVariants(toolName);
      const filtered = activeOnly ? variants.filter(v => v.active) : variants;
      return JSON.stringify({
        toolName: toolName ?? "all",
        count: filtered.length,
        variants: filtered.map(v => ({
          id: v.id,
          toolName: v.toolName,
          active: v.active,
          noveltyScore: v.noveltyScore,
          score: v.score,
          model: v.model,
          createdAt: v.createdAt,
          feedback: v.feedback.slice(0, 100)
        }))
      }, null, 2);
    }

    case "select_tool_variant": {
      const toolName = String(args.tool_name ?? "");
      const variantId = String(args.variant_id ?? "");

      if (!toolName || !variantId) {
        return JSON.stringify({ error: "tool_name and variant_id are required" }, null, 2);
      }

      const ok = globalToolRegistry.selectVariant(toolName, variantId);
      return JSON.stringify({ success: ok, toolName, variantId }, null, 2);
    }

    case "enable_tool": {
      const toolName = String(args.tool_name ?? "");
      if (!toolName) return JSON.stringify({ error: "tool_name is required" }, null, 2);
      const ok = globalToolRegistry.enableTool(toolName);
      return JSON.stringify({ success: ok, toolName, enabled: ok }, null, 2);
    }

    case "disable_tool": {
      const toolName = String(args.tool_name ?? "");
      if (!toolName) return JSON.stringify({ error: "tool_name is required" }, null, 2);
      const ok = globalToolRegistry.disableTool(toolName);
      return JSON.stringify({ success: ok, toolName, enabled: !ok }, null, 2);
    }

    case "tool_stats": {
      const counts = globalToolRegistry.getToolCount();
      return JSON.stringify(counts, null, 2);
    }

    case "tool_evolution_stats": {
      return globalToolRegistry.getEvolutionStats();
    }

    default:
      return `Unknown evolver tool: ${name}`;
  }
}
