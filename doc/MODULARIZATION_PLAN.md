# Chrysalis Forge Tool Modularization Plan

## Philosophy

Chrysalis's core value is **self-evolution**: an agent that improves its own prompts, harness, and tools through feedback. Everything else should be opt-in. This aligns with Pi's Unix-inspired philosophy of composable, minimal primitives.

The current tool surface is 66+ tools across 14 categories. Many are valuable but not essential to the self-evolution loop. This plan proposes a **core install** that contains only what is needed for the agent to plan, execute, evolve, and persist state. Everything else ships as optional packages installable separately.

---

## 1. Current Tool Audit

### Tool Group Inventory

| File | Tools | Count | Category |
|------|-------|-------|----------|
| `ts/core/tools/evolution-tools.ts` | evolve_system, evolve_meta, evolve_harness, log_feedback, suggest_profile, profile_stats, archive_list, evolution_stats | 8 | Self-Evolution |
| `ts/core/tools/evolver-tools.ts` | evolve_tool, list_tools, tool_variants, select_tool_variant, enable_tool, disable_tool, tool_stats, tool_evolution_stats | 8 | Tool System |
| `ts/core/tools/priority-tools.ts` | set_priority, get_priority, suggest_priority | 3 | Execution Control |
| `ts/core/tools/decomp-tools.ts` | decompose_task, classify_task, decomp_vote | 3 | Planning |
| `ts/core/tools/rollback-tools.ts` | file_rollback, file_rollback_list | 2 | Safety |
| `ts/core/tools/git-tools.ts` | git_status, git_diff, git_log, git_commit, git_checkout, git_add, git_branch | 7 | VCS (Git) |
| `ts/core/tools/jj-tools.ts` | jj_status, jj_log, jj_diff, jj_undo, jj_op_log, jj_op_restore, jj_workspace_add, jj_workspace_list, jj_describe, jj_new | 10 | VCS (Jujutsu) |
| `ts/core/tools/store-tools.ts` | store_create, store_list, store_get, store_set, store_rm, store_dump, store_delete | 7 | Persistence |
| `ts/core/tools/cache-tools.ts` | cache_get, cache_set, cache_invalidate, cache_invalidate_tag, cache_stats, cache_cleanup | 6 | Caching |
| `ts/core/tools/rdf-tools.ts` | rdf_load, rdf_query, rdf_insert | 3 | Knowledge Graph |
| `ts/core/tools/web-tools.ts` | web_fetch, web_search | 2 | External |
| `ts/core/tools/sub-agent-tools.ts` | spawn_task, await_task, task_status | 3 | Concurrency |
| `ts/core/tools/judge-tools.ts` | use_llm_judge, judge_quality | 2 | Evaluation |
| `ts/core/tools/test-tools.ts` | generate_tests, generate_test_cases | 2 | Testing |

**Total: 66 tools across 14 files.**

---

## 2. Core vs Optional Classification

### Core (self-evolution loop)

These tools are required for Chrysalis to fulfill its primary purpose: planning tasks, executing them, evolving its own behavior, and persisting state.

| Group | Tools | Rationale |
|-------|-------|-----------|
| **Planning** (`decomp-tools.ts`) | decompose_task, classify_task | Task decomposition is the entry point to all work. |
| **Execution Control** (`priority-tools.ts`) | set_priority, get_priority, suggest_priority | Profile selection is part of the core loop. |
| **Self-Evolution** (`evolution-tools.ts`) | evolve_system, evolve_meta, evolve_harness, log_feedback, suggest_profile, profile_stats, archive_list, evolution_stats | The entire GEPA/MAP-Elites loop. |
| **Tool System** (`evolver-tools.ts`) | evolve_tool, list_tools, tool_variants, select_tool_variant, enable_tool, disable_tool, tool_stats, tool_evolution_stats | Self-evolution of tools is part of the core. |
| **Safety** (`rollback-tools.ts`) | file_rollback, file_rollback_list | Essential for safe file operations. |
| **Persistence** (`store-tools.ts`) | store_create, store_list, store_get, store_set, store_rm, store_dump, store_delete | Dynamic state persistence. |

**Core total: 32 tools**

### Optional (installable separately)

These are valuable but orthogonal to self-evolution. They can be installed as needed without breaking the core loop.

| Package | Group | Tools | Rationale |
|---------|-------|-------|-----------|
| `@chrysalis/vcs-git` | Git (`git-tools.ts`) | 7 tools | Version control. Most users have git but not all need agent-managed git ops. |
| `@chrysalis/vcs-jj` | Jujutsu (`jj-tools.ts`) | 10 tools | Alternative VCS. Niche, should not be in core. |
| `@chrysalis/web` | Web (`web-tools.ts`) | 2 tools | External HTTP + search. Requires API keys; not all workflows need web access. |
| `@chrysalis/eval` | Judge (`judge-tools.ts`) + Test (`test-tools.ts`) | 4 tools | LLM-as-judge and test generation. Useful for benchmarking but heavy; requires extra LLM calls. |
| `@chrysalis/concurrent` | Sub-Agent (`sub-agent-tools.ts`) | 3 tools | Parallel sub-agents. Useful for large tasks but adds process-spawning complexity. |
| `@chrysalis/cache` | Cache (`cache-tools.ts`) | 6 tools | TTL-based caching. The web tool uses this internally, so this is a dependency of `@chrysalis/web`. |
| `@chrysalis/rdf` | RDF (`rdf-tools.ts`) | 3 tools | Knowledge graph. Powerful but niche; most users will not need semantic triplestores. |

