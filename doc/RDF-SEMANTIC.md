# Semantic Memory & Knowledge Graphs

Chrysalis Forge provides two complementary memory systems for agent cognition:

1. **Vector Store** — Fuzzy semantic search using embeddings
2. **RDF Store** — Structured knowledge graphs with temporal queries

Together, these enable agents to maintain both associative memory (finding similar concepts) and factual knowledge (precise relationship queries).

---

## Vector Store

The vector store (`src/stores/vector-store.rkt`) provides semantic similarity search using OpenAI embeddings.

### How It Works

1. Text is converted to a 1536-dimensional vector using `text-embedding-3-small`
2. Vectors are stored with their source text
3. Queries are embedded and compared using cosine similarity
4. Top-k most similar results are returned

### API

```racket
(require "src/stores/vector-store.rkt")

;; Add text to the vector store
(vector-add! "The authentication module uses JWT tokens for session management."
             api-key
             "https://api.openai.com/v1")
; → "Stored."

;; Search for similar content
(vector-search "How does login work?" api-key)
; → '((0.87 . "The authentication module uses JWT tokens...")
;     (0.72 . "Users can login with email and password...")
;     (0.65 . "Session tokens expire after 24 hours..."))
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `text` | string | required | Text to store or query |
| `key` | string | required | OpenAI API key |
| `base` | string | `"https://api.openai.com/v1"` | API base URL |
| `top-k` | number | 3 | Number of results to return |

### Storage

Vectors persist to `~/.agentd/vectors.json` as a hash mapping IDs to `{text, vec}` pairs.

### Use Cases

- **Fuzzy Memory**: "What did we discuss about caching?"
- **Code Search**: Find similar implementations
- **Documentation Retrieval**: Find relevant docs for a question
- **Deduplication**: Detect near-duplicate content

---

## RDF Store

The RDF store (`src/stores/rdf-store.rkt`) provides a SQLite-backed triple/quad store for structured knowledge.

### Data Model

Each fact is stored as a **quad** (triple + graph):

| Field | Description |
|-------|-------------|
| `subject` | The entity being described |
| `predicate` | The relationship type |
| `object` | The value or related entity |
| `graph` | Named graph for organizing facts |
| `timestamp` | When the fact was recorded (epoch seconds) |

### API

```racket
(require "src/stores/rdf-store.rkt")

;; Insert a triple
(rdf-insert! "auth.rkt" "implements" "JWT")
(rdf-insert! "auth.rkt" "author" "alice" "project-facts")
(rdf-insert! "auth.rkt" "modified" "2024-01-15" "project-facts" 1705276800)

;; Load triples from a file
(rdf-load! "project-facts.ttl" "project-graph")

;; Query the knowledge graph
(rdf-query "auth.rkt ?p ?o" "default")
; → All predicates and objects for auth.rkt
```

### Query Pattern Syntax

Patterns use `?` prefix for variables:

#### 3-Part Patterns (Triples)

| Pattern | Finds |
|---------|-------|
| `?s predicate object` | Subjects with given predicate-object |
| `subject ?p object` | Predicates linking subject to object |
| `subject predicate ?o` | Objects for given subject-predicate |
| `?s ?p object` | All triples with given object |
| `?s predicate ?o` | All subject-object pairs for predicate |
| `subject ?p ?o` | All facts about subject |

#### 4-Part Patterns (Quads)

| Pattern | Finds |
|---------|-------|
| `?s predicate object graph` | Subjects in specific graph |
| `subject predicate ?o graph` | Objects in specific graph |
| `subject predicate object ?g` | Graphs containing the triple |

### Examples

```racket
;; Find all files that implement JWT
(rdf-query "?s implements JWT" "default")

;; Find what auth.rkt implements
(rdf-query "auth.rkt implements ?o" "default")

;; Find all facts about auth.rkt
(rdf-query "auth.rkt ?p ?o" "default")

;; Find facts in the project-facts graph
(rdf-query "?s author ?o project-facts" "default")

