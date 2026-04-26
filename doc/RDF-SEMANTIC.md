# RDF & Semantic Memory

Chrysalis Forge provides two complementary knowledge stores for agents: a **Vector Store** for semantic similarity search and an **RDF Store** for structured triple/quad knowledge graphs. Both are JSON-backed, zero-dependency, and store data under `.chrysalis/state/`.

These stores give agents long-term memory that persists across sessions — the vector store finds semantically similar passages, while the RDF store answers structured queries about entities and their relationships.

---

## Vector Store

The vector store enables semantic search over embedded text. You add text with its embedding vector, then query with a new vector to find the closest matches by cosine similarity.

**Source:** `ts/core/stores/vector-store.ts`

### API

```typescript
import { vectorAdd, vectorSearch, cosineSimilarity } from "./core/stores/vector-store.js";
```

#### `vectorAdd(cwd, text, vec): Promise<string>`

Add a text entry with its embedding vector. Returns a unique ID.

| Parameter | Type | Description |
|-----------|------|-------------|
| `cwd` | `string` | Project root directory |
| `text` | `string` | The text to store |
| `vec` | `number[]` | Embedding vector for the text |

Returns: a generated ID string like `"1710000000-a1b2c3"`.

```typescript
const id = await vectorAdd(
  projectDir,
  "GEPA uses reflective prompt evolution to outperform RL",
  [0.12, -0.34, 0.56, ...]
);
```

#### `vectorSearch(cwd, queryVec, topK?): Promise<Array<{ score: number; text: string }>>`

Search for entries similar to the query vector. Returns results sorted by cosine similarity, highest first.

| Parameter | Type | Description |
|-----------|------|-------------|
| `cwd` | `string` | Project root directory |
| `queryVec` | `number[]` | Query embedding vector |
| `topK` | `number` | Maximum results (default: `3`) |

```typescript
const results = await vectorSearch(projectDir, [0.11, -0.30, 0.52, ...], 5);
// => [{ score: 0.94, text: "GEPA uses reflective..." }, ...]
```

#### `cosineSimilarity(a, b): number`

Compute cosine similarity between two vectors. Returns a value in `[0, 1]` for non-negative vectors, or `[-1, 1]` in general. Returns `0` if either vector has zero magnitude.

```typescript
const sim = cosineSimilarity([1, 0, 0], [0, 1, 0]); // => 0
const sim = cosineSimilarity([1, 0, 0], [1, 0, 0]); // => 1
```

### Data Format

The vector store writes to `.chrysalis/state/vectors.json`:

```json
{
  "1710000000-a1b2c3": {
    "text": "GEPA uses reflective prompt evolution",
    "vec": [0.12, -0.34, 0.56, ...]
  }
}
```

The `VectorEntry` type (from `ts/core/types.ts`):

```typescript
interface VectorEntry {
  text: string;
  vec: number[];
}
```

---

## RDF Store

The RDF store manages structured knowledge as triples (subject–predicate–object) with optional graph and timestamp fields. It uses pattern-matching queries with `?` wildcards — not SQL.

**Source:** `ts/core/stores/rdf-store.ts`

### Data Model

Every entry in the RDF store is a `Triple`:

```typescript
interface Triple {
  subject: string;
  predicate: string;
  object: string;
  graph: string;      // named graph (defaults to "default")
  timestamp: number;   // Unix epoch seconds
}
```

Triples are grouped by graph. Loading a file into a graph replaces all existing triples in that graph, preserving triples from other graphs.

### API

```typescript
import { rdfLoad, rdfQuery, rdfInsert } from "./core/stores/rdf-store.js";
```

#### `rdfLoad(cwd, path, graphId): Promise<string>`

Load triples from a text file into a named graph. Each line in the file should contain whitespace-separated `subject predicate object` tokens. Any content after the first three tokens becomes the object (allowing objects with spaces).

Loading into a graph **replaces** all existing triples in that graph. Triples in other graphs are preserved.

| Parameter | Type | Description |
|-----------|------|-------------|
| `cwd` | `string` | Project root directory |
| `path` | `string` | Path to the triple file |
| `graphId` | `string` | Named graph to load into |

Returns: a summary string like `"Loaded 42 lines into graph my-graph."`.

**Triple file format** (`knowledge.txt`):

```
chrysalis implements prompt-evolution
gepa outperforms reinforcement-learning
gepa uses reflective-prompt-evolution
maker enables million-step-reasoning
```

```typescript
const result = await rdfLoad(projectDir, "knowledge.txt", "research");
// => "Loaded 4 lines into graph research."
```

#### `rdfQuery(cwd, query, graphId?): Promise<string>`

Query the store using pattern-matching syntax. Returns JSON-stringified matching triples.

**Pattern syntax:** Space-separated fields map to `subject predicate object graph`. Use `?` as a wildcard for any field. Omitted trailing fields are unconstrained.

| Pattern | Meaning |
|---------|---------|
| `?s predicate object` | Match by predicate and object |
| `?s ?p object` | Match by object only |
| `subject ?p ?o` | Match by subject only |
| `subject predicate ?o ?g` | Match by subject and predicate across all graphs |
| `subject predicate object graph` | Exact match |

Results are capped at 200 triples.

> **Note:** SQL `SELECT` queries are not supported. The store is JSON-backed, not SQL-backed. If you attempt a `SELECT` query, you'll receive an error message with guidance to use pattern syntax instead.

```typescript
// Find everything about GEPA
const result = await rdfQuery(projectDir, "gepa ?p ?o");
// => JSON array of matching triples

// Find all evolution methods
const result = await rdfQuery(projectDir, "?s uses ?o", "research");

// Exact match
const result = await rdfQuery(projectDir, "gepa outperforms reinforcement-learning");
```

