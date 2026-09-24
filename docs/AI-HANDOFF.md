# Mac-mini-Frame: handoff to the next AI

This is the state of the repo as of 2026-09-24, and what to do next. Read it with [`HANDOFF.md`](HANDOFF.md) in this folder. That file is the owner's original design spec for **Console Mode** (hardware, paths, and the findings you must not re-learn). This file says what has been built from that spec, what's verified, and what's left.

---

## 1. Repository and access

| | |
|---|---|
| Repo | https://github.com/CristoXD73/Pergolas (the owner may rename it to `Mac-mini-Frame`, and GitHub redirects the old URL) |
| Owner | GitHub user **CristoXD73** |
| Visibility | **Public**. Anyone can clone and read it, and CI logs are readable without auth |
| Branches | Only **`claude/steam-console-macos-perf-4lbx1k`**, which is also the **default branch** (the repo was empty before this work) |
| Open PRs | None |
| CI | `.github/workflows/ci.yml`, GitHub Actions, green on commit `84c2bcd` |

### Permissions: what you have and what you need

- **Read:** no credentials needed. `git clone https://github.com/CristoXD73/Pergolas.git`
- **Write (push, PRs, re-running CI):** needs access **granted by the owner to you**. No credentials are stored in this repo or in this document, and none should ever be committed. The owner can grant access in any of these ways:
  1. **Claude Code on the web / Claude GitHub App:** the owner connects GitHub at claude.ai and installs the Claude GitHub App on this repo (https://github.com/apps/claude/installations/select_target). The previous work was pushed this way.
  2. **Another AI's GitHub integration:** the owner installs that tool's GitHub App on `CristoXD73/Pergolas` with *Contents: read & write*, *Pull requests: read & write* and *Actions: read*.
  3. **Collaborator:** repo Settings → Collaborators → add the bot or person with *Write* role.
  4. **Fine-grained personal access token:** scoped to this one repo only, with the permissions above and a short expiry. The owner should give it to the AI through that tool's secret or environment settings, **never** in chat or in a file.
- **Push rules the previous AI followed:** work on `claude/steam-console-macos-perf-4lbx1k`, no force-pushes, and no PRs unless the owner asks. Commit messages end with a co-author line.

---

## 2. What the project is

The owner has a Mac mini (Apple M6, macOS 27, two 1080p displays, Xbox Wireless Controller over Bluetooth) and plays Windows games through a **CrossOver GPTK4 bottle named `Steam`**. **Console Mode** makes the Mac act like a console, driven by the controller:

- **Press the Xbox button:** other apps are hidden and paused (SIGSTOP). The other displays show a starfield. **Native Mac Steam Big Picture** opens on the main display, and bottle games appear there as tiles.
- **Hold the Xbox button 6 s:** back to the desktop. The game and both Steam clients close, and everything resumes.
- **Xbox + D-pad up/down** changes volume, **Xbox + Y** toggles the stats overlay, and **Xbox + View** takes a screenshot.
- Save folders are backed up after each game.

The key design decision (HANDOFF.md §4.1): the **bottle's** Big Picture is stuck at 12–20 fps. Windows Steam forces `--disable-gpu` on macOS, and nothing outside Steam fixes it. So the menu is **Mac** Steam, and each tile runs `bottle-launch`, which starts the game inside the bottle.

---

## 3. History

| Commit | What |
|---|---|
| `bb05746`, `a68b84f` | First attempt: `steam-tune`, a bash CLI that tuned the bottle (registry keys like `GPUAccelWebViewsV3=0`, CEF flags, MSync). **Superseded and deleted.** The owner's handoff showed these tweaks don't help the bottle's Big Picture (HANDOFF.md §4.1). Don't revive it. |
| `069d989` | Project renamed to **Mac-mini-Frame** at the owner's request |
| `c87e403` | **Console Mode rebuilt from HANDOFF.md**: all Swift sources, resource scripts, build script, tools, tests, CI |
| `84c2bcd` | Fixed the one Swift 6 compile error (main-actor isolation of startup), added the README. CI green |

The owner confirmed this is the route: "That the route we are taking update the repo with this".

---

## 4. Repo layout (what exists now)

```
build.sh                  zsh; builds build/Console Mode.app, signs it with
                          designated requirement identifier "local.consolemode",
                          installs to /Applications (skip with --no-install)
src/
  Common.swift            Paths constants (HANDOFF §9), log(), run()/spawn(),
                          bringToFront() (cooperative activation), onMain() helpers,
                          window scanning (gameWindowOwner, bigPictureReady),
                          ProcessList (sysctl KERN_PROC_UID + proc_pidpath)
  Freezer.swift           hide → write frozen.json → SIGSTOP; resume; protection
                          rules (system paths, Steam, CrossOver, Console Mode, Claude,
                          checked on the process AND its ancestors); watchdog installer
  Input.swift             IOHID (vendors 045E/054C/28DE): home = page 0x09 usage 0x0D,
                          hat = page 0x01 usage 0x39; 6 s hold timer; other button
                          cancels; GameController for Y / View(buttonOptions); de-dup
  Takeover.swift          controller outlines (400x260 box), starfield renderer
                          (timeline per HANDOFF §7), Takeover windows on non-main
                          displays at CGShieldingWindowLevel, LoadingCover
  Overlays.swift          Toast (+ screenshot flash), StatsOverlay (CPU, GPU via
                          IOAccelerator PerformanceStatistics, RAM, clock)
  Power.swift             display-sleep assertion, optional "Console Mode On/Off" Shortcuts
  main.swift              Controller state machine: desktop → starting → game → exiting
resources/                (copied into the .app's Contents/Resources)
  Info.plist              LSUIElement, bundle id local.consolemode, exec ConsoleMode, macOS 15+
  bottle-launch           zsh: `steam <appid>` | `exe <path>`; waits ≤180 s for a window,
                          then until it's gone 6 s in a row
  bottle-windows.swift    prints the owner of a large on-screen *.exe window (not Steam's own)
  add-game                python3: binary shortcuts.vdf writer; add / --list / --remove /
                          --sync / --check (exit 10); cover art copy; tag "Bottle Steam"
  backup-saves            python3: read-only, verified save backups (HANDOFF §6)
  watchdog                zsh LaunchAgent script (every 15 s)
tools/                    hidprobe.swift, render-preview.swift, cdp.js, prof.js
tests/                    test_add_game.py (13), test_backup_saves.py (6), test_scripts.sh (14)
docs/HANDOFF.md           the owner's original spec (source of truth for behaviour)
docs/AI-HANDOFF.md        this file
```

Things added beyond the spec (all small):

- **Environment overrides for testing.** Scripts read `CM_BOTTLE`, `CM_MAC_STEAM`, `CM_LAUNCHER`, `CM_HOME`, `CM_BACKUP_DEST`, `CM_WINE`, `CM_BOTTLE_WINDOWS`, `CM_LOG`, `CM_FROZEN`, `CM_PROC_NAME`, and timing values like `CM_GONE_SECS`. Real use needs none of them.
- **Signal handler** in `main.swift`: SIGTERM, SIGINT and SIGHUP resume the paused pids before exit.
- **Exit-to-PC shuts the bottle down by path.** It sends SIGTERM, then SIGKILL after 4 s, to every process under `CrossOverGPTK4.app/Contents/SharedSupport/CrossOver/`. It does not touch the CrossOver UI app.
- **Screenshots use `/usr/sbin/screencapture -D1`.** `CGDisplayCreateImage` is unavailable in the macOS 15 SDK. It still needs Screen Recording permission.
- **The app keeps the name "Console Mode"** (bundle `local.consolemode`), so the owner's existing Home-button mapping, TCC permission, watchdog label and backup folders still work. Only the repo/project is called Mac-mini-Frame.

---

## 5. What's verified and what isn't

**Verified by CI on `macos-15` (arm64, Swift 6.1.2 in Swift 5 mode, Python 3.14):**

- The app compiles with no warnings, and `bottle-windows` compiles and runs.
- The bundle is signed with the designated requirement, and `plutil -lint` passes.
- `tools/hidprobe.swift` and `tools/render-preview.swift` compile, and the preview renders. It's uploaded as the `takeover-preview` artifact on each run.
- All 33 script tests pass on macOS and Ubuntu. Coverage:
  - VDF round-trip and the appid formula (`crc32('"<launcher>"' + name) | 0x80000000`)
  - sync and check (including libraries on `D:` through `dosdevices`), and skipping redistributables and partial installs
  - cover art, for both the new and old librarycache layouts
  - not clobbering the user's own shortcuts
  - backup-saves: sources are byte-for-byte untouched, skip lists, the 15-backup limit, duplicate detection, no backup after failed verification
  - bottle-launch timing and tolerating window flicker
  - watchdog resume

**NOT verified. Nothing has run on the owner's Mac yet:**

1. The whole app flow with the real controller: entering game mode, the 6-second exit, combos, pausing and resuming apps, the starfield on the second display, Big Picture detection (`bigPictureReady()` uses an ≥80%-of-main-display window heuristic).
2. HANDOFF.md §8's open items: screenshots (needs Screen Recording granted), launching a real bottle game from a Mac Steam tile, double input from Steam Input, PlayStation and Steam controllers (HID usage 13 is assumed), and the Focus Shortcuts.
3. `add-game --sync` against the owner's real bottle library and Mac Steam `userdata`. Also whether Mac Steam's art file naming matches (`<id>p.jpg`, `<id>.jpg`, `<id>_hero.jpg`, `<id>_logo.png`).
4. The controller outline shapes are approximations. The Steam controller shape was meant to match a reference photo that wasn't available.
5. `Freezer` protection in practice. Check the log line `freeze: hid N apps, paused M processes` against the handoff's 35–39 processes, and confirm that Claude Code sessions (including the qemu VM in HANDOFF §4.10) are never paused.

---

## 6. Suggested next steps

1. On the Mac: `./build.sh`, then do the one-time setup in HANDOFF.md §5 (Home button → Console Mode, Screen Recording, remove Mac Steam from Login Items).
2. Press the Xbox button, watch `~/Library/Logs/ConsoleMode.log`, and work through §5 above.
3. Run `python3 "/Applications/Console Mode.app/Contents/Resources/add-game" --check`, then `--sync` with Mac Steam closed, and confirm the tiles and art in Big Picture.
4. Launch one real bottle game from a tile (not the Cyberpunk repack; see the ground rules), and confirm that game-to-front, returning to Big Picture and the save backup all work.
5. Fix what breaks. Keep the tests green (`python3 -m unittest discover -s tests -p 'test_*.py'`, `bash tests/test_scripts.sh`) and let CI compile the Swift if you're not on a Mac.

## 7. Owner's ground rules (from HANDOFF.md §10, still binding)

- Never use the `/Volumes/Expansion` drive.
- The console look must never appear on the play (main) screen. Other screens are taken over, never switched off.
- Pausing everything is fine ("nuclear is fine"), with no exceptions for Discord or music. Claude, Steam, CrossOver and system processes stay protected.
- Don't pop test windows (such as Notepad stand-ins) on the owner's screen without saying so.
- Don't launch the Cyberpunk repack or add it as a tile. The owner can add any exe themselves with `add-game`.
- Don't try to bypass Steam's integrity check (no CRC forging of `steamwebhelper.exe`).

## 8. Communication notes

- The owner writes short messages, often from a phone, and prefers action over questions.
- They asked for the project name **Mac-mini-Frame**.
- They offered their Mac for testing. The previous session had no computer-use access, so testing happened in CI only.
