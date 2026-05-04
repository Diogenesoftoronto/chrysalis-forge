Output .vhs/evo-cycle.mp4
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "catppuccin-mocha"
Set Shell "bash"

# Full Evolution Cycle: evolve system prompt, then profile, then check stats
Type 'chrysalis evolve "prefer terminal-first concise responses"'
Enter
Sleep 3s

Type 'chrysalis profile fast'
Enter
Sleep 1s

Type 'chrysalis stats'
Enter
Sleep 2s

Type 'chrysalis archive'
Enter
Sleep 2s
