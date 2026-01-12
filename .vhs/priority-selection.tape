Output .vhs/priority-selection.gif
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "catppuccin-mocha"
Set Shell "bash"

# Set PATH to include Racket bin directory so chrysalis will be available after install
Type "export PATH=/usr/local/racket/bin:$PATH"
Enter
Sleep 0.5s

# Install the package so chrysalis command is available
# Change to project root (parent of .vhs directory) and install
Type "cd .. && /usr/local/racket/bin/raco pkg install --auto --skip-installed 2>&1 | tail -3 || true"
Enter
Sleep 3s

# Show different priority options
Type "chrysalis --priority fast -h"
Enter
Sleep 1s
Type "chrysalis --priority cheap -h"
Enter
Sleep 1s
Type "chrysalis --priority 'I need accuracy' -h"
Enter
Sleep 2s
