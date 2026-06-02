import { RDF_TOOL_DEFINITIONS, executeRdfTool } from "./rdf-tools.js";
import { rdfLoad, rdfQuery, rdfInsert } from "./rdf-store.js";
import { vectorAdd, vectorSearch, cosineSimilarity } from "./vector-store.js";

export function register(pi: any): void {
  for (const def of RDF_TOOL_DEFINITIONS) {
    pi.registerTool({
      name: def.name,
      label: def.name.replace(/_/g, " "),
      description: def.description,
      parameters: def.parameters,
      async execute(_toolCallId: string, params: any, _signal: any, _onUpdate: any, ctx: any): Promise<{ content: Array<{ type: string; text: string }> }> {
        try {
          const result = await executeRdfTool(ctx.cwd, def.name, params);
          return { content: [{ type: "text", text: result }] };
        } catch (err) {
          return { content: [{ type: "text", text: `Error: ${err instanceof Error ? err.message : String(err)}` }] };
        }
      }
    });
  }
}

function argsList(args: string | string[]): string[] {
  return Array.isArray(args) ? args : String(args ?? "").trim().split(/\s+/).filter(Boolean);
}

export const commands = [
  {
    name: "rdf-load",
    description: "Load an N-triples file into an RDF named graph.",
    handler: async (args: string | string[], ctx: any): Promise<void> => {
      const [path, id] = argsList(args);
      if (!path || !id) {
        ctx.ui.notify("Usage: /rdf-load <path> <id>", "info");
        return;
      }
      ctx.ui.notify(String(await executeRdfTool(ctx.cwd, "rdf_load", { path, id })), "info");
    }
  },
  {
    name: "rdf-query",
    description: "Query the RDF knowledge graph.",
    handler: async (args: string | string[], ctx: any): Promise<void> => {
      const query = argsList(args).join(" ").trim();
      if (!query) {
        ctx.ui.notify("Usage: /rdf-query <query>", "info");
        return;
      }
      ctx.ui.notify(String(await executeRdfTool(ctx.cwd, "rdf_query", { query })), "info");
    }
  },
  {
    name: "rdf-insert",
    description: "Insert a triple into the RDF store.",
    handler: async (args: string | string[], ctx: any): Promise<void> => {
      const [subject, predicate, object, graph] = argsList(args);
      if (!subject || !predicate || !object) {
        ctx.ui.notify("Usage: /rdf-insert <subject> <predicate> <object> [graph]", "info");
        return;
      }
      ctx.ui.notify(String(await executeRdfTool(ctx.cwd, "rdf_insert", { subject, predicate, object, graph: graph ?? "default" })), "info");
    }
  }
];

export const toolGroup = { definitions: RDF_TOOL_DEFINITIONS, execute: executeRdfTool };
export { RDF_TOOL_DEFINITIONS, executeRdfTool };
export { rdfLoad, rdfQuery, rdfInsert };
export { vectorAdd, vectorSearch, cosineSimilarity };
