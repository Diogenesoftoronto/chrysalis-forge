# Changelog

All notable changes to Chrysalis Forge are documented here.

## 0.5.0 — 2026-06-02

### Modular extensions

The optional tool surface now ships as standalone `@chrysalis/*` packages that
load from configuration, keeping the self-evolution core lean.

- **New optional packages**: `@chrysalis/vcs-jj` (Jujutsu), `@chrysalis/web`
  (fetch/search), `@chrysalis/cache` (TTL cache), `@chrysalis/rdf` (triplestore +
  vector search), and `@chrysalis/concurrent` (sub-agent spawning).
- **`extensions` config**: list packages under `extensions` in
  `chrysalis.config.json` to enable them. The default enables all five for
  backward compatibility; set `"extensions": []` for a core-only install.
- **Extension loader**: resolves each entry from the local `packages/` workspace
  first, then as a bare npm specifier when installed separately. Tools *and*
  slash commands ship together, so a disabled extension contributes neither — and
  a missing or broken package never breaks the core agent.
- **`@chrysalis/web` now depends on `@chrysalis/cache`** instead of carrying a
  private copy of the cache logic — one shared, tag-aware, TTL-bounded store.
- npm workspaces, per-package `tsconfig`/build, and conditional `exports`
  (`bun` → source, node → `dist`).

### Fixes

- Tool-evolution novelty was scored against an empty variant set, so every
  candidate looked maximally novel and duplicates were never rejected. Novelty
  now scores against the accumulated variants.
- Routed the Thompson-sampling bandit update through its intended helper instead
  of an inlined duplicate.
- Fixed a callback-vs-promise `mkdir` misuse in the sub-agent package.

### Internal

- Enabled `noUnusedLocals` and cleared the resulting dead code across core and
  tests.
- Consolidated a `ProviderConfig` interface that had been duplicated in six
  files into `core/types.ts`.

## 0.4.0

- Full TypeScript migration of the Pi-powered harness, tools system, dynamic
  stores, decomposition planner, and evolution engine.
