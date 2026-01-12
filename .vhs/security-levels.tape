Output .vhs/security-levels.gif
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

# Show security level options
Type "chrysalis --perms 0 -h"
Enter
Sleep 1s
Type "chrysalis --perms 1 -h"
Enter
Sleep 1s
Type "chrysalis --perms 2 -h"
Enter
Sleep 1s
Type "chrysalis --perms god -h"
Enter
Sleep 2s
