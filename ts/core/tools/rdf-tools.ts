import { rdfLoad, rdfQuery, rdfInsert } from "../stores/rdf-store.js";

export const RDF_TOOL_DEFINITIONS = [
  {
    name: "rdf_load",
    description: "Load triples/quads from a file into a named graph.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path to the file containing triples/quads" },
        id: { type: "string", description: "Graph ID/Name to load into" }
      },
      required: ["path", "id"]
    }
  },
  {
    name: "rdf_query",
    description: "Query the Knowledge Graph. Returns results with subject, predicate, object, graph, and timestamp. Use pattern syntax like '?s predicate object' or '?s ?p object'.",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "Query string (e.g. '?s p o' or '?s ?p o ?g')" },
        id: { type: "string", description: "Default Graph ID to query (optional)" }
      },
      required: ["query"]
    }
  },
  {
    name: "rdf_insert",
    description: "Insert a single triple or quad with an optional timestamp.",
    parameters: {
      type: "object",
      properties: {
        subject: { type: "string" },
        predicate: { type: "string" },
        object: { type: "string" },
        graph: { type: "string", description: "Graph Name (optional, defaults to 'default')" },
        timestamp: { type: "integer", description: "Timestamp (epoch seconds). Defaults to now." }
      },
      required: ["subject", "predicate", "object"]
    }
  }
];

export async function executeRdfTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "rdf_load":
      return rdfLoad(cwd, String(args.path ?? ""), String(args.id ?? "default"));
    case "rdf_query":
      return rdfQuery(cwd, String(args.query ?? ""), args.id != null ? String(args.id) : undefined);
    case "rdf_insert":
      return rdfInsert(
        cwd,
        String(args.subject ?? ""),
        String(args.predicate ?? ""),
        String(args.object ?? ""),
        String(args.graph ?? "default"),
        args.timestamp != null ? Number(args.timestamp) : undefined
      );
    default:
      return `Unknown RDF tool: ${name}`;
  }
}
