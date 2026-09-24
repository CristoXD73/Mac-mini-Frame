#!/bin/bash
# Test suite for mac-mini-frame. Builds a fake CrossOver install and bottle in a
# temp dir (with a stub `wine` that records calls and writes registry values),
# so it runs anywhere — including CI on macOS with the stock bash 3.2.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TOOL="$ROOT/bin/mac-mini-frame"
# TEST_BASH lets CI/devs run the tool under a specific bash (e.g. 3.2).
st() { "${TEST_BASH:-bash}" "$TOOL" "$@"; }
export NO_COLOR=1

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'; }
assert_contains() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "expected to find: $3"$'\n'"in: $2" ;; esac; }
assert_not_contains() { case "$2" in *"$3"*) fail "$1" "did not expect: $3"$'\n'"in: $2" ;; *) pass "$1" ;; esac; }
assert_eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$3] got [$2]"; fi; }

setup() {
  T="$(mktemp -d)"
  export CX_APP="$T/CrossOver.app"
  export CX_BOTTLES="$T/Bottles"
  export STEAM_BOTTLE="Steam"
  unset CX_BIN DRY_RUN
  mkdir -p "$CX_APP/Contents/SharedSupport/CrossOver/bin"
  cat > "$CX_APP/Contents/Info.plist" <<'EOF'
<plist><dict>
<key>CFBundleShortVersionString</key>
<string>25.1.0</string>
</dict></plist>
EOF
  # Stub wine: log argv; emulate `reg add` by appending to user.reg.
  cat > "$CX_APP/Contents/SharedSupport/CrossOver/bin/wine" <<'EOF'
#!/bin/bash
echo "$*" >> "$CX_BOTTLES/wine-calls.log"
[ "$1" = --bottle ] || exit 3
b="$CX_BOTTLES/$2"; shift 2
if [ "$1" = reg ] && [ "$2" = add ]; then
  key="$(printf '%s' "$3" | sed 's/^HKCU\\//; s/\\/\\\\/g')"
  name="$5"; type="$7"; data="$9"
  if [ "$type" = REG_DWORD ]; then v="dword:$(printf '%08x' "$data")"; else v="\"$data\""; fi
  printf '\n[%s] 1700000000\n"%s"=%s\n' "$key" "$name" "$v" >> "$b/user.reg"
fi
exit 0
EOF
  chmod +x "$CX_APP/Contents/SharedSupport/CrossOver/bin/wine"

  B="$CX_BOTTLES/Steam"
  mkdir -p "$B/drive_c/Program Files (x86)/Steam"
  : > "$B/drive_c/Program Files (x86)/Steam/steam.exe"
  cat > "$B/cxbottle.conf" <<'EOF'
;;; CrossOver bottle configuration
[Bottle]
"Encoding" = "UTF-8"
"Template" = "win10_64"

[EnvironmentVariables]
"WINEMSYNC" = "0"
"CX_GRAPHICS_BACKEND" = "dxvk"

[Wine]
"Version" = "25.1.0"
EOF
  chmod 600 "$B/cxbottle.conf"
  printf 'WINE REGISTRY Version 2\n\n[Software\\\\Wine\\\\Mac Driver] 1600000000\n"RetinaMode"="y"\n' > "$B/user.reg"
}
teardown() { rm -rf "$T"; }

# shellcheck source=SCRIPTDIR/../lib/cxconf.sh
. "$ROOT/lib/cxconf.sh"
# shellcheck source=SCRIPTDIR/../lib/flags.sh
. "$ROOT/lib/flags.sh"

