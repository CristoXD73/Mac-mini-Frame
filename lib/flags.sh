# shellcheck shell=bash
# Steam launch-flag profiles.
#
# Almost all of Steam's UI lag under CrossOver comes from steamwebhelper.exe,
# Steam's embedded Chromium (CEF). Under Wine its GPU process renders through
# ANGLE -> D3D11 -> (wined3d/DXMT/D3DMetal) -> Metal, which is slow and
# glitchy. Pushing CEF onto its software path and trimming startup work makes
# the client (and Big Picture) far more responsive on Apple silicon.

# Flags shared by every profile: skip startup work that is pure overhead.
FLAGS_COMMON="-noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles -cef-disable-breakpad -cef-disable-js-logging"

# lite: recommended default. Software-composited CEF, no DirectWrite.
FLAGS_LITE="-cef-disable-gpu-compositing -cef-disable-d3d11 -no-dwrite"

# nogpu: CEF fully off the GPU. Try this if 'lite' still stutters or menus
# render blank/black.
FLAGS_NOGPU="-cef-disable-gpu -cef-disable-gpu-compositing -cef-disable-d3d11 -no-dwrite"

# rescue: last resort when steamwebhelper keeps crashing / "not responding".
FLAGS_RESCUE="-cef-disable-gpu -cef-disable-gpu-compositing -cef-disable-d3d11 -cef-in-process-gpu -no-cef-sandbox -no-dwrite"

# stock: no tweaks at all (for A/B comparison).

# shellcheck disable=SC2034  # used by bin/mac-mini-frame
PROFILES="lite nogpu rescue stock"

# profile_flags NAME -> prints flags, returns 1 on unknown profile
profile_flags() {
  local p
  case "$1" in
    lite)   p="$FLAGS_LITE" ;;
    nogpu)  p="$FLAGS_NOGPU" ;;
    rescue) p="$FLAGS_RESCUE" ;;
    stock)  printf '%s' ""; return 0 ;;
    *)      return 1 ;;
  esac
  printf '%s %s' "$FLAGS_COMMON" "$p"
}

# ui_flag MODE -> flag that picks the UI Steam opens in
ui_flag() {
  case "$1" in
    desktop) printf '%s' "" ;;
    bigpicture) printf '%s' "-gamepadui" ;;   # new Big Picture (Steam Deck UI)
    *) return 1 ;;
  esac
}
