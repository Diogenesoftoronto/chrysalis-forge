Output .vhs/security-levels.gif
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "catppuccin-mocha"
Set Shell "bash"

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
