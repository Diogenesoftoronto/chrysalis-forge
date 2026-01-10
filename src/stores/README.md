# Stores

This directory contains the persistence and state management modules for Chrysalis Forge.

## Modules

- **`cache-store.rkt`**: Persistent caching with TTL and invalidation logic.
- **`context-store.rkt`**: Manages agent conversation history, system prompts, and operational modes.
- **`eval-store.rkt`**: Tracks performance of tool profiles and sub-agents to enable learning.
- **`rdf-store.rkt`**: Knowledge graph persistence using RDF triples and hypergraph patterns.
- **`trace-store.rkt`**: Logs detailed execution traces for debugging and auditing.
- **`vector-store.rkt`**: Interface for vector-based semantic memory.
