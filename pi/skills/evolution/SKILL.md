# Evolution Workflows

Use this skill for prompt evolution, harness mutation, archive inspection, and profile-learning tasks.

## Operating Rules
- Prefer autonomous evolution as the default path; do not ask the user to run commands unless they explicitly want a manual override.
- Use `/evolve` only when the user is directly inspecting or forcing a system-prompt pass.
- Use `/meta-evolve` only when the user is directly inspecting or forcing an optimizer-prompt pass.
- Use `/harness` when the request is about context budget, tool routing, or execution style.
- Use `/archive` when the user wants to inspect prior variants.
- Use `/stats` when the user wants profile-learning or model-selection state.
- Keep changes terminal-first and archive-friendly.

## Output Expectations
- Be specific about what changed.
- Preserve deterministic file outputs under `.chrysalis`.
- Avoid GUI work unless the user explicitly asks for it.
