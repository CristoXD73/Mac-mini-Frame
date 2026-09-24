#!/bin/zsh
# Install Mac-mini-Frame (Console Mode) on this Mac.
#
#   From a checkout:  ./install.sh
#   One line:         curl -fsSL https://raw.githubusercontent.com/CristoXD73/Mac-mini-Frame/claude/steam-console-macos-perf-4lbx1k/install.sh | zsh
#
# Builds Console Mode from source, installs it to /Applications, and starts it in the background.
# Safe to run again to update.
set -euo pipefail

REPO="https://github.com/CristoXD73/Mac-mini-Frame.git"
BRANCH="claude/steam-console-macos-perf-4lbx1k"
SRC="${CM_SRC:-$HOME/Mac-mini-Frame}"

say()  { print -P "%B==>%b $*"; }
warn() { print -P "%F{yellow}!%f  $*"; }
die()  { print -P "%F{red}✗%f  $*"; exit 1; }

# 1. Requirements
[[ "$(uname)" == Darwin ]] || die "macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 15 )) || die "Needs macOS 15 or newer (this Mac has $(sw_vers -productVersion))."
if ! xcrun --find swiftc >/dev/null 2>&1; then
  warn "Apple's Command Line Tools are needed to build. Starting their installer…"
  xcode-select --install 2>/dev/null || true
  die "Finish installing the Command Line Tools, then run this again."
fi
command -v python3 >/dev/null || die "python3 is missing (it comes with the Command Line Tools)."
command -v git >/dev/null || die "git is missing (it comes with the Command Line Tools)."

# 2. Source: this checkout, or clone / update one in ~/Mac-mini-Frame
here="${0:A:h}"
if [[ -f "$here/build.sh" && -d "$here/src" ]]; then
  SRC="$here"
  say "Using this checkout: $SRC"
elif [[ -d "$SRC/.git" ]]; then
  say "Updating $SRC"
  git -C "$SRC" fetch -q origin "$BRANCH" && git -C "$SRC" checkout -q "$BRANCH" && git -C "$SRC" pull -q --ff-only origin "$BRANCH"
else
  say "Downloading to $SRC"
  git clone -q -b "$BRANCH" "$REPO" "$SRC"
fi

# 3. Build + install (build.sh refuses while game mode is active, quits the old copy cleanly,
#    installs to /Applications and starts it in standby)
say "Building and installing Console Mode"
( cd "$SRC" && ./build.sh )

# 4. What the rest of the setup needs
[[ -d "/Applications/Steam.app" ]] || warn "Mac Steam isn't installed: get it from store.steampowered.com (Console Mode uses its Big Picture)."
ls -d /Applications/CrossOver*.app >/dev/null 2>&1 || warn "CrossOver isn't installed: it runs the Windows games (a bottle named \"Steam\" is expected)."

cat <<'EOF'

✓ Console Mode is installed and running in the background.

One-time setup (System Settings):
  1. Game Controllers › your controller › Home button  →  open app  →  Console Mode
  2. Privacy & Security › Accessibility                →  turn on Console Mode  (instant start)
  3. Privacy & Security › Screen & System Audio Recording → turn on Console Mode (screenshots)
  4. General › Login Items: remove Steam if it's there (Console Mode starts it quietly itself)

Optional settings: ~/Library/Application Support/Console Mode/config.json, for example
  { "gamesDrive": "/Volumes/Games", "backupDest": "/Volumes/Backup/Console Mode/Save Backups" }

Add a Windows game (quit Mac Steam first):
  "/Applications/Console Mode.app/Contents/Resources/add-game" "Game Name" exe "/path/to/Game.exe"

Press the Xbox button to start. Hold it for 6 seconds to go back to the desktop.
Uninstall:  ~/Mac-mini-Frame/uninstall.sh   (or the one-line version in the README)
EOF
