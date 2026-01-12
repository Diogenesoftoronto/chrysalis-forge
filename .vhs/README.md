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

**Note**: The scripts automatically install the package using `raco pkg install --auto` at the start, so the `chrysalis` command will be available. The scripts assume they are run from the project root directory (or the `.vhs` subdirectory).

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
