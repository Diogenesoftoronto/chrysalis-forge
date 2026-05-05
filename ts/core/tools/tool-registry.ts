import { EventEmitter } from "node:events";
import { getActiveToolVariant, evolveTool, listToolVariants, archiveToolVariant, selectToolVariant, toolEvolutionStats, type ToolVariant } from "./tool-evolution.js";

export interface ToolDefinition {
  name: string;
  description: string;
  parameters: {
    type: string;
    properties: Record<string, unknown>;
    required?: string[];
  };
  execute?: ToolExecutor;
}

export type ToolExecutor = (
  cwd: string,
  name: string,
  args: Record<string, unknown>
) => Promise<string>;

export interface RegisteredTool {
  definition: ToolDefinition;
  executor: ToolExecutor;
  enabled: boolean;
  version: number;
  variants: ToolVariant[];
}

class EvolvableToolRegistry extends EventEmitter {
  private tools: Map<string, RegisteredTool> = new Map();
  private cwd: string = process.cwd();

  setCwd(cwd: string): void {
    this.cwd = cwd;
  }

  registerTool(def: ToolDefinition, executor: ToolExecutor): void {
    const existing = this.tools.get(def.name);
    const tool: RegisteredTool = {
      definition: def,
      executor,
      enabled: true,
      version: existing ? existing.version + 1 : 1,
      variants: []
    };
    this.tools.set(def.name, tool);
    this.emit("tool:registered", { name: def.name, version: tool.version });
  }

  unregisterTool(name: string): boolean {
    const deleted = this.tools.delete(name);
    if (deleted) this.emit("tool:unregistered", { name });
    return deleted;
  }

  enableTool(name: string): boolean {
    const tool = this.tools.get(name);
    if (!tool) return false;
    tool.enabled = true;
    this.emit("tool:enabled", { name });
    return true;
  }

  disableTool(name: string): boolean {
    const tool = this.tools.get(name);
    if (!tool) return false;
    tool.enabled = false;
    this.emit("tool:disabled", { name });
    return true;
  }

  getTool(name: string): RegisteredTool | undefined {
    return this.tools.get(name);
  }

  getActiveDefinition(name: string): ToolDefinition | undefined {
    const evolved = getActiveToolVariant(this.cwd, name);
    if (evolved) return evolved;
    return this.tools.get(name)?.definition;
  }

  async evolveToolDefinition(
    name: string,
    feedback: string,
    field?: "description" | "parameters" | "both",
    threshold = 0.25
  ): Promise<{ success: boolean; variant?: ToolVariant; error?: string }> {
    const tool = this.tools.get(name);
    if (!tool) return { success: false, error: `Tool '${name}' not found` };

    try {
      const { variant, rejected } = await evolveTool(
        this.cwd,
        name,
        tool.definition,
        feedback,
        field,
        threshold
      );

      const registered = this.tools.get(name);
      if (registered) registered.variants.push(variant);

      this.emit("tool:evolved", { name, variant, rejected });
      return { success: true, variant };
    } catch (err) {
      return { success: false, error: err instanceof Error ? err.message : "Unknown error" };
    }
  }

  selectVariant(name: string, variantId: string): boolean {
    const ok = selectToolVariant(this.cwd, variantId);
    if (ok) this.emit("tool:variant-selected", { name, variantId });
    return ok;
  }

  archiveVariant(variantId: string): boolean {
    const ok = archiveToolVariant(this.cwd, variantId);
    if (ok) this.emit("tool:variant-archived", { variantId });
    return ok;
  }

  getVariants(name?: string): ToolVariant[] {
    return listToolVariants(this.cwd, name);
  }

  listTools(): Array<{ name: string; enabled: boolean; version: number; hasEvolvedVariant: boolean }> {
    const variants = listToolVariants(this.cwd);
    const variantNames = new Set(variants.map(v => v.toolName));
    return Array.from(this.tools.values()).map(t => ({
      name: t.definition.name,
      enabled: t.enabled,
      version: t.version,
      hasEvolvedVariant: variantNames.has(t.definition.name)
    }));
  }

  getEvolutionStats(): string {
    return toolEvolutionStats(this.cwd);
  }

  async execute(
    name: string,
    args: Record<string, unknown>
  ): Promise<string> {
    const tool = this.tools.get(name);
    if (!tool) throw new Error(`Tool '${name}' not found`);
    if (!tool.enabled) throw new Error(`Tool '${name}' is disabled`);

    const def = this.getActiveDefinition(name);
    if (!def) throw new Error(`No active definition for '${name}'`);

    return tool.executor(this.cwd, name, args);
  }

  hasTool(name: string): boolean {
    return this.tools.has(name);
  }

  getToolCount(): { total: number; enabled: number; disabled: number } {
    let enabled = 0, disabled = 0;
    for (const t of this.tools.values()) {
      if (t.enabled) enabled++; else disabled++;
    }
    return { total: this.tools.size, enabled, disabled };
  }
}

export const globalToolRegistry = new EvolvableToolRegistry();
