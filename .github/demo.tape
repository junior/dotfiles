# Regenerate the README demo:  vhs .github/demo.tape   (from the repo root)
# Keep this file pure ASCII - multibyte chars mojibake through ttyd typing.
Output .github/demo.gif

Set Shell zsh
Set FontSize 16
Set Width 920
Set Height 520
Set Padding 16
Set TypingSpeed 55ms
Set Theme "Dracula"

Hide
Type "setopt interactivecomments && clear"
Enter
Show

Sleep 1s
Type "# one repo drives both machines - everything below is chezmoi-managed"
Enter
Sleep 1s
Type "chezmoi managed | head -8"
Enter
Sleep 2.5s
Type "chezmoi diff"
Enter
Sleep 1.5s
Type "# empty: machine and repo are in sync"
Enter
Sleep 1.5s
Type "grep -cE '^(brew|cask)' ~/.Brewfile"
Enter
Sleep 1s
Type "# every tool is declared, not remembered"
Enter
Sleep 1.5s
Type "kubectl krew list"
Enter
Sleep 2.5s
Type "mise ls"
Enter
Sleep 3.5s
