---
name: delegating-to-gemini-cli
description: Delegates coding tasks to the Gemini CLI agent. Use when asked to use gemini, gemini-cli, or to spawn external agents for parallel work on multiple issues.
---

# Delegating to Gemini CLI

Orchestrates work delegation to the Gemini CLI agent for parallel task execution.

## When to Use

- User explicitly asks to use "gemini", "gemini cli", or "gemini-cli"
- Multiple independent issues need fixing in parallel
- Tasks benefit from a fresh context/agent perspective
- Offloading work to run concurrently while continuing other tasks

## Prerequisites

Verify gemini CLI is installed:
```bash
which gemini && gemini --version
```

## Model Selection

Always specify the model explicitly with `-m`. Only use Gemini 3 models:

```bash
gemini -m gemini-3-pro-preview "task description"
```

**Allowed models:**
- `gemini-3-pro-preview` - Best for complex coding tasks, refactoring, multi-file changes
- `gemini-3-flash` - Fast for simpler tasks, single-file fixes, quick edits

**Never use:** `gemini-2.5-pro`, `gemini-2.0-flash`, or any 2.x models.

## Execution Patterns

### Single Task (Direct)
```bash
gemini -m gemini-3-pro-preview -y "Fix the bug in src/foo.rkt on line 42. Read the file first, then implement the fix and run tests."
```

### Parallel Tasks (Via Subagents)
Use the `Task` tool to spawn subagents, each invoking gemini:

```
<Task>
  <description>Fix Issue #1: Description</description>
  <prompt>Use the gemini CLI to fix Issue #1.

Run this command:
```bash
cd /path/to/project && gemini -m gemini-3-pro-preview -y "Detailed task description with:
1. Files to read
2. Specific changes needed
3. Tests to run after"
```

Report back what changes were made.</prompt>
</Task>
```

### Key Flags

| Flag | Purpose |
|------|---------|
| `-m MODEL` | Specify model (required for consistent results) |
| `-y` | Auto-accept all actions (YOLO mode) - use for automated tasks |
| `-d` | Debug mode for troubleshooting |
| `-s` | Sandbox mode for safer execution |
| `--approval-mode auto_edit` | Auto-approve edits only, prompt for other actions |

## Task Description Best Practices

Structure prompts for gemini with:

1. **Context**: What file(s) to read first
2. **Requirements**: Numbered list of specific changes
3. **Verification**: Test command to run after changes
4. **Scope**: Be explicit about what NOT to change

Example:
```
"Fix the ANSI parser in src/tui/text/ansi.rkt to support 256-color codes.

Requirements:
1. Read the current implementation first
2. Add parsing for 38;5;N (256-color) sequences
3. Add parsing for 38;2;R;G;B (TrueColor) sequences
4. Add tests for new functionality
5. Do NOT modify existing 16-color handling

After changes, run: raco test src/tui/text/ansi.rkt"
```

## Creating GitHub Issues First

Before delegating, create detailed issues with `gh`:

```bash
gh issue create \
  --title "[Component] Brief description" \
  --label "bug" \
  --body 'Detailed markdown with:
- Problem description
- File locations with line numbers
- Root cause analysis
- Proposed solution
- Acceptance criteria'
```

Then reference issues in gemini prompts for traceability.

## Workflow: Issue Batch Processing

1. **Analyze codebase** for issues (grep TODOs, review docs, find bugs)
2. **Create GitHub issues** with `gh issue create` including file:line references
3. **Spawn subagents** each running gemini for one issue
4. **Collect results** from subagent summaries
5. **Verify** with build/test commands
6. **Report** consolidated status to user

## Error Handling

If gemini hits quota limits:
```
The model is overloaded. Please try again later.
```

Fallback options:
1. Switch to `gemini-3-flash` if using pro (or vice versa)
2. Implement the fix directly in the subagent
3. Queue the task for retry

## Verification After Delegation

Always verify gemini's work:
```bash
# Build check
raco make main.rkt

# Run tests
raco test src/

# Check for uncommitted changes
git status
git diff --stat
```

## Example: Full Workflow

```bash
# 1. Create issues
gh issue create --title "[TUI] Fix scroll bug" --label "bug" --body '...'

# 2. Spawn subagent with gemini task
# (via Task tool in Amp)

# 3. Verify results
raco test src/tui/
git diff
```
