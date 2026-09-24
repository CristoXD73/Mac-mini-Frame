# shellcheck shell=bash
# Shared helpers. Must stay compatible with macOS's stock bash 3.2:
# no associative arrays, no ${var,,}, no mapfile, no `local -n`.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YLW=''; C_DIM=''; C_OFF=''
fi

info() { printf '%s\n' "$*"; }
ok()   { printf '%s✔%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YLW" "$C_OFF" "$*" >&2; }
err()  { printf '%s✘%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()  { err "$*"; exit 1; }
dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }

# DRY_RUN=1 prints commands instead of running them.
run() {
  if [ "${DRY_RUN:-0}" = 1 ]; then
    { printf '%s[dry-run]%s' "$C_DIM" "$C_OFF"; printf ' %q' "$@"; printf '\n'; } >&2
  else
    "$@"
  fi
}

# --- CrossOver locations (all overridable for testing) ---------------------

cx_app()       { printf '%s' "${CX_APP:-/Applications/CrossOver.app}"; }
cx_bin()       { printf '%s' "${CX_BIN:-$(cx_app)/Contents/SharedSupport/CrossOver/bin}"; }
cx_bottles()   { printf '%s' "${CX_BOTTLES:-$HOME/Library/Application Support/CrossOver/Bottles}"; }
bottle_name()  { printf '%s' "${STEAM_BOTTLE:-Steam}"; }
bottle_dir()   { printf '%s/%s' "$(cx_bottles)" "$(bottle_name)"; }
bottle_conf()  { printf '%s/cxbottle.conf' "$(bottle_dir)"; }
backup_dir()   { printf '%s/.mac-mini-frame-backups' "$(bottle_dir)"; }

# Prints the steam.exe path inside the bottle, or fails.
steam_exe() {
  local d c
  d="$(bottle_dir)/drive_c"
  for c in "Program Files (x86)/Steam/steam.exe" "Program Files/Steam/steam.exe"; do
    if [ -f "$d/$c" ]; then printf '%s/%s' "$d" "$c"; return 0; fi
  done
  return 1
}

# Windows-style path of steam.exe (what wine wants).
steam_exe_win() {
  local p rel
  p="$(steam_exe)" || return 1
  rel="${p#"$(bottle_dir)"/drive_c/}"
  # shellcheck disable=SC1003  # a literal backslash, not an escaped quote
  printf 'C:\\%s' "$(printf '%s' "$rel" | tr '/' '\\')"
}

cx_wine() { run "$(cx_bin)/wine" --bottle "$(bottle_name)" "$@"; }

require_bottle() {
  [ -d "$(bottle_dir)" ] || die "Bottle '$(bottle_name)' not found in $(cx_bottles). Use --bottle NAME (run 'mac-mini-frame doctor' to list bottles)."
  [ -f "$(bottle_conf)" ] || die "No cxbottle.conf in $(bottle_dir) — is this a CrossOver bottle?"
}

require_wine() {
  [ -x "$(cx_bin)/wine" ] || die "CrossOver's wine not found at $(cx_bin)/wine. Is CrossOver installed in /Applications? (override with CX_APP=...)"
}

# Wine rewrites a process's command line to its Windows path, e.g.
#   C:\Program Files (x86)\Steam\steam.exe -silent
# so anchor on that shape; a loose `pgrep -f steam` would also match shells,
# editors and greps that merely mention the name.
win_proc_re() { printf '^[A-Za-z]:\\\\.*\\\\%s( |$)' "$1"; }

# proc_running EXE_REGEX, e.g. proc_running 'steam\.exe'
proc_running() { pgrep -f "$(win_proc_re "$1")" >/dev/null 2>&1; }
