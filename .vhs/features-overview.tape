Output .vhs/features-overview.gif
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "catppuccin-mocha"
Set Shell "bash"

# Show various features
Type "echo '=== Chrysalis Forge CLI Demo ==='"
Enter
Sleep 1s
Type "chrysalis -h"
Enter
Sleep 2s
Type "echo ''"
Enter
Sleep 0.5s
Type "echo 'Priority options:'"
Enter
Sleep 0.5s
Type "chrysalis --priority fast -h 2>&1 | head -5"
Enter
Sleep 2s
Type "echo ''"
Enter
Sleep 0.5s
Type "echo 'Security levels:'"
Enter
Sleep 0.5s
Type "chrysalis --perms 1 -h 2>&1 | head -5"
Enter
Sleep 2s
