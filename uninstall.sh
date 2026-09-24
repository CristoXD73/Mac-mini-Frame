#!/bin/zsh
# Remove Mac-mini-Frame (Console Mode) from this Mac.
#
#   From a checkout:  ./uninstall.sh            (keeps your save backups)
#                     ./uninstall.sh --purge    (also deletes internal-drive save backups, settings and logs)
#   One line:         curl -fsSL https://raw.githubusercontent.com/CristoXD73/Pergolas/claude/steam-console-macos-perf-4lbx1k/uninstall.sh | zsh
#
# Never touches your games, your CrossOver bottle, your own Steam shortcuts, or the game's own save files.
set -uo pipefail

APP="/Applications/Console Mode.app"
SUPPORT="$HOME/Library/Application Support/Console Mode"
PURGE=0; [[ "${1:-}" == "--purge" ]] && PURGE=1

say() { print -P "%B==>%b $*"; }

# 1. Nothing may stay paused: resume anything game mode paused (SIGCONT is harmless otherwise).
if [[ -f "$SUPPORT/frozen.json" ]]; then
  say "Resuming apps paused by game mode"
  grep -oE '"pid" *: *[0-9]+' "$SUPPORT/frozen.json" | grep -oE '[0-9]+$' | while read pid; do kill -CONT "$pid" 2>/dev/null; done
fi

# 2. Quit Console Mode cleanly (it restores the desktop itself), force only as a last resort.
if pgrep -x ConsoleMode >/dev/null; then
  say "Quitting Console Mode"
  osascript -e 'quit app "Console Mode"' 2>/dev/null
  for i in {1..40}; do pgrep -x ConsoleMode >/dev/null || break; sleep 0.25; done
  pkill -x ConsoleMode 2>/dev/null
fi

# 3. Background agents (standby at login, watchdog)
for label in local.consolemode.standby local.consolemode.watchdog local.consolemode.xbox; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
say "Removed background agents"

# 4. Tiles Console Mode added to Mac Steam (Steam must be closed while its tile list is edited)
if [[ -x "$APP/Contents/Resources/add-game" ]]; then
  if pgrep -x steam_osx >/dev/null; then
    say "Closing Mac Steam to remove Console Mode's tiles"
    osascript -e 'quit app "Steam"' 2>/dev/null
    for i in {1..60}; do pgrep -x steam_osx >/dev/null || break; sleep 0.5; done
  fi
  "$APP/Contents/Resources/add-game" --uninstall 2>/dev/null && say "Removed Console Mode's Steam tiles (your own shortcuts are untouched)"
fi

# 5. The app
rm -rf "$APP" && say "Removed $APP"

# 6. Its data
if (( PURGE )); then
  rm -rf "$SUPPORT" "$HOME/Library/Logs/ConsoleMode.log"
  say "Purged settings, internal-drive save backups and logs"
else
  if [[ -d "$SUPPORT" ]]; then
    find "$SUPPORT" -mindepth 1 -maxdepth 1 ! -name "Save Backups" -exec rm -rf {} +
  fi
  say "Kept your save backups (external drive, and $SUPPORT/Save Backups if any). Use --purge to delete internal ones too."
fi

cat <<'EOF'

✓ Console Mode is uninstalled.

Optional clean-up in System Settings:
  • Game Controllers › your controller › Home button: set it back (e.g. "Games")
  • Privacy & Security › Accessibility / Screen Recording / Input Monitoring: remove "Console Mode"
EOF