;; Raw SQL for complex queries
(rdf-query "SELECT * FROM triples WHERE predicate='depends-on' ORDER BY timestamp DESC" "default")
```

### Storage

The RDF store persists to `~/.agentd/graph.db` (SQLite).

---

## RDF Tools

The RDF tools (`src/tools/rdf-tools.rkt`) expose knowledge graph operations to the agent.

### Tool Definitions

```racket
(make-rdf-tools)
; Returns tool schemas for: rdf_load, rdf_query, rdf_insert
```

### rdf_load

Load triples from a file into a named graph.

```json
{
  "name": "rdf_load",
  "arguments": {
    "path": "knowledge/project-facts.ttl",
    "id": "project"
  }
}
```

### rdf_query

Query the knowledge graph with patterns.

```json
{
  "name": "rdf_query",
  "arguments": {
    "query": "?s implements JWT",
    "id": "default"
  }
}
```

### rdf_insert

Insert a single fact with optional timestamp.

```json
{
  "name": "rdf_insert",
  "arguments": {
    "subject": "api-router.rkt",
    "predicate": "depends-on",
    "object": "auth.rkt",
    "graph": "dependencies",
    "timestamp": 1705276800
  }
}
```

---

## Semantic Mode

The context mode `'semantic` enables RDF operations. Set it in the context:

```racket
(define ctx
  (ctx #:system "You are a knowledge engineer."
       #:mode 'semantic
       #:priority 'best))
```

In semantic mode, the agent has access to:
- All RDF tools (`rdf_load`, `rdf_query`, `rdf_insert`)
- File reading (to extract facts)
- No file writing (read-only analysis)

---

## Building a Project Knowledge Base

Here's a practical example of building a knowledge graph for a codebase:

### 1. Define Your Ontology

```
# Predicates for code relationships
implements    - File implements a concept
depends-on    - File depends on another file
exports       - File exports a function/struct
authored-by   - File was written by
modified-at   - Last modification timestamp
```

### 2. Bootstrap with Facts

```racket
;; Core module relationships
(rdf-insert! "auth.rkt" "implements" "authentication")
(rdf-insert! "auth.rkt" "implements" "JWT")
(rdf-insert! "auth.rkt" "exports" "create-jwt")
(rdf-insert! "auth.rkt" "exports" "verify-jwt")
(rdf-insert! "auth.rkt" "depends-on" "config.rkt")

(rdf-insert! "billing.rkt" "implements" "usage-tracking")
(rdf-insert! "billing.rkt" "depends-on" "auth.rkt")
(rdf-insert! "billing.rkt" "depends-on" "db.rkt")
```

### 3. Query for Understanding

```racket
;; What depends on auth.rkt?
(rdf-query "?s depends-on auth.rkt" "default")

;; What does billing.rkt depend on?
(rdf-query "billing.rkt depends-on ?o" "default")

;; Find all JWT-related files
(rdf-query "?s implements JWT" "default")
```

### 4. Temporal Queries

With timestamps, you can track knowledge evolution:

```racket
;; Insert with timestamp
(rdf-insert! "auth.rkt" "status" "refactored" "default" (current-seconds))

;; Query recent changes (via raw SQL)
(rdf-query "SELECT * FROM triples WHERE timestamp > 1705000000 ORDER BY timestamp DESC" "default")
```

---

## Combining Vector and RDF Search

For optimal retrieval, combine both approaches:

```racket
;; 1. Use vector search to find relevant context
(define similar (vector-search "authentication flow" api-key))

;; 2. Extract entities from results
(define entities (extract-file-names similar))

;; 3. Use RDF to get structured relationships
(for ([entity entities])
  (printf "~a depends on: ~a~n" 
          entity 
          (rdf-query (format "~a depends-on ?o" entity) "default")))
```

This hybrid approach gives you:
- **Breadth** from semantic similarity
- **Precision** from structured relationships
- **Temporal awareness** from timestamps

---

## Data Locations

| Store | Path | Format |
|-------|------|--------|
| Vector Store | `~/.agentd/vectors.json` | JSON hash |
| RDF Store | `~/.agentd/graph.db` | SQLite |