**Optional total: 34 tools** (plus the cache module as a web dependency)

### Optional package dependency graph

```
@chrysalis/web
  └── @chrysalis/cache   (web_fetch and web_search use cache)

@chrysalis/eval
  └── (no deps, but optionally benefits from @chrysalis/web for judge tests)

@chrysalis/vcs-git      (standalone)
@chrysalis/vcs-jj       (standalone)
@chrysalis/concurrent   (standalone)
@chrysalis/rdf          (standalone)
```

---

## 3. Package Structure

### Monorepo layout (inside existing repo)

```
packages/
  core/                          # existing chrysalis-forge core
    ts/core/tools/
      # keep only core tools:
      #   decomp-tools.ts
      #   priority-tools.ts
      #   evolution-tools.ts
      #   evolver-tools.ts
      #   rollback-tools.ts
      #   store-tools.ts
      #   index.ts (exports core)
    ts/core/stores/
      # keep core stores:
      #   context-store.ts
      #   eval-store.ts
      #   session-stats.ts
      #   trace-store.ts
      #   thread-store.ts
      #   rollback-store.ts
      #   store-registry.ts
      #   index.ts
    # remove or move to optional:
    #   rdf-store.ts      → @chrysalis/rdf
    #   vector-store.ts   → @chrysalis/rdf (or standalone semantic)
    #   cache-store.ts    → @chrysalis/cache
    #   decomp-archive.ts → @chrysalis/core (keep, used by planner)

  vcs-git/
    package.json
    ts/index.ts                  # exports GIT_TOOL_DEFINITIONS, executeGitTool
    ts/git-tools.ts              # copied from core/tools/git-tools.ts

  vcs-jj/
    package.json
    ts/index.ts                  # exports JJ_TOOL_DEFINITIONS, executeJjTool
    ts/jj-tools.ts               # copied from core/tools/jj-tools.ts

  web/
    package.json
    ts/index.ts                  # exports WEB_TOOL_DEFINITIONS, executeWebTool
    ts/web-tools.ts              # copied from core/tools/web-tools.ts

  cache/
    package.json
    ts/index.ts                  # exports CACHE_TOOL_DEFINITIONS, executeCacheTool
    ts/cache-tools.ts            # copied from core/tools/cache-tools.ts
    ts/cache-store.ts            # moved from core/stores/cache-store.ts

  eval/
    package.json
    ts/index.ts                  # exports JUDGE + TEST tool defs
    ts/judge-tools.ts
    ts/test-tools.ts

  concurrent/
    package.json
    ts/index.ts                  # exports SUB_AGENT defs
    ts/sub-agent-tools.ts

  rdf/
    package.json
    ts/index.ts                  # exports RDF defs + store
    ts/rdf-tools.ts
    ts/rdf-store.ts              # moved from core/stores/rdf-store.ts
```

### Package `package.json` examples

Each optional package declares `chrysalis-forge` as a peer dependency:

```json
{
  "name": "@chrysalis/web",
  "version": "0.4.0",
  "type": "module",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "peerDependencies": {
    "chrysalis-forge": "^0.4.0"
  },
  "dependencies": {
    "@chrysalis/cache": "^0.4.0"
  }
}
```

---

## 4. Configuration Schema Changes

### `chrysalis.config.json` (new field)

Add an `extensions` array so users opt into optional tool packages:

```json
{
  "pi": {
    "runtimePreference": "prefer-embedded",
    "tools": ["read", "bash", "edit", "write", "grep", "find", "ls"]
  },
  "profiles": { "default": "best" },
  "artifacts": { "root": ".chrysalis" },
  "extensions": [
    "@chrysalis/vcs-git",
    "@chrysalis/web"
  ]
}
```

The Pi extension (`ts/pi/chrysalis-extension.ts`) loads only the tool groups registered by enabled extensions.

### Extension API

Each optional package exports a single `register(pi)` function:

```typescript
// packages/web/ts/index.ts
import { globalToolRegistry } from "chrysalis-forge";
import { WEB_TOOL_DEFINITIONS, executeWebTool } from "./web-tools.js";

export function register(pi: any): void {
  for (const def of WEB_TOOL_DEFINITIONS) {
    pi.registerTool({
      name: def.name,
      label: def.name.replace(/_/g, " "),
      description: def.description,
      parameters: def.parameters,
      async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
        const result = await executeWebTool(ctx.cwd, def.name, params);
        return { content: [{ type: "text", text: result }] };
      }
    });
  }
}
```

The core extension iterates `extensions` in config and calls each `register(pi)`:

