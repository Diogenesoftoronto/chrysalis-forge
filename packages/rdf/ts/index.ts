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

export const toolGroup = { definitions: RDF_TOOL_DEFINITIONS, execute: executeRdfTool };
export { RDF_TOOL_DEFINITIONS, executeRdfTool };
export { rdfLoad, rdfQuery, rdfInsert };
export { vectorAdd, vectorSearch, cosineSimilarity };
