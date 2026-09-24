#!/bin/zsh
# Build Console Mode.app and install it to /Applications.
#   ./build.sh            build + install (quits a running Console Mode first)
#   ./build.sh --no-install   build into ./build only
set -euo pipefail
cd "${0:A:h}"
APP="build/Console Mode.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "• compiling Console Mode"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/ConsoleMode" src/*.swift

echo "• compiling bottle-windows helper"
swiftc -O -o "$APP/Contents/Resources/bottle-windows" resources/bottle-windows.swift

cp app/Info.plist "$APP/Contents/Info.plist"
cp app/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for f in bottle-launch add-game backup-saves watchdog; do
  cp "resources/$f" "$APP/Contents/Resources/$f"; chmod +x "$APP/Contents/Resources/$f"
done

# Ad-hoc signature with a FIXED designated requirement. A plain ad-hoc signature ties macOS
# privacy permissions (Screen Recording) to the exact binary hash, so every rebuild would
# silently drop them. Pinning the requirement to the bundle identifier keeps them.
echo "• signing"
codesign --force -s - -r='designated => identifier "local.consolemode"' "$APP"

[[ "${1:-}" == "--no-install" ]] && { echo "built: $APP"; exit 0; }

# Never install in the middle of a game-mode session: restarting Console Mode mid-session unpauses
# and re-pauses every app. frozen.json exists exactly while apps are paused.
if [[ -f "$HOME/Library/Application Support/Console Mode/frozen.json" && "${1:-}" != "--force" ]]; then
  echo "✗ Console Mode is in game mode right now; not installing. Exit game mode first (or use --force)."
  exit 1
fi

echo "• installing to /Applications"
# Quit cleanly so Console Mode restores the desktop itself; force-kill only as a last resort.
osascript -e 'quit app "Console Mode"' 2>/dev/null || true
for i in {1..40}; do pgrep -x ConsoleMode >/dev/null || break; sleep 0.25; done
pkill -x ConsoleMode 2>/dev/null && echo "  (had to force-quit Console Mode)" || true
rm -rf "/Applications/Console Mode.app"
cp -R "$APP" "/Applications/Console Mode.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Console Mode.app"
echo "installed: /Applications/Console Mode.app"
open -g -a "/Applications/Console Mode.app" --args --standby     # back in the background, ready for the Xbox button
echo "restarted in standby"
