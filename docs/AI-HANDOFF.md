# Mac-mini-Frame: handoff to the next AI

State of the repo as of 2026-09-24 (second update), and what to do next. Read it together with [`HANDOFF.md`](HANDOFF.md). That file is the full design, every finding (§4: *don't re-learn these*), the setup and the test status. This file covers what changed, what's verified and what's left.

---

## 1. Repository and access

| | |
|---|---|
| Repo | https://github.com/CristoXD73/Pergolas (project name: **Mac-mini-Frame**) |
| Visibility | **Public.** Never commit usernames, account IDs, local IPs, keys or tokens |
| Branch | **`claude/steam-console-macos-perf-4lbx1k`** (also the default branch). No force-pushes, no PRs unless the owner asks |
| Install / uninstall | one-liners in the README (`install.sh`, `uninstall.sh` at the repo root) |

Write access comes from the owner (Claude GitHub App, a collaborator invite, or a repo-scoped token given through the tool's secret settings, never in chat or a file). Commit messages end with a co-author line.

---

## 2. What changed in this update, and why

The previous commit (`84c2bcd`) was a clean CI-tested **rebuild of the first handoff**. Nothing in it had run on the owner's Mac. This update replaces it with the version **developed and debugged live on the owner's Mac mini with the real controller** (a local Claude Code session on the Mac, 2026-09-24). Main differences:

| Area | Now |
|---|---|
| Controller | HID matches **only the gamepad interface** (usage page 1, usage 5/4). The Xbox controller's keyboard-like interface disconnects on every Xbox press and needs Input Monitoring; matching it broke the exit hold and made connecting random (HANDOFF §4 #29). |
| Start | Console Mode stays resident (**standby** LaunchAgent at login, Mac Steam preloaded with `-silent`). Big Picture is parked through Accessibility on exit, and re-entry takes ~1 s. Every start path behaves the same (#15–17, #28). |
| Games | Every Mac Steam tile is a small **wrapper `.app`** (Mac Steam can't launch scripts, #23). Launch screen, then Space-aware hand-off with **"Scooting over to your game…"** (#30), no duplicate instances, one game at a time (#24). |
| Features | **Quick Resume** (Xbox+X), **force quit** (Xbox+Menu+View ×2), **Save Rewind** (Xbox+LB, snapshots while playing plus restore with undo), glass **HUD** (Core Audio volume, exit ring), **Now Playing** card, battery/storage chip, optional audio routing |
| Safety | `build.sh` refuses to install during game mode and always quits cleanly. The watchdog resumes paused apps if Console Mode dies. The bottle-Steam warm-up and persistent `wineserver -p` were removed (they took the controller and blocked the CrossOver app, #26–27). |
| Portability | `gamesDrive` and `backupDest` come from `config.json` (defaults are the owner's `/Volumes/circular` and `/Volumes/Storage/...`) |
| Install | `install.sh` (requirement checks, clone or update to `~/Mac-mini-Frame`, build, standby) and `uninstall.sh` (resumes paused apps, removes agents, **only** Console Mode's tiles (`add-game --uninstall`), and the app; save backups are kept unless `--purge`) |

The previous rebuild's Python tests covered its own `CM_*`-hookable scripts and don't apply to these, so they were replaced by `tests/test_scripts.sh`. That script covers syntax of every script, the Save Rewind round trip (restore, undo, the guard), tile wrappers (create, list, lookup, uninstall keeping foreign shortcuts) and watchdog recovery. It runs in a throwaway home folder.

---

## 3. Verified on the owner's Mac (real controller, real games)

- Xbox press → game mode (0.1–1 s warm, ~5 s cold). A **real 6 s hold exits** once the gamepad-only fix is in place (log `13:21:57 → 13:22:03`). 5/5 restarts connect to the controller instantly.
- Pausing and resuming (35–43 processes; Claude and Steam protected), takeover on the second display, Big Picture leaves the screen on exit, focus returns to the previous app.
- Volume (Core Audio, 16 steps, hold-repeat), stats overlay, the glass HUD.
- Tiles: `add-game` wrappers launch through Mac Steam with no "choose an app" dialog. Portal 2 (bottle Steam) launched with the launch screen, "Scooting over", and the game in front (recorded every 100 ms with `tools/spacewatch.swift`). The duplicate-launch guard, and the Steam tile list and art, were verified inside Big Picture over the DevTools protocol.
- Save backups found and verified for real games. The Rewind restore/undo round trip passes.

## 4. Not verified yet

1. Quick Resume, force quit and Save Rewind **with the physical controller on a running game** (logic tested; buttons not pressed live).
2. The **Now Playing** card and **launch screen** with real art during a real game (only preview renders were reviewed).
3. The **"Scooting over"** fallback for a game whose window never reaches the current Space (the timing logic works in the Portal 2 recording).
4. PlayStation and Steam controllers, audio routing (only one output device on the test Mac), Focus Shortcuts, and Remote Play pairing.
5. `install.sh` on a clean Mac (it was run from a checkout only).
6. Steam's own **Guide-hold Power Menu** also opens during the 6 s exit hold. That's harmless but ugly; the fix is probably a Steam controller setting (open item).

## 5. Suggested next steps

1. Confirm §4 items 1–3 with the owner holding the controller. Read `~/Library/Logs/ConsoleMode.log`: every Xbox up/down and interface removal is logged (`hid: …`).
2. Look into the Guide-hold Power Menu in Steam's controller settings.
3. Keep `tests/test_scripts.sh` green, and add a test for every script change.

## 6. Ground rules (from the owner, binding)

- Never use the `/Volumes/Expansion` drive.
- The console look never appears on the play (main) screen. Other screens are taken over, never turned off.
- Pausing everything is fine ("nuclear"). Claude, Steam, CrossOver and system processes stay protected.
- **Test on real hardware, not just scripts.** Scripted tests inject input above the layer that failed (HANDOFF #27). Say plainly what couldn't be verified.
- Don't install while the owner is in game mode, and don't pop test windows on their screen without saying so.
- Only add games the owner has a right to play. Don't add or launch pirated copies; `add-game` is for their own games.
- Don't bypass Steam's integrity checks (no CRC forging of `steamwebhelper.exe`).

## 7. Communication notes

- The owner writes short messages, often from a phone, and prefers action over questions, but wants evidence (logs, recordings, screenshots), not assumptions.
- Project name: **Mac-mini-Frame**. The app keeps the name **Console Mode** (bundle `local.consolemode`) so existing permissions and the Home-button mapping keep working.
