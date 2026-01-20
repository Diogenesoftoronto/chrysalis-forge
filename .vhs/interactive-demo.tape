Output .vhs/interactive-demo.gif
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "catppuccin-mocha"
Set Shell "bash"

# Show interactive mode with new commands
Type "chrysalis -i"
Enter
Sleep 1s

# Use a fast model for the demo
Type "/config model glm-4.5-air"
Enter
Sleep 0.8s
Type "/priority fast"
Enter
Sleep 0.6s

# Show config list
Type "/config list"
Enter
Sleep 2s

# Show models command
Type "/models"
Enter
Sleep 3s

# Show workflows command
Type "/workflows"
Enter
Sleep 2s

# Show help
Type "/help"
Enter
Sleep 2s

# Exit
Type "/exit"
Enter
Sleep 1s
