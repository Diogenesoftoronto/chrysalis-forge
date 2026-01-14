# Agent Guidance: Stores

When working with state or memory, use these modules to maintain persistence.

## Key Patterns

1. **Context Management**: Always use `context-store.rkt` to retrieve or update the active session state. 
   - `(ctx-get-active)`: Get the current context.
   - `(save-ctx! db)`: Persist changes.

2. **Performance Tracking**: Log task results using `log-eval!` in `eval-store.rkt`. This is essential for the system's self-improvement loops.

3. **Knowledge Retrieval**:
   - Use `vector-store.rkt` for fuzzy semantic memory.
   - Use `rdf-store.rkt` for structured fact retrieval.

## Data Locations
All stores persist to the `~/.chrysalis/` directory (e.g., `~/.chrysalis/evals.jsonl`, `~/.chrysalis/context.json`).
