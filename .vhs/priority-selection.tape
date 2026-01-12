Output .vhs/priority-selection.gif
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "catppuccin-mocha"
Set Shell "bash"

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
