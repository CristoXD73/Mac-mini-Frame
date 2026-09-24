#!/bin/bash
# Double-click in Finder: start Steam straight into Big Picture (console UI)
# with the low-lag profile. Edit STEAM_BOTTLE if your bottle has another name.
export STEAM_BOTTLE="${STEAM_BOTTLE:-Steam}"
cd "$(dirname "$0")/.." && exec bin/mac-mini-frame launch --fresh --profile lite --bigpicture
