---
name: ax-workflows
description: Use Ax for structured planning and evaluation instead of inventing another prompt DSL.
---

# Ax Workflows

Use this skill when the task needs structured reasoning, recommendation, or evaluation.

Rules:

- prefer Ax programs for typed planning/evaluation flows
- keep the first version narrow and operational
- fall back to deterministic heuristics if model credentials are unavailable
- write plan artifacts to `.chrysalis/outputs/plans/`
