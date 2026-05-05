import { existsSync, statSync } from "node:fs";
import { readdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");

const bundles = [
  {
    baseDir: root,
    entries: [
      "package.json",
      "SYSTEM.md",
      "README.md",
      "CHANGELOG.md"
    ]
  },
  {
    baseDir: join(root, "pi"),
    entries: [
      "prompts",
      "skills"
    ],
    targetPrefix: "pi"
  },
  {
    baseDir: join(root, "dist", "ts"),
    entries: ["."],
    targetPrefix: "ts"
  },
  {
    baseDir: join(root, "node_modules", "@mariozechner", "pi-coding-agent"),
    entries: [
      "dist/modes/interactive/theme",
      "dist/modes/interactive/assets",
      "dist/core/export-html"
    ],
    remap: (path) =>
      path
        .replace(/^dist\/modes\/interactive\/theme/, "theme")
        .replace(/^dist\/modes\/interactive\/assets/, "assets")
        .replace(/^dist\/core\/export-html/, "export-html")
  },
  {
    baseDir: join(root, "node_modules", "@silvia-odwyer", "photon-node"),
    entries: ["photon_rs_bg.wasm"]
  }
];

async function listFiles(baseDir, entry) {
  const absolute = join(baseDir, entry);
  if (!existsSync(absolute)) {
    return [];
  }
  const stats = statSync(absolute);
  if (stats.isFile()) {
    return [absolute];
  }

  const out = [];
  async function walk(dir) {
    const entries = await readdir(dir, { withFileTypes: true });
    for (const child of entries) {
      const next = join(dir, child.name);
      if (child.isDirectory()) {
        await walk(next);
      } else if (child.isFile()) {
        out.push(next);
      }
    }
  }
  await walk(absolute);
  return out;
}

function encodingForPath(path) {
  return /\.(png|jpg|jpeg|gif|webp|wasm)$/i.test(path) ? "base64" : "utf8";
}

const files = [];

for (const bundle of bundles) {
  for (const entry of bundle.entries) {
    for (const file of await listFiles(bundle.baseDir, entry)) {
      const relativePath = relative(bundle.baseDir, file).replaceAll("\\", "/");
      const targetPath = bundle.remap
        ? bundle.remap(relativePath)
        : bundle.targetPrefix
          ? `${bundle.targetPrefix}/${relativePath === "." ? "" : relativePath}`.replace(/\/+$/g, "")
          : relativePath;
      const encoding = encodingForPath(file);
      const content = await readFile(file, encoding === "base64" ? undefined : "utf8");
      files.push({
        path: targetPath,
        encoding,
        content: encoding === "base64" ? content.toString("base64") : content
      });
    }
  }
}

files.sort((left, right) => left.path.localeCompare(right.path));

const output = `export interface BundledFile {
  path: string;
  encoding: "utf8" | "base64";
  content: string;
}

export const BUNDLED_APP_VERSION = ${JSON.stringify(JSON.parse(await readFile(join(root, "package.json"), "utf8")).version)};

export const BUNDLED_FILES: BundledFile[] = ${JSON.stringify(files, null, 2)};\n`;

await writeFile(join(root, "ts", "runtime", "bundled-assets.generated.ts"), output, "utf8");
