import { storeCreate, storeDelete, storeList, storeGet, storeSet, storeRemove, storeDump, storeDescribe } from "../stores/store-registry.js";

export const STORE_TOOL_DEFINITIONS = [
  {
    name: "store_create",
    description: "Create a new dynamic store. Supports key-value (kv), append-only log (log), unique set (set), and counter (counter) store types.",
    parameters: {
      type: "object",
      properties: {
        name: { type: "string", description: "Store name" },
        kind: { type: "string", description: "Store type: kv, log, set, or counter" },
        namespace: { type: "string", description: "Namespace (default 'default')" },
        description: { type: "string", description: "Human-readable description" }
      },
      required: ["name", "kind"]
    }
  },
  {
    name: "store_list",
    description: "List dynamic stores, optionally filtered by namespace.",
    parameters: {
      type: "object",
      properties: {
        namespace: { type: "string", description: "Filter by namespace" }
      },
      required: []
    }
  },
  {
    name: "store_get",
    description: "Get a value from a dynamic store.",
    parameters: {
      type: "object",
      properties: {
        name: { type: "string", description: "Store name" },
        field: { type: "string", description: "Key/field to get" },
        namespace: { type: "string", description: "Namespace" }
      },
      required: ["name", "field"]
    }
  },
  {
    name: "store_set",
    description: "Set a value in a dynamic store.",
    parameters: {
      type: "object",
      properties: {
        name: { type: "string", description: "Store name" },
        field: { type: "string", description: "Key/field to set" },
        value: { type: "string", description: "Value to store" },
        namespace: { type: "string", description: "Namespace" }
      },
      required: ["name", "field", "value"]
    }
  },
  {
    name: "store_rm",
    description: "Remove a key from a dynamic store.",
    parameters: {
      type: "object",
      properties: {
        name: { type: "string", description: "Store name" },
        field: { type: "string", description: "Key/field to remove" },
        namespace: { type: "string", description: "Namespace" }
      },
      required: ["name", "field"]
    }
  },
  {
    name: "store_dump",
    description: "Dump all contents of a dynamic store.",
    parameters: {
      type: "object",
      properties: {
        name: { type: "string", description: "Store name" },
        namespace: { type: "string", description: "Namespace" }
      },
      required: ["name"]
    }
  },
  {
    name: "store_delete",
    description: "Delete an entire dynamic store.",
    parameters: {
      type: "object",
      properties: {
        name: { type: "string", description: "Store name" },
        namespace: { type: "string", description: "Namespace" }
      },
      required: ["name"]
    }
  }
];

export async function executeStoreTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  try {
    switch (name) {
      case "store_create": {
        const spec = await storeCreate(cwd, String(args.name), String(args.kind) as any, {
          namespace: args.namespace ? String(args.namespace) : undefined,
          description: args.description ? String(args.description) : undefined
        });
        return JSON.stringify(spec, null, 2);
      }
      case "store_list": {
        const specs = await storeList(cwd, args.namespace ? { namespace: String(args.namespace) } : undefined);
        return JSON.stringify(specs, null, 2);
      }
      case "store_get":
        return await storeGet(cwd, String(args.name), String(args.field), args.namespace ? String(args.namespace) : undefined);
      case "store_set":
        return await storeSet(cwd, String(args.name), String(args.field), String(args.value), args.namespace ? String(args.namespace) : undefined);
      case "store_rm":
        return await storeRemove(cwd, String(args.name), String(args.field), args.namespace ? String(args.namespace) : undefined);
      case "store_dump":
        return await storeDump(cwd, String(args.name), args.namespace ? String(args.namespace) : undefined);
      case "store_delete":
        return await storeDelete(cwd, String(args.name), args.namespace ? String(args.namespace) : undefined);
      default:
        return `Unknown store tool: ${name}`;
    }
  } catch (err) {
    return `Error: ${err instanceof Error ? err.message : String(err)}`;
  }
}