# ---------------------------------------------------------------- cxconf lib
setup
C="$B/cxbottle.conf"
assert_eq "cxconf_get existing" "$(cxconf_get "$C" EnvironmentVariables WINEMSYNC)" "0"
cxconf_get "$C" EnvironmentVariables NOPE >/dev/null; assert_eq "cxconf_get missing -> 1" "$?" "1"
assert_eq "cxconf_get is section-scoped" "$(cxconf_get "$C" Wine Version)" "25.1.0"
cxconf_set "$C" EnvironmentVariables WINEMSYNC 1
assert_eq "cxconf_set replaces" "$(cxconf_get "$C" EnvironmentVariables WINEMSYNC)" "1"
assert_eq "no duplicate keys" "$(grep -c '"WINEMSYNC"' "$C")" "1"
cxconf_set "$C" EnvironmentVariables WINEDEBUG "-all"
assert_eq "cxconf_set adds" "$(cxconf_get "$C" EnvironmentVariables WINEDEBUG)" "-all"
assert_eq "new key lands in right section" \
  "$(awk '/^\[/{s=$0} /WINEDEBUG/{print s}' "$C")" "[EnvironmentVariables]"
cxconf_unset "$C" EnvironmentVariables CX_GRAPHICS_BACKEND
cxconf_get "$C" EnvironmentVariables CX_GRAPHICS_BACKEND >/dev/null; assert_eq "cxconf_unset" "$?" "1"
assert_eq "other sections untouched" "$(cxconf_get "$C" Bottle Template)" "win10_64"
cxconf_set "$C" NewSection Foo bar
assert_eq "creates missing section" "$(cxconf_get "$C" NewSection Foo)" "bar"
mode="$(stat -c '%a' "$C" 2>/dev/null || stat -f '%Lp' "$C")"
assert_eq "file mode preserved" "$mode" "600"
teardown

# ------------------------------------------------------------------- flags
assert_contains "lite disables CEF gpu compositing" "$(profile_flags lite)" "-cef-disable-gpu-compositing"
assert_not_contains "lite keeps CEF sandbox" "$(profile_flags lite)" "-no-cef-sandbox"
assert_contains "rescue drops sandbox" "$(profile_flags rescue)" "-no-cef-sandbox"
assert_eq "stock is empty" "$(profile_flags stock)" ""
profile_flags bogus >/dev/null; assert_eq "unknown profile fails" "$?" "1"

# --------------------------------------------------------------------- CLI
setup
out="$(st help)"; assert_contains "help works" "$out" "Usage: mac-mini-frame"
out="$(st flags --bigpicture)"
assert_contains "flags bigpicture" "$out" "-gamepadui"
assert_contains "flags default profile lite" "$out" "-cef-disable-d3d11"
out="$(st flags --profile stock)"; assert_eq "stock flags empty" "$out" ""
out="$(st flags --profile stock -- -silent)"; assert_eq "extra args passthrough" "$out" "-silent"
st flags --profile nope >/dev/null 2>&1; assert_eq "bad profile exit code" "$?" "1"
st frobnicate >/dev/null 2>&1; assert_eq "bad command exit code" "$?" "2"

out="$(st doctor 2>&1)"
assert_contains "doctor finds CrossOver version" "$out" "CrossOver 25.1.0"
assert_contains "doctor lists bottle" "$out" "- Steam"
assert_contains "doctor finds steam.exe" "$out" 'C:\Program Files (x86)\Steam\steam.exe'
assert_contains "doctor flags msync off" "$out" "MSync off"
assert_contains "doctor flags retina" "$out" "Retina"
assert_contains "doctor flags gpu webviews" "$out" "GPU web-view acceleration is on"

out="$(st --dry-run apply 2>&1)"
assert_contains "dry-run apply shows reg calls" "$out" "reg add"
assert_eq "dry-run apply leaves conf alone" "$(cxconf_get "$B/cxbottle.conf" EnvironmentVariables WINEMSYNC)" "0"

