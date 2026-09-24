#!/bin/bash
# Double-click in Finder: start Steam (desktop UI) with the low-lag profile.
# Edit STEAM_BOTTLE below if your bottle isn't called "Steam".
export STEAM_BOTTLE="${STEAM_BOTTLE:-Steam}"
cd "$(dirname "$0")/.." && exec bin/steam-tune launch --fresh --profile lite
