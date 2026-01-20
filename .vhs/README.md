# VHS Test Scripts

This directory contains [vhs](https://github.com/charmbracelet/vhs) scripts for generating end-to-end testing GIFs of the Chrysalis Forge CLI.

## Prerequisites

- [vhs](https://github.com/charmbracelet/vhs) installed (`go install github.com/charmbracelet/vhs@latest`)
- `ffmpeg` installed
- `ttyd` installed (optional, but recommended)

## Available Scripts

- `help.tape` - Demonstrates the help command and basic CLI usage
- `interactive-demo.tape` - Shows interactive mode with `/help` and `/exit` commands
- `priority-selection.tape` - Demonstrates natural language priority selection
- `security-levels.tape` - Shows different security level options
- `features-overview.tape` - Comprehensive overview of CLI features

## Regenerating GIFs

**Note**: The scripts install the package using `raco pkg install --auto --skip-installed` at the start, so the `chrysalis` launcher will be available (via whatever Racket install is on your `PATH`). The scripts assume they are run from the project root directory (or the `.vhs` subdirectory).

## Model + timing notes

- **Model used in tapes**: `glm-4.5-air` (set via `--model` or `/config model`).
- **API endpoint**: `chrysalis` uses `OPENAI_API_BASE` and `OPENAI_API_KEY` (or your provider’s equivalents) to talk to an OpenAI-compatible API. If `/models` fails, your endpoint may not support model listing.
- **Wait tuning**: the tapes currently use conservative `Sleep 8s` waits for agent responses. If your environment is faster/slower, adjust those `Sleep` values.

To regenerate all GIFs:

```bash
cd .vhs
vhs help.tape
vhs interactive-demo.tape
vhs priority-selection.tape
vhs security-levels.tape
vhs features-overview.tape
```

Or regenerate a specific GIF:

```bash
vhs .vhs/help.tape
```

## Customization

Edit the `.tape` files to customize:
- Terminal size (`Set Width`, `Set Height`)
- Font size (`Set FontSize`)
- Theme (`Set Theme`)
- Timing (`Sleep` durations)
- Commands and interactions

See the [vhs documentation](https://github.com/charmbracelet/vhs) for more details.
