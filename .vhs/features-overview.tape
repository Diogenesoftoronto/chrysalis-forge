Output .vhs/features-overview.gif
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "catppuccin-mocha"
Set Shell "bash"

# Overview: Show help and one example
Type "chrysalis --help"
Enter
Sleep 2s
Type "echo ''"
Enter
Sleep 0.5s
Type "chrysalis --model glm-4.5-air --priority fast 'Write a haiku about coding'"
Enter
Sleep 8s
