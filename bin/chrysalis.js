#!/usr/bin/env node

const MIN_NODE_VERSION = "20.19.0";

function parseVersion(version) {
  const [major = "0", minor = "0", patch = "0"] = version.replace(/^v/, "").split(".");
  return {
    major: Number.parseInt(major, 10) || 0,
    minor: Number.parseInt(minor, 10) || 0,
    patch: Number.parseInt(patch, 10) || 0
  };
}

function compareVersions(left, right) {
  if (left.major !== right.major) return left.major - right.major;
  if (left.minor !== right.minor) return left.minor - right.minor;
  return left.patch - right.patch;
}

if (compareVersions(parseVersion(process.versions.node), parseVersion(MIN_NODE_VERSION)) < 0) {
  console.error(`chrysalis requires Node.js ${MIN_NODE_VERSION} or later (detected ${process.versions.node}).`);
  process.exit(1);
}

await import(new URL("../dist/ts/cli/main.js", import.meta.url).href);