#### `rdfInsert(cwd, subject, predicate, object, graph?, timestamp?): Promise<string>`

Insert a single triple into the store. The graph defaults to `"default"` and the timestamp defaults to the current time.

| Parameter | Type | Description |
|-----------|------|-------------|
| `cwd` | `string` | Project root directory |
| `subject` | `string` | Subject URI or label |
| `predicate` | `string` | Predicate URI or label |
| `object` | `string` | Object value |
| `graph` | `string` | Named graph (default: `"default"`) |
| `timestamp` | `number` | Unix epoch seconds (default: now) |

```typescript
const result = await rdfInsert(
  projectDir,
  "chrysalis",
  "stores-knowledge-in",
  "json-files",
  "project-facts"
);
// => "Inserted triple: chrysalis stores-knowledge-in json-files (graph: project-facts)"
```

### Data Location

The RDF store writes to `.chrysalis/state/rdf/graph.db` as a JSON array of triples:

```json
[
  {
    "subject": "gepa",
    "predicate": "outperforms",
    "object": "reinforcement-learning",
    "graph": "research",
    "timestamp": 1710000000
  }
]
```

---

## RDF Tools (Pi Agent Interface)

The Pi agent accesses RDF functionality through three tool definitions dispatched by `executeRdfTool()`. These tools are registered in `ts/core/tools/rdf-tools.ts` and exposed to the Pi agent via `ts/pi/chrysalis-extension.ts`.

**Source:** `ts/core/tools/rdf-tools.ts`

### Tool Definitions

| Tool | Description | Required Params | Optional Params |
|------|-------------|-----------------|-----------------|
| `rdf_load` | Load triples from a file into a named graph | `path`, `id` | — |
| `rdf_query` | Query the knowledge graph with pattern syntax | `query` | `id` (default graph) |
| `rdf_insert` | Insert a single triple or quad | `subject`, `predicate`, `object` | `graph`, `timestamp` |

### `executeRdfTool(cwd, name, args): Promise<string>`

Dispatch function that routes tool calls to the appropriate RDF store function.

```typescript
import { executeRdfTool } from "./core/tools/rdf-tools.js";

const result = await executeRdfTool(projectDir, "rdf_query", {
  query: "gepa ?p ?o"
});
```

---

## Data Locations Summary

| Store | File | Content |
|-------|------|---------|
| Vector Store | `.chrysalis/state/vectors.json` | `Record<string, VectorEntry>` |
| RDF Store | `.chrysalis/state/rdf/graph.db` | `Triple[]` |

Both stores are initialized automatically on first use. No setup or external database is required.

---

## Usage Patterns

### Building a Project Knowledge Base

```typescript
import { rdfLoad, rdfInsert, rdfQuery } from "./core/stores/rdf-store.js";
import { vectorAdd, vectorSearch } from "./core/stores/vector-store.js";

// 1. Load structured facts from a file
await rdfLoad(projectDir, "docs/facts.txt", "project");

// 2. Insert individual facts
await rdfInsert(projectDir, "api", "exposes-endpoint", "/evolve", "project");
await rdfInsert(projectDir, "evolution", "uses-method", "gepa", "project");

// 3. Query relationships
const methods = await rdfQuery(projectDir, "evolution uses-method ?o", "project");

// 4. Add semantic passages for retrieval
await vectorAdd(projectDir, "The evolution engine runs GEPA-style ...", evolutionEmbedding);
await vectorAdd(projectDir, "Decomposition follows the MAKER ...", decompEmbedding);

// 5. Search semantically
const similar = await vectorSearch(projectDir, queryEmbedding, 5);
```

### Agent Memory in a Pi Session

Within a Pi agent session, the RDF tools are available directly:

```
/rdf_insert subject=chrysalis predicate=supports object=typescript graph=project-facts
/rdf_query query="chrysalis ?p ?o"
/rdf_load path=knowledge.txt id=external-kb
```

### Combining Both Stores

The vector store and RDF store complement each other:

- **Vector store** — answers "what is similar to X?" Good for retrieval-augmented generation, finding relevant context, and fuzzy matching.
- **RDF store** — answers "what is the relationship between X and Y?" Good for structured queries, relationship traversal, and exact entity lookups.

A typical agent workflow:
1. Use **vector search** to find relevant passages for the current query.
2. Use **RDF query** to look up specific relationships mentioned in those passages.
3. Use **RDF insert** to record new facts discovered during the session.
4. Use **vector add** to store important passages for future retrieval.

---

## Design Decisions

### Why JSON-backed, not SQLite?

The Racket predecessor used SQLite for the RDF store. The TypeScript migration deliberately switched to JSON files for:

1. **Zero dependencies** — no native module compilation, works everywhere Node.js runs.
2. **Transparency** — data is human-readable and debuggable with any text editor.
3. **Portability** — copy the `.chrysalis/` directory to back up or transfer all project state.

The trade-off is query performance on very large graphs. For typical agent knowledge bases (hundreds to low thousands of triples), JSON I/O is fast enough. The 200-result cap on queries prevents pathological cases.

### Why No SQL Support?

The `rdfQuery` function detects `SELECT`-style queries and returns an error with guidance. Pattern matching is the intended query interface — it maps directly to the JSON-backed storage model without a SQL parser. If you need complex relational queries, consider exporting the triples and loading them into a dedicated graph database.

### Wildcard Semantics

The `?` wildcard matches any value in that field position. Trailing wildcards can be omitted — `subject predicate` is equivalent to `subject predicate ?o ?g`. This keeps the query syntax concise for the common case of querying by subject and/or predicate.
