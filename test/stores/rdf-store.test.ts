import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { rdfLoad, rdfQuery, rdfInsert } from "../../ts/core/stores/rdf-store.js";

describe("rdf-store", () => {
  test("load N-triples, query with wildcards, and insert", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-rdf-"));
    const triplesPath = join(cwd, "test.nt");
    try {
      await writeFile(triplesPath, "alice knows bob\nalice knows carol\nbob knows dave\n");
      const loadResult = await rdfLoad(cwd, triplesPath, "test-graph");
      expect(loadResult).toContain("3");
      expect(loadResult).toContain("test-graph");

      const allResult = await rdfQuery(cwd, "? knows bob", "test-graph");
      const parsed = JSON.parse(allResult);
      expect(parsed.length).toBe(1);
      expect(parsed[0].subject).toBe("alice");

      const insertResult = await rdfInsert(cwd, "eve", "knows", "alice", "test-graph");
      expect(insertResult).toContain("eve");
      expect(insertResult).toContain("Inserted");

      const afterInsert = await rdfQuery(cwd, "eve knows ?", "test-graph");
      const parsed2 = JSON.parse(afterInsert);
      expect(parsed2.length).toBe(1);
      expect(parsed2[0].object).toBe("alice");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("query with all wildcards returns all triples in graph", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-rdf-"));
    const triplesPath = join(cwd, "data.nt");
    try {
      await writeFile(triplesPath, "x rel y\na rel b\n");
      await rdfLoad(cwd, triplesPath, "g1");
      const result = await rdfQuery(cwd, "? ? ?", "g1");
      const parsed = JSON.parse(result);
      expect(parsed.length).toBe(2);
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test("load returns error for missing file", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "chrysalis-rdf-"));
    try {
      const result = await rdfLoad(cwd, "/nonexistent/file.nt", "g");
      expect(result).toContain("not found");
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