```typescript
// In chrysalis-extension.ts, after registering core tools:
const config = await loadConfig(ctx.cwd);
for (const extName of config.extensions ?? []) {
  try {
    const ext = await import(extName);
    if (typeof ext.register === "function") {
      ext.register(pi);
    }
  } catch {
    notify(ctx, `Extension load failed: ${extName}`);
  }
}
```

---

## 5. Store Layer Split

The store layer currently lives in `ts/core/stores/`. As part of modularization:

| Store | Belongs To | Reason |
|-------|-----------|--------|
| `context-store.ts` | core | Session/context persistence |
| `eval-store.ts` | core | Evolution learning data |
| `session-stats.ts` | core | Telemetry |
| `trace-store.ts` | core | Execution traces |
| `thread-store.ts` | core | Thread hierarchy |
| `rollback-store.ts` | core | File safety |
| `store-registry.ts` | core | Dynamic stores |
| `cache-store.ts` | `@chrysalis/cache` | Web caching |
| `rdf-store.ts` | `@chrysalis/rdf` | Knowledge graph |
| `vector-store.ts` | `@chrysalis/rdf` | Semantic vectors (or separate package) |
| `decomp-archive.ts` | core | Planner pattern archive |

Each optional package with stores exports a `setupStores(cwd)` function that creates its JSON files on first use.

---

## 6. CLI Impact

### Commands in `ts/cli/main.ts`

Some CLI commands correspond to optional tools. They should be gated behind availability checks:

| Command | Tool Group | Action |
|---------|-----------|--------|
| `cache-stats` | `@chrysalis/cache` | Move to `chrysalis cache stats` (subcommand) |
| `rdf-load` / `rdf-query` / `rdf-insert` | `@chrysalis/rdf` | Move to `chrysalis rdf load` etc. |
| `stores` | core | Keep as-is |
| `rollback` | core | Keep as-is |
| `decomp` | core | Keep as-is |

This keeps the top-level CLI flat for core concerns and namespace-optional features.

---

## 7. Implementation Phases

### Phase 1: Extract without breaking (one package at a time)

1. **Create `packages/` directory** with `.gitkeep`.
2. **Extract `@chrysalis/vcs-jj`** — highest bang for buck (10 tools, niche userbase).
   - Copy `jj-tools.ts` into `packages/vcs-jj/`.
   - Add `register()` export.
   - Remove `JJ_TOOL_DEFINITIONS` from `ALL_TOOL_GROUPS` in `chrysalis-extension.ts`.
   - Remove jj CLI commands from `ts/cli/main.ts`.
   - Update docs.
3. **Extract `@chrysalis/rdf`** — clearly separate concern.
   - Move `rdf-tools.ts`, `rdf-store.ts`.
   - Move rdf CLI commands to `chrysalis rdf <sub>`.
4. **Extract `@chrysalis/cache`** — dependency of web, small surface.
   - Move `cache-tools.ts`, `cache-store.ts`.
   - Move `cache-stats` CLI to `chrysalis cache stats`.

### Phase 2: Extract mid-size packages

5. **Extract `@chrysalis/vcs-git`** — 7 tools, many users will want this.
6. **Extract `@chrysalis/web`** — 2 tools but requires `@chrysalis/cache`.
7. **Extract `@chrysalis/eval`** — judge + test tools, heavy LLM usage.
8. **Extract `@chrysalis/concurrent`** — sub-agent spawning.

### Phase 3: Cleanup and monorepo tooling

9. Publish all packages to npm under `@chrysalis/*` scope.
10. Update `chrysalis.config.json` schema documentation.
11. Update README to show "Core + Optional" install story:
    ```bash
    # Core only
    npm install -g chrysalis-forge

    # With git and web
    npm install -g chrysalis-forge @chrysalis/vcs-git @chrysalis/web
    ```

---

## 8. Files to Modify

| File | Changes |
|------|---------|
| `ts/core/tools/index.ts` | Remove exports for optional tools |
| `ts/pi/chrysalis-extension.ts` | Replace `ALL_TOOL_GROUPS` with extensible registry; load config extensions |
| `ts/cli/main.ts` | Gate optional commands; move some to subcommands |
| `ts/core/stores/index.ts` | Remove exports for optional stores |
| `ts/core/types.ts` | Ensure no optional types leak into core interfaces |
| `package.json` | Update to monorepo workspace root if using npm/yarn workspaces |
| `chrysalis.config.json` | Document `extensions` field |
| `README.md` | Update tool tables to show core vs optional |
| `doc/ARCHITECTURE.md` | Document the extension/package model |

---

## 9. Backward Compatibility

- Existing `chrysalis-forge` installs get the **core + all optional** equivalent via a meta-package or a compatibility layer.
- The default `extensions` array in `chrysalis.config.json` can start populated with all packages for existing users.
- New installs default to **core only** and require explicit opt-in.

---

## Summary

| Metric | Before | After (core) | Optional |
|--------|--------|--------------|----------|
| Tool files | 14 | 6 | 8 (extracted) |
| Tools | 66 | 32 | 34 |
| Store files | 11 | 7 | 4 |
| Dependencies | All bundled | Minimal | Per-package |

The result: a lean, focused core that does one thing well (self-evolution), surrounded by composable packages for VCS, web, evaluation, concurrency, and semantic memory.