out="$(st apply --backend d3dmetal 2>&1)"; rc=$?
assert_eq "apply exit 0" "$rc" "0"
assert_eq "apply sets MSync" "$(cxconf_get "$B/cxbottle.conf" EnvironmentVariables WINEMSYNC)" "1"
assert_eq "apply sets WINEDEBUG" "$(cxconf_get "$B/cxbottle.conf" EnvironmentVariables WINEDEBUG)" "-all"
assert_eq "apply sets backend" "$(cxconf_get "$B/cxbottle.conf" EnvironmentVariables CX_GRAPHICS_BACKEND)" "d3dmetal"
calls="$(cat "$CX_BOTTLES/wine-calls.log")"
assert_contains "apply disables GPU webviews" "$calls" 'reg add HKCU\Software\Valve\Steam /v GPUAccelWebViewsV3 /t REG_DWORD /d 0 /f'
assert_contains "apply disables smooth scroll" "$calls" "SmoothScrollWebViews"
assert_contains "apply disables retina" "$calls" "RetinaMode /t REG_SZ /d n"
assert_eq "apply made backup + original" "$(ls "$B/.mac-mini-frame-backups" | wc -l | tr -d ' ')" "2"

out="$(st doctor 2>&1)"
assert_contains "doctor after apply: msync" "$out" "MSync enabled"
assert_contains "doctor after apply: webviews" "$out" "GPU web-view acceleration off"
assert_not_contains "doctor after apply: retina fixed" "$out" "Retina) mode ON"

st apply --backend auto >/dev/null 2>&1
cxconf_get "$B/cxbottle.conf" EnvironmentVariables CX_GRAPHICS_BACKEND >/dev/null
assert_eq "backend auto removes key" "$?" "1"
st apply --backend metalz >/dev/null 2>&1; assert_eq "bad backend rejected" "$?" "1"

assert_eq "repeat apply adds a backup, keeps original" "$(ls "$B/.mac-mini-frame-backups" | wc -l | tr -d ' ')" "3"
st restore >/dev/null 2>&1
assert_eq "restore latest = state before last apply" "$(cxconf_get "$B/cxbottle.conf" EnvironmentVariables WINEMSYNC)" "1"
st restore original >/dev/null 2>&1
assert_eq "restore brings back msync=0" "$(cxconf_get "$B/cxbottle.conf" EnvironmentVariables WINEMSYNC)" "0"
assert_eq "restore brings back backend" "$(cxconf_get "$B/cxbottle.conf" EnvironmentVariables CX_GRAPHICS_BACKEND)" "dxvk"
assert_not_contains "restore brings back user.reg" "$(cat "$B/user.reg")" "GPUAccelWebViewsV3"

out="$(st --dry-run launch --bigpicture 2>&1)"
assert_contains "dry-run launch runs steam.exe" "$out" 'Steam\\steam.exe'
assert_contains "dry-run launch has bigpicture" "$out" "-gamepadui"

: > "$CX_BOTTLES/wine-calls.log"
st launch --profile nogpu >/dev/null 2>&1; sleep 1
calls="$(cat "$CX_BOTTLES/wine-calls.log")"
assert_contains "launch invokes wine with bottle" "$calls" "--bottle Steam C:\\Program Files (x86)\\Steam\\steam.exe"
assert_contains "launch passes profile flags" "$calls" "-cef-disable-gpu "

st --bottle Nope doctor >/dev/null 2>&1; assert_eq "missing bottle fails" "$?" "1"

# Process detection: a shell merely mentioning steamwebhelper/steam.exe must
# not count as Steam running; a Wine-style C:\...\steam.exe process must.
bash -c 'sleep 3; : C:\\\\x\\\\steamwebhelper.exe steam.exe' & decoy=$!
st apply >/dev/null 2>&1; assert_eq "apply ignores unrelated cmdlines" "$?" "0"
kill "$decoy" 2>/dev/null; wait "$decoy" 2>/dev/null
bash -c 'exec -a "C:\\Program Files (x86)\\Steam\\steam.exe" sleep 3' & fake=$!
sleep 0.3
out="$(st apply 2>&1)"; assert_contains "apply refuses while steam.exe runs" "$out" "Steam is running"
st kill >/dev/null 2>&1
if kill -0 "$fake" 2>/dev/null; then fail "kill stops steam.exe"; kill "$fake"; else pass "kill stops steam.exe"; fi
wait "$fake" 2>/dev/null
teardown

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
