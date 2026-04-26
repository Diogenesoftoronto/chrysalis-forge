import { cacheGet, cacheSet, cacheInvalidate, cacheInvalidateByTag, cacheCleanup, cacheStats } from "../stores/cache-store.js";

export const CACHE_TOOL_DEFINITIONS = [
  {
    name: "cache_get",
    description: "Retrieve a cached value by key. Returns null if not found or expired.",
    parameters: {
      type: "object",
      properties: {
        key: { type: "string", description: "Cache key" }
      },
      required: ["key"]
    }
  },
  {
    name: "cache_set",
    description: "Store a value in the cache with optional TTL and tags for invalidation.",
    parameters: {
      type: "object",
      properties: {
        key: { type: "string", description: "Cache key" },
        value: { type: "string", description: "Value to cache" },
        ttl: { type: "integer", description: "TTL in seconds (default 86400)" },
        tags: { type: "array", items: { type: "string" }, description: "Tags for group invalidation" }
      },
      required: ["key", "value"]
    }
  },
  {
    name: "cache_invalidate",
    description: "Invalidate a specific cache key.",
    parameters: {
      type: "object",
      properties: {
        key: { type: "string", description: "Cache key to invalidate" }
      },
      required: ["key"]
    }
  },
  {
    name: "cache_invalidate_tag",
    description: "Invalidate all cache entries with a given tag.",
    parameters: {
      type: "object",
      properties: {
        tag: { type: "string", description: "Tag to invalidate" }
      },
      required: ["tag"]
    }
  },
  {
    name: "cache_stats",
    description: "Show cache statistics: total entries, valid, expired, tag counts.",
    parameters: { type: "object", properties: {}, required: [] }
  },
  {
    name: "cache_cleanup",
    description: "Remove all expired entries from the cache.",
    parameters: { type: "object", properties: {}, required: [] }
  }
];

export async function executeCacheTool(
  cwd: string,
  name: string,
  args: Record<string, unknown>
): Promise<string> {
  switch (name) {
    case "cache_get": {
      const key = String(args.key ?? "");
      if (!key) return "Error: key is required";
      const value = await cacheGet(cwd, key);
      return value ?? "(not found or expired)";
    }
    case "cache_set": {
      const key = String(args.key ?? "");
      const value = String(args.value ?? "");
      if (!key) return "Error: key is required";
      const ttl = Number(args.ttl ?? 86400);
      const tags = Array.isArray(args.tags) ? args.tags.map(String) : [];
      return await cacheSet(cwd, key, value, ttl, tags);
    }
    case "cache_invalidate": {
      const key = String(args.key ?? "");
      if (!key) return "Error: key is required";
      return await cacheInvalidate(cwd, key);
    }
    case "cache_invalidate_tag": {
      const tag = String(args.tag ?? "");
      if (!tag) return "Error: tag is required";
      return await cacheInvalidateByTag(cwd, tag);
    }
    case "cache_stats": {
      const stats = await cacheStats(cwd);
      return JSON.stringify(stats, null, 2);
    }
    case "cache_cleanup":
      return await cacheCleanup(cwd);
    default:
      return `Unknown cache tool: ${name}`;
  }
}
