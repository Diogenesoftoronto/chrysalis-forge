Output .vhs/help.gif
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "catppuccin-mocha"
Set Shell "bash"

# Getting Started: Installation and Setup
# Set PATH to include Racket bin directory
Type "export PATH=/usr/local/racket/bin:$PATH"
Enter
Sleep 0.5s

# Install the package
Type "cd .. && /usr/local/racket/bin/raco pkg install --auto --skip-installed 2>&1 | tail -3 || true"
Enter
Sleep 3s

# Show help command
Type "chrysalis --help"
Enter
Sleep 2s

# Show interactive mode with help
Type "chrysalis -i"
Enter
Sleep 1s
Type "/help"
Enter
Sleep 3s
Type "/exit"
Enter
Sleep 1s
