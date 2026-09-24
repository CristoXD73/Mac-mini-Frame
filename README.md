# Mac-mini-Frame

Turns a Mac mini into a game console you drive entirely with a controller. The app it builds is **Console Mode**. It uses native Mac Steam Big Picture as the menu, and the Windows games themselves run in a **CrossOver bottle**.

| Controller | What happens |
|---|---|
| **Press Xbox button** | **Game mode.** Other apps are hidden and paused. Every display except the main one shows an animated starfield. Mac Steam opens in Big Picture on the main display, and your bottle games appear there as tiles |
| Press again | Brings Big Picture, or the running game, back to the front |
| **Hold Xbox button 6 s** | **Back to PC.** The game and both Steam clients close, apps resume, and the starfield goes away. A countdown shows from 2 s |
| Xbox + D-pad up/down | Volume ±6% |
| Xbox + Y | CPU / GPU / RAM / clock overlay |
| Xbox + View | Screenshot to `~/Pictures/Console Mode/` |

When a game closes, the save folders it changed are backed up (and verified) to `/Volumes/Storage/Console Mode/Save Backups/`.

## Why not the bottle's own Big Picture?

Windows Steam detects macOS and starts its interface with `--disable-gpu`, and nothing outside Steam can change that. In the bottle, Big Picture navigates at **12–20 fps**. Native Mac Steam Big Picture runs at **52–60 fps**. So Mac Steam is the menu, and each tile starts the game inside the bottle through `bottle-launch`. The details, and what was already tried, are in [docs/HANDOFF.md §4](docs/HANDOFF.md).

## Setup

You need macOS 15+, Xcode Command Line Tools, CrossOver with GPTK4/D3DMetal, a bottle named `Steam` with Windows Steam installed, and Mac Steam signed in to the same account. Paths are set for the original Mac. [HANDOFF §9](docs/HANDOFF.md) lists the constants to change on a different machine.

```bash
git clone -b claude/steam-console-macos-perf-4lbx1k https://github.com/CristoXD73/Pergolas.git Mac-mini-Frame
cd Mac-mini-Frame
./build.sh                     # builds and installs /Applications/Console Mode.app
```

Then configure these once:

1. Set **System Settings › Game Controllers › (your controller) › Home button** to open **Console Mode**.
2. Turn on **System Settings › Privacy & Security › Screen & System Audio Recording** for Console Mode (needed for screenshots).
3. Remove Mac Steam from **Login Items**.
4. Optional: map the games drive as the bottle's `D:` and add it as a library in the bottle's Steam. See [HANDOFF §5](docs/HANDOFF.md) for this and the rest of the one-time setup.

Games installed in the bottle's Steam become Mac Steam tiles automatically each time game mode starts. To add any other Windows game:

```bash
R="/Applications/Console Mode.app/Contents/Resources"
python3 "$R/add-game" "My Game" exe "/Volumes/circular/Games/MyGame/game.exe"   # Mac Steam must be closed
python3 "$R/add-game" --list
```

## Layout

| Path | What |
|---|---|
| `src/` | The Swift app: `main` (state machine), `Input` (HID + GameController), `Freezer` (pause/resume + watchdog), `Takeover` (starfield), `Overlays`, `Power`, `Common` |
| `resources/` | Scripts bundled into the app: `bottle-launch`, `bottle-windows`, `add-game`, `backup-saves`, `watchdog` |
| `tools/` | `hidprobe.swift` (raw controller buttons), `render-preview.swift` (takeover frames to JPEG), `cdp.js`/`prof.js` (Big Picture fps over DevTools) |
| `tests/` | Tests for the scripts using a fake bottle, fake Mac Steam and fake wine |
| `docs/HANDOFF.md` | The full design, hard-won findings, and what is and isn't verified |
| `docs/AI-HANDOFF.md` | Current status, repo access, and next steps for whoever picks this up |

## Tests

```bash
python3 -m unittest discover -s tests -p 'test_*.py'   # add-game, backup-saves
bash tests/test_scripts.sh                             # bottle-launch, watchdog
./build.sh --no-install                                # compile the app (macOS only)
```

On every push, CI compiles the app on macOS 15, checks the signing requirement, renders a preview of the takeover animation (downloadable as a CI artifact), and runs the tests on macOS and Linux.

Logs are written to `~/Library/Logs/ConsoleMode.log`.
