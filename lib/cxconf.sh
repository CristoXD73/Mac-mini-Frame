# shellcheck shell=bash
# Read/write keys in CrossOver's cxbottle.conf, whose entries look like:
#
#   [EnvironmentVariables]
#   "WINEMSYNC" = "1"
#
# Edits are done with awk into a temp file and then moved into place, so a
# failure never leaves a half-written config.

# cxconf_get FILE SECTION KEY  -> prints value, returns 1 if absent
cxconf_get() {
  awk -v sec="[$2]" -v key="$3" '
    function trim(s) { gsub(/^[ \t]+|[ \t\r]+$/, "", s); return s }
    /^[ \t]*\[/ { in_sec = (trim($0) == sec); next }
    in_sec {
      line = $0
      if (match(line, /^[ \t]*"[^"]*"[ \t]*=/)) {
        k = line; sub(/^[ \t]*"/, "", k); sub(/".*/, "", k)
        if (k == key) {
          v = substr(line, RLENGTH + 1); v = trim(v)
          sub(/^"/, "", v); sub(/"$/, "", v)
          print v; found = 1; exit
        }
      }
    }
    END { exit found ? 0 : 1 }
  ' "$1"
}

# cxconf_set FILE SECTION KEY VALUE  (creates the section if missing)
cxconf_set() {
  _cxconf_edit "$1" "$2" "$3" "$4" set
}

# cxconf_unset FILE SECTION KEY
cxconf_unset() {
  _cxconf_edit "$1" "$2" "$3" "" unset
}

_cxconf_edit() {
  local file="$1" tmp
  tmp="$(mktemp "${file}.XXXXXX")" || return 1
  if awk -v sec="[$2]" -v key="$3" -v val="$4" -v mode="$5" '
    function trim(s) { gsub(/^[ \t]+|[ \t\r]+$/, "", s); return s }
    function emit() { printf "\"%s\" = \"%s\"\n", key, val; done = 1 }
    /^[ \t]*\[/ {
      if (in_sec && !done && mode == "set") emit()
      in_sec = (trim($0) == sec); if (in_sec) seen = 1
      print; next
    }
    in_sec && match($0, /^[ \t]*"[^"]*"[ \t]*=/) {
      k = $0; sub(/^[ \t]*"/, "", k); sub(/".*/, "", k)
      if (k == key) {
        if (mode == "set" && !done) emit()
        next
      }
    }
    { print }
    END {
      if (mode != "set" || done) exit
      if (!seen) printf "\n%s\n", sec
      emit()
    }
  ' "$file" > "$tmp"; then
    # Keep the original file mode.
    chmod "$(_file_mode "$file")" "$tmp" 2>/dev/null || true
    mv "$tmp" "$file"
  else
    rm -f "$tmp"; return 1
  fi
}

_file_mode() {
  # GNU first: on Linux `stat -f` means filesystem status and "succeeds".
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo 644
}
