#!/bin/bash
# Tests for the zsh resource scripts (bottle-launch, watchdog) using a fake
# wine and a fake bottle-windows. Needs zsh (stock on macOS).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
check() { if eval "$2"; then PASS=$((PASS+1)); echo "ok   $1"; else FAIL=$((FAIL+1)); echo "FAIL $1"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export CM_LOG="$T/log" CM_BOTTLE="$T/bottle" CM_POLL=1
mkdir -p "$CM_BOTTLE/drive_c/Program Files (x86)/Steam"; : > "$CM_BOTTLE/drive_c/Program Files (x86)/Steam/steam.exe"
cat > "$T/wine" <<'W'
#!/bin/bash
printf '%s|' "$@" >> "$(dirname "$0")/wine.calls"; echo >> "$(dirname "$0")/wine.calls"
W
cat > "$T/windows" <<'W'
#!/bin/bash
[ -f "$(dirname "$0")/window" ] && cat "$(dirname "$0")/window"
W
chmod +x "$T/wine" "$T/windows"
export CM_WINE="$T/wine" CM_BOTTLE_WINDOWS="$T/windows"

# --- steam launch: window appears at ~2s, closes at ~4s
( sleep 2; echo "Cyberpunk2077.exe" > "$T/window"; sleep 2; rm -f "$T/window" ) &
start=$(date +%s)
CM_GONE_SECS=2 zsh "$ROOT/resources/bottle-launch" steam 1091500; rc=$?
elapsed=$(( $(date +%s) - start ))
check "steam launch exits 0 after window closes" '[ $rc -eq 0 ]'
check "waited for the window to close (>=5s, was ${elapsed}s)" '[ $elapsed -ge 5 ]'
check "wine called with bottle + applaunch" 'grep -q "^--bottle|Steam|C:\\\\Program Files (x86)\\\\Steam\\\\steam.exe|-silent|-applaunch|1091500|" "$T/wine.calls"'
check "logged game window" 'grep -q "game window up: Cyberpunk2077.exe" "$CM_LOG"'

# --- a brief flicker (window gone 1s) must not end the session
: > "$T/wine.calls"
( sleep 1; echo "g.exe" > "$T/window"; sleep 2; rm -f "$T/window"; sleep 1; echo "g.exe" > "$T/window"; sleep 2; rm -f "$T/window" ) &
start=$(date +%s)
CM_GONE_SECS=3 zsh "$ROOT/resources/bottle-launch" steam 620
elapsed=$(( $(date +%s) - start ))
check "flicker tolerated (ran ${elapsed}s >= 8s)" '[ $elapsed -ge 8 ]'

# --- exe launch
mkdir -p "$T/My Game"; : > "$T/My Game/game.exe"; : > "$T/wine.calls"
( sleep 1; echo "game.exe" > "$T/window"; sleep 1; rm -f "$T/window" ) &
CM_GONE_SECS=1 zsh "$ROOT/resources/bottle-launch" exe "$T/My Game/game.exe"
check "exe launch uses --workdir" 'grep -qF -- "--bottle|Steam|--workdir|$T/My Game|$T/My Game/game.exe|" "$T/wine.calls"'

# --- errors
CM_START_TIMEOUT=2 zsh "$ROOT/resources/bottle-launch" steam 620; rc=$?
check "no window -> exit 2" '[ $rc -eq 2 ]'
zsh "$ROOT/resources/bottle-launch" steam abc 2>/dev/null; rc=$?
check "bad appid -> exit 1" '[ $rc -eq 1 ]'
zsh "$ROOT/resources/bottle-launch" exe /nope.exe 2>/dev/null; rc=$?
check "missing exe -> exit 1" '[ $rc -eq 1 ]'

# --- watchdog
sleep 60 & victim=$!
kill -STOP $victim
export CM_FROZEN="$T/frozen.json"
printf '{"pids":[%d,999999],"hidden":["com.apple.Safari"]}' $victim > "$CM_FROZEN"
state() { ps -o stat= -p "$1" | cut -c1; }
check "victim is paused" '[ "$(state $victim)" = T ]'
CM_PROC_NAME=bash zsh "$ROOT/resources/watchdog"   # stands in for a running ConsoleMode
check "watchdog leaves things alone while app runs" '[ -f "$CM_FROZEN" ] && [ "$(state $victim)" = T ]'
CM_PROC_NAME=NoSuchProcessXYZ zsh "$ROOT/resources/watchdog"
check "watchdog resumes paused pid" '[ "$(state $victim)" != T ]'
check "watchdog removes frozen.json" '[ ! -f "$CM_FROZEN" ]'
kill $victim 2>/dev/null
CM_PROC_NAME=NoSuchProcessXYZ zsh "$ROOT/resources/watchdog"; rc=$?
check "watchdog no-op without file" '[ $rc -eq 0 ]'

echo; echo "$PASS passed, $FAIL failed"; [ $FAIL -eq 0 ]
