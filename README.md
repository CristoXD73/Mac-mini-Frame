# Mac-mini-Frame: Console Mode

Turns a Mac into a controller-driven game console. Press the Xbox button and the Mac becomes a console:
- other apps are paused and hidden;
- extra displays show an animated starfield (or a Now Playing card);
- a GPU-rendered Steam Big Picture comes up;
- Windows games run through CrossOver as regular tiles.

Hold the Xbox button 6 seconds to go back to the desktop.

![Console Mode screens](docs/images/takeover-frames.jpg)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/CristoXD73/Pergolas/claude/steam-console-macos-perf-4lbx1k/install.sh | zsh
```

This downloads the source to `~/Mac-mini-Frame`, builds it, installs **Console Mode** to `/Applications` and starts it in the background. Run it again to update. From a checkout, `./install.sh` does the same.

**Needs:** macOS 15+, Apple's Command Line Tools (the installer offers them), [Steam for Mac](https://store.steampowered.com), and [CrossOver](https://www.codeweavers.com/crossover) with a bottle named **`Steam`** for Windows games.

**One-time setup** (System Settings):

| Setting | Why |
|---|---|
| Game Controllers › your controller › **Home button → Console Mode** | the Xbox button opens it |
| Privacy & Security › **Accessibility** → Console Mode | instant (≈1 s) start |
| Privacy & Security › **Screen & System Audio Recording** → Console Mode | screenshots |
| General › Login Items › remove **Steam** | Console Mode starts Steam quietly itself |

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/CristoXD73/Pergolas/claude/steam-console-macos-perf-4lbx1k/uninstall.sh | zsh
```

What it removes:
- the app and its background agents;
- only the Steam tiles Console Mode added.

What it keeps:
- your save backups;
- your games, bottle and own shortcuts.

To also delete internal-drive backups, settings and logs, run `~/Mac-mini-Frame/uninstall.sh --purge`, or append `-s -- --purge` to the one-liner.

## Using it

| Controller | Action |
|---|---|
| **Xbox** | game mode: Big Picture, apps paused, other screens taken over |
| **Hold Xbox 6 s** | back to the desktop |
| Xbox + **D-pad ↑↓** | volume (hold to repeat) |
| Xbox + **Y** | CPU / GPU / RAM / storage overlay |
| Xbox + **View** | screenshot → `~/Pictures/Console Mode` |
| Xbox + **X** | Quick Resume: suspend or resume the game |
| Xbox + **Menu + View** (twice) | force quit the game |
| Xbox + **LB** | Save Rewind: roll a game's saves back to an earlier point |

**Adding games:**
- **Installed through the bottle's Steam:** they appear as tiles automatically, with cover art.
- **Any other Windows game you own:** quit Mac Steam, then run
  ```bash
  "/Applications/Console Mode.app/Contents/Resources/add-game" "Game Name" exe "/path/to/Game.exe"
  ```
  It shows up in Big Picture › Library › **Non-Steam**.

**Settings** (optional) go in `~/Library/Application Support/Console Mode/config.json`:
```json
{ "gamesDrive": "/Volumes/Games", "backupDest": "/Volumes/Backup/Console Mode/Save Backups",
  "keepSteamLoaded": true, "nowPlaying": true, "gamingAudioOutput": "LG TV", "lowStorageGB": 50 }
```

## Docs

- [`docs/HANDOFF.md`](docs/HANDOFF.md): full design, every hard-won finding, setup and test status.
- [`docs/AI-HANDOFF.md`](docs/AI-HANDOFF.md): state of the repo for the next AI or developer.

Build from source: `./build.sh` (`--no-install` to only build). Tests: `zsh tests/test_scripts.sh`.
