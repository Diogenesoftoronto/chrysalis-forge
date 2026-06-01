import { mkdir } from "node:fs/promises";
import { join, resolve } from "node:path";

export function cacheStorePath(cwd: string, rootName = ".chrysalis"): string {
  return join(resolve(cwd, rootName), "state", "web-cache.json");
}

export async function ensureCacheDir(cwd: string, rootName = ".chrysalis"): Promise<void> {
  await mkdir(join(resolve(cwd, rootName), "state"), { recursive: true });
}
