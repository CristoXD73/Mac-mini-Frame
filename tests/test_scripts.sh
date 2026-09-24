#!/bin/zsh
# Tests for Console Mode's helper scripts. Everything runs in a throwaway fake home folder, so
# nothing on the machine (saves, Steam, the real app) is touched. macOS only (uses codesign).
ROOT="${0:A:h:h}"; R="$ROOT/resources"
PASS=0; FAIL=0
check() { if eval "$2"; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- syntax
for f in "$R/bottle-launch" "$R/watchdog" "$ROOT/build.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh"; do
  check "zsh syntax: ${f:t}" "zsh -n '$f'"
done
for f in "$R/add-game" "$R/backup-saves"; do
  check "python syntax: ${f:t}" "python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' '$f'"
done

# --- backup-saves: snapshot → change → restore → undo, and the restore guard
H="$T/home"; S="$H/Library/Application Support/CrossOver/Bottles/Steam/drive_c/users/crossover/Saved Games/Studio/MyGame"
mkdir -p "$S" "$H/dest"
B() { HOME="$H" CM_BACKUP_DEST="$H/dest" python3 "$R/backup-saves" "$@"; }
first() { B --list-json | python3 -c "import json,sys; g=json.load(sys.stdin)[0]; print([x['dir'] for x in g['snapshots'] if x['kind']==sys.argv[1]][int(sys.argv[2])])" "$1" "$2"; }
echo "v1" > "$S/slot1.sav"; START=$(( $(date +%s) - 5 )); B --since $START
echo "v2" > "$S/slot1.sav"; echo "new" > "$S/slot2.sav"; B --since $START
check "two snapshots recorded" '[ "$(B --list-json | python3 -c "import json,sys; print(len(json.load(sys.stdin)[0][\"snapshots\"]))")" = 2 ]'
B --restore "$(first auto -1)" >/dev/null
check "restore brings back the old save" '[ "$(cat "$S/slot1.sav")" = v1 ] && [ ! -f "$S/slot2.sav" ]'
B --restore "$(first before-restore 0)" >/dev/null
check "undo (before-restore snapshot) brings it all back" '[ "$(cat "$S/slot1.sav")" = v2 ] && [ "$(cat "$S/slot2.sav")" = new ]'
mkdir -p "$H/dest/Evil/x"; echo '{"source": "/etc"}' > "$H/dest/Evil/x/.manifest.json"
check "refuses to restore outside save folders" 'B --restore "$H/dest/Evil/x" | grep -q refusing'

# --- add-game: wrapper tiles, lookup, uninstall keeps foreign shortcuts
mkdir -p "$H/Library/Application Support/Steam/userdata/123/config" /tmp/cm-test-game && touch /tmp/cm-test-game/Game.exe
A() { HOME="$H" CM_ASSUME_STEAM_CLOSED=1 python3 "$R/add-game" "$@"; }
A "Test Game" exe "/tmp/cm-test-game/Game.exe" >/dev/null
W="$H/Library/Application Support/Console Mode/Tiles/Test Game.app"
check "wrapper app created" '[ -x "$W/Contents/MacOS/launch" ] && codesign -v "$W" 2>/dev/null'
check "wrapper runs bottle-launch with the target" 'grep -q "exe .*/tmp/cm-test-game/Game.exe" "$W/Contents/MacOS/launch"'
check "--list shows the tile" 'A --list | grep -q "Test Game: exe"'
ID=$(sed -n "s/^export CM_TILE_SHORTCUT=//p" "$W/Contents/MacOS/launch")
check "--lookup finds the tile by id" '[ "$(A --lookup $ID)" = "Test Game" ]'
HOME="$H" python3 - "$R/add-game" <<'PY'
import importlib.util, glob, os, sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("add_game", sys.argv[1]).load_module()
path = glob.glob(os.path.expanduser("~/Library/Application Support/Steam/userdata/*/config/shortcuts.vdf"))[0]
sc = m.load(path); sc["99"] = {"appid": 5, "AppName": "My Own Shortcut", "Exe": '"/Applications/Chess.app"', "LaunchOptions": ""}
m.save(path, sc)
PY
A --uninstall >/dev/null
check "--uninstall removes Console Mode's tiles" '! A --list | grep -q "Test Game"'
check "--uninstall keeps the user's own shortcuts" 'A --list | grep -q "My Own Shortcut"'
check "--uninstall removes the wrapper apps" '[ ! -d "$H/Library/Application Support/Console Mode/Tiles" ]'
rm -rf /tmp/cm-test-game

# --- watchdog: resumes paused processes when Console Mode isn't running
if pgrep -x ConsoleMode >/dev/null; then
  echo "skip watchdog test (Console Mode is running on this machine)"
else
  sleep 60 & P=$!; kill -STOP $P
  mkdir -p "$H/Library/Application Support/Console Mode" "$H/Library/Logs"
  echo "[{\"pid\": $P, \"path\": \"/bin/sleep\"}]" > "$H/Library/Application Support/Console Mode/frozen.json"
  HOME="$H" zsh "$R/watchdog"
  check "watchdog resumed the paused process" '[ "$(ps -o stat= -p $P | cut -c1)" != T ]'
  check "watchdog cleared frozen.json" '[ ! -f "$H/Library/Application Support/Console Mode/frozen.json" ]'
  kill $P 2>/dev/null
fi

echo "---- $PASS passed, $FAIL failed"
(( FAIL == 0 ))
