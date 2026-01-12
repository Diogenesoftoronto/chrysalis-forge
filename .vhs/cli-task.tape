Output .vhs/cli-task.gif
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "catppuccin-mocha"
Set Shell "bash"

# Install the package so chrysalis command is available
# Change to project root (parent of .vhs directory) and install
Type "cd .. && raco pkg install --auto --skip-installed 2>&1 | tail -3 || true"
Enter
Sleep 3s

# Show CLI task execution
Type "chrysalis --priority fast 'What is 2+2?'"
Enter
Sleep 3s
