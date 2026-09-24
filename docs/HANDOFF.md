# Console Mode: handoff

Everything needed to rebuild this project 1:1 on a Mac and continue it. It's written for another Claude (or a person) picking it up cold. Read it top to bottom once. Sections 4 and 5 are the ones people get wrong.

---

## 1. What this is

A macOS app that makes a Mac mini behave like a game console, driven entirely by a controller (built and tested with an **Xbox Wireless Controller**, model 0x0B13, over Bluetooth).

| Controller action | What happens |
|---|---|
| **Press the Xbox button** | **Game mode.** Other apps are hidden and *paused* (SIGSTOP). Every display except the main one shows an animated starfield "takeover". **Native Mac Steam Big Picture** opens on the main display. Windows games from a **CrossOver bottle** show up in Big Picture as tiles and launch through the bottle. |
| Press it again later | Brings Big Picture, or the running game, back to the front. |
| **Hold the Xbox button 6 s** | **Back to PC.** The game, Mac Steam and the bottle's Windows Steam close. Paused apps resume, hidden apps reappear and the takeover disappears. A countdown shows from the 2-second mark. |
| Xbox + **D-pad up/down** | Volume ±6% (shows a notice) |
| Xbox + **Y** | Toggles a CPU / GPU / RAM / clock overlay in the top-right corner |
| Xbox + **View** | Screenshot of the main display to `~/Pictures/Console Mode/` (flash and shutter sound) |
| Any other button while holding Xbox | Cancels the 6-second exit countdown for that hold |

After a game closes, the save folders it changed are **backed up** (read-only on the game side and verified) to `/Volumes/Storage/Console Mode/Save Backups/`.

![takeover frames](docs/images/takeover-frames.jpg)

---

## 2. The machine it was built on

These paths are baked into the code. On a different Mac, change the constants listed in section 9.

| Thing | Value |
|---|---|
| Mac | Mac mini, Apple M6, 16 GB RAM, 256 GB internal SSD |
| macOS | 27.0 |
| Displays | 2 × Dell P2422HE, 1920×1080 @ 60 Hz. The **main** display (menu bar) is the play screen. |
| Controller | Xbox Wireless Controller, Bluetooth, vendor 0x045E, product 0x0B13 |
| External drives | `/Volumes/circular` (954 GB, **exFAT**, games), `/Volumes/Storage` (931 GB, **APFS**, general storage and save backups), `/Volumes/Expansion` (**do not use**, the owner asked for it to be ignored) |
| CrossOver | `/Applications/CrossOverGPTK4.app` (CrossOver 26.3 with Apple Game Porting Toolkit 4 / D3DMetal). A stock `/Applications/CrossOver.app` also exists, but **all of this uses the GPTK4 build.** |
| Bottle | `~/Library/Application Support/CrossOver/Bottles/Steam` (Windows Steam installed inside) |
| Mac Steam | `/Applications/Steam.app` (bundle id `com.valvesoftware.steam`), signed in to the same account |
| Wine binary used everywhere | `/Applications/CrossOverGPTK4.app/Contents/SharedSupport/CrossOver/bin/wine` |

### Bottle settings (in `…/Bottles/Steam/cxbottle.conf`, `[EnvironmentVariables]`)

```
"WINEMSYNC" = "1"
"CX_GRAPHICS_BACKEND" = "d3dmetal"
"D3DM_MTL4" = "1"
"D3DM_ENABLE_METALFX" = "1"
"MTL_HUD_ENABLED" = "0"      # was 1; turned off for a clean console look
```

A backup of the bottle settings from before the GPTK4 tuning is at `…/Bottles/Steam-GPTK4-settings-backup-20260924-025812`. The record of the applied values is in `/Volumes/Storage/UserData/Documents/Codex/2026-09-24/cl/outputs/CrossOver-GPTK4-Setup/applied-settings.json`.

Reference performance in this bottle: Cyberpunk 2077's built-in benchmark at 1080p, Medium textures and FSR2 ran at **~60–73 FPS on average** (see `…/outputs/Cyberpunk-session-report.md`).

### Bottle drive letters (`…/Bottles/Steam/dosdevices/`)

```
c: -> ../drive_c
d: -> /Volumes/circular      # added so the bottle's Steam can put a library on the games drive
y: -> ~ (home)
z: -> /
```

Important: inside the bottle, `drive_c/users/crossover/Documents` is a **symlink to the Mac's real `~/Documents`**, and the same goes for Downloads, Music, Pictures and Videos. Games that save to "My Documents" write into the Mac's Documents folder. The save-backup script accounts for this.

---

## 3. Architecture

```
Xbox button ──(macOS: System Settings › Game Controllers › Home button = "Console Mode")──▶ opens Console Mode.app
                                                                                               │
Console Mode.app (Swift, LSUIElement, no Dock icon)                                            ▼
 ├─ Input      raw IOHID (home-button hold, D-pad hat)  +  GameController framework (Y, View, which pad)
 ├─ Freezer    SIGSTOP / SIGCONT of user processes; list saved to disk; watchdog LaunchAgent as safety net
 ├─ Takeover   SwiftUI Canvas starfield on every NON-main display (shielding window level)
 ├─ LoadingCover  plain black window on the main display while Steam starts
 ├─ Power      IOPMAssertion (no display sleep) + optional Shortcuts "Console Mode On/Off" for Focus
 ├─ Overlays   Toast (countdown, volume, screenshot) + StatsOverlay (CPU/GPU/RAM)
 └─ main       game-mode state machine; starts Mac Steam in Big Picture (-gamepadui);
               watches for bottle game windows (owner name ends in ".exe") → brings them to the front;
               game closed → backup-saves → back to Big Picture

Resources/ (inside the .app)
 ├─ bottle-launch   target of every Mac Steam tile: runs a game inside the bottle, waits until its window closes
 ├─ bottle-windows  tiny Swift helper: prints the owner of a large on-screen bottle window (used by bottle-launch)
 ├─ add-game        writes Mac Steam's binary shortcuts.vdf (add / remove / list / --sync / --check)
 ├─ backup-saves    save-game backup (read-only on the source side, verified copies)
 └─ watchdog        LaunchAgent script: resumes paused apps if Console Mode isn't running
```

### Source files (`src/`)

| File | Contents |
|---|---|
| `Common.swift` | Paths and constants, `log()`, `run()` / `spawn()`, `bringToFront()` (cooperative activation), `gameWindowOwner()`, `bigPictureReady()` |
| `Freezer.swift` | Process enumeration (`sysctl KERN_PROC_UID` + `proc_pidpath`), protection rules, freeze/resume, watchdog installer |
| `Takeover.swift` | Controller outlines (Xbox / PlayStation / Steam) as SwiftUI `Path`s, starfield renderer, `Takeover` (non-main displays), `LoadingCover` (main display) |
| `Input.swift` | IOHID manager (vendors 0x045E Microsoft, 0x054C Sony, 0x28DE Valve), home-button hold timer, hat-switch D-pad, GameController combos, de-duplication |
| `Overlays.swift` | `Toast` and `StatsOverlay` (CPU via `host_processor_info`, GPU via IORegistry `IOAccelerator` → `PerformanceStatistics` → `Device Utilization %`, RAM via `host_statistics64`) |
| `Power.swift` | Display-sleep assertion; runs Shortcuts named "Console Mode On" / "Console Mode Off" if they exist |
| `main.swift` | `Controller`: `summon()` / `enterGameMode()` / `startSteam()` / `watch()` / `combo()` / `exitToPC()` / `restoreDesktop()` |

---

## 4. Why it's built this way (hard-won findings, don't re-learn these)

1. **The bottle's own Big Picture is unusable, and it isn't fixable from outside Steam.** Windows Steam checks `wine_get_host_version` in ntdll, sees "Darwin", and launches `steamwebhelper.exe` with `--disable-gpu`. The GPU setting (`enable_gpu_accelerated_webviews`, client setting field 5001) is honored everywhere except here. Measured: **12–20 fps while navigating** (the software compositor process sits at ~116% CPU). Things tried that did **not** work:
   - the `-cef-force-gpu` launch option;
   - the registry value `HKCU\Software\Valve\Steam\GPUAccelWebViewsV3=1`;
   - setting 5001 through `SteamClient.Settings.SetSetting`;
   - Low Performance Mode (field 7005) and Reduce Motion (field 26006);
   - `-cef-force-opaque-backgrounds` (made it worse).

   A shim `steamwebhelper.exe` that strips the flag gets restored by Steam's bootstrapper: it checks **file size and CRC32** of executables. Forging the CRC was deliberately **not** done, because it defeats Steam's integrity check. **Don't go down that road.**
2. **So the menu is native Mac Steam Big Picture** (GPU-rendered: **52–60 fps navigating**), and the games still run in the bottle. Mac Steam only knows about Windows games through **non-Steam shortcuts** that point at `Resources/bottle-launch`. Both Steam clients can be signed in at once; only one can be *playing* at a time.
3. **macOS owns the controller's home button.** Pressing it triggers the system action (Games app by default), and the GameController framework never reports it as *held*, even with `shouldMonitorBackgroundEvents = true` and `preferredSystemGestureState = .disabled`. Solutions:
   - Set **System Settings › Game Controllers › (controller) › Home button** to open **Console Mode.app**. That's the launch trigger.
   - Read the **raw HID report** for the hold: Button page `0x09`, usage `0x0D` (13) on the Xbox 0x0B13. It was verified with `tools/hidprobe.swift`: press and release times come through exactly. DualSense is assumed to use the same usage (PS button); that's unverified.
4. **The D-pad isn't delivered while Steam is in front**, so it's read from HID too: hat switch (page `0x01`, usage `0x39`). Directions run clockwise from "up" starting at the element's logical minimum (0…7 or 1…8); out of range means centered. Y and View work fine through GameController.
5. **Every combo press also opens Console Mode** (macOS fires the home action on the Xbox-button press), so `summon()` must *not* re-activate Steam if it's already in front. Otherwise the screen flickers. That check is already in place.
6. **Bringing another app forward from an accessory app** needs macOS 14+ cooperative activation: `NSApp.activate()`, then `NSApp.yieldActivation(to:)`, then `app.activate(from: .current)`. A plain `activate()` is silently refused. Console Mode must stay running (a shell script that exits hands focus back to Finder).
7. **Bottle windows** show up in `CGWindowListCopyWindowInfo` with owner names like `notepad.exe` or `steamwebhelper.exe`. Full-screen Wine windows sit at **layer 26**, not 0.
8. **Ad-hoc code signing resets privacy permissions on every rebuild** (TCC keys on the code hash). `build.sh` signs with `-r='designated => identifier "local.consolemode"'` so Screen Recording survives rebuilds.
9. **Pausing (SIGSTOP) rules** (see `Freezer.swift`):
   - Never pause anything whose own path, or any ancestor's path, is under macOS system paths, Steam, CrossOver, Console Mode or **Claude** (Claude Code sessions and everything they launched). Pausing Claude cuts off the controlling session and the phone Remote Control link.
   - Record the list to `~/Library/Application Support/Console Mode/frozen.json` **before** sending the signals.
   - A crash is covered by `local.consolemode.watchdog` (every 15 s) and by the next launch.
   - SIGCONT is harmless on a running process, so resuming is always safe to repeat.
   - Hide apps **before** pausing them: a paused app can't hide itself.
10. **A qemu VM owned by another Claude Code session** (`qemu-system-aarch64`, OccultVM) is normally found paused (`T`). That isn't caused by Console Mode: it's a Claude descendant, so it's protected and never touched. Leave its state alone.
11. **Save backups must never touch the game's files.** `backup-saves` only reads the sources and writes into its own folder. Each copy goes to `.incoming-<stamp>`, gets verified file-by-file (sizes), and then is renamed into place.

---

## 5. Things that live outside the repo (set these up by hand)

Do these once on a new Mac, in this order.

1. **CrossOver GPTK4 + bottle.** Install CrossOver with GPTK4/D3DMetal and create a bottle named **`Steam`** with Windows Steam in it. Apply the environment variables in section 2.
2. **Bottle D: drive:** `ln -sfn /Volumes/circular "~/Library/Application Support/CrossOver/Bottles/Steam/dosdevices/d:"`. Then, in the bottle's Steam, go to Settings › Storage › Add Drive › `D:` so installs go to the games drive and not the 256 GB internal disk.
3. **Mac Steam.** Install it and sign in once, which creates `~/Library/Application Support/Steam/userdata/<id>/`. **Remove Mac Steam from Login Items** (System Settings › General › Login Items). Otherwise its windows pop up at every boot.
4. **Build and install:** `./build.sh`, which puts the app at `/Applications/Console Mode.app`.
5. **Controller home button:** System Settings › **Game Controllers** › *Xbox Wireless Controller* › **Home button** → open app → **Console Mode**.
6. **Screen Recording** for screenshots: System Settings › Privacy & Security › **Screen & System Audio Recording** › add and enable **Console Mode**.
7. The **watchdog LaunchAgent** installs itself on the first launch (`~/Library/LaunchAgents/local.consolemode.watchdog.plist`).
8. *(Optional)* **Focus while gaming:** create two Shortcuts named exactly **`Console Mode On`** (Set Focus › Do Not Disturb › On) and **`Console Mode Off`** (… › Off).

State changed during development that you may want to reproduce (or undo):
- In the **bottle's** Windows Steam: Low Performance Mode and Reduce Motion were turned **on** while trying to speed up its Big Picture. It's harmless; that Big Picture isn't used anymore.
- An early LaunchAgent `local.consolemode.xbox` (a background listener) was **removed**. It doesn't exist anymore.

---

## 6. Resource scripts, in detail

### `bottle-launch` (zsh): what each Mac Steam tile runs
```
bottle-launch steam <appid>          # game installed via the bottle's Steam → steam.exe -silent -applaunch <appid>
bottle-launch exe "/path/game.exe"   # any Windows exe → wine --bottle Steam --workdir <dir> <exe>
```
It waits up to 3 minutes for a bottle game window (via `bottle-windows`), then waits for it to be gone for about 6 s. That keeps Mac Steam in "playing" state for the whole session.

### `add-game` (python3): Mac Steam non-Steam shortcuts
```
add-game "Name" exe "/path/to/game.exe"
add-game "Name" steam <appid>
add-game --list | --remove "Name"
add-game --sync     # mirror every game installed in the bottle's Steam (skips redistributables)
add-game --check    # exit 10 if --sync has work to do (allowed while Steam runs)
```
- Writes `userdata/<id>/config/shortcuts.vdf` in Steam's **binary VDF** format (0x00 map, 0x01 string, 0x02 int32, 0x08 end).
- Shortcut appid = `crc32('"<launcher path>"' + name) | 0x80000000`.
- Synced tiles are tagged `Bottle Steam`, and `--sync` only adds or removes tiles with that tag.
- Cover art is copied from the bottle's `appcache/librarycache/<appid>/` into `userdata/<id>/config/grid/` as `<id>p.jpg` (portrait), `<id>.jpg` (wide), `<id>_hero.jpg` and `<id>_logo.png`.
- **Mac Steam must be closed** to write, because it rewrites the file on exit. Console Mode syncs right before it starts Steam, and restarts Steam if `--check` says something changed.
- Verified: Steam lists a written shortcut in `appStore.allApps` (app_type `1073741824`).

### `backup-saves` (python3)
```
backup-saves --since <unix time game started> [--label game.exe] [--dry-run]
```
- **Where it looks:**
  - Bottle `Saved Games`, `AppData/{Roaming,Local,LocalLow}`: two folder levels = one save folder, e.g. `Saved Games/CD Projekt Red/Cyberpunk 2077`.
  - `~/Documents/My Games/*`.
  - `~/Documents/*/*`, minus a skip list (`codex`, `claude`, `projects`, …).
  - Bottle `Steam/userdata/<acct>/<appid>/remote` (Steam Cloud), excluding Steam's own app IDs 7, 760 and 241100.
- **What it skips:**
  - Folders named cache, shadercache, logs, crash*, temp, steam, microsoft, mods, benchmarkresults, screenshots, …
  - Files ending in `.log`, `.dmp`, `.tmp`, `.cache`, …
- Only folders with a file modified since `since - 60 s` are backed up.
- **Safety limits:**
  - Skips anything over 2 GB or 5000 files.
  - No new backup if the manifest hash matches the last one.
  - Keeps the newest 15 per folder.
- **Destination:** `/Volumes/Storage/Console Mode/Save Backups/<Root - Vendor - Game>/<YYYY-MM-DD HH-MM-SS>/` with a `.manifest.json`. Falls back to `~/Library/Application Support/Console Mode/Save Backups` if Storage isn't mounted.
- Runs under `taskpolicy -b` (background priority).
- Dry-run against the real bottle found exactly Cyberpunk's `Saved Games/…` and `AppData/Local/CD Projekt Red/Cyberpunk 2077`, in 0.5 s.

### `watchdog` (zsh)
If `frozen.json` exists and no `ConsoleMode` process is running, it sends SIGCONT to every recorded pid and deletes the file.

---

## 7. Visual spec (takeover)

- **Where:**
  - Every display **except the main one**, at `CGShieldingWindowLevel()`.
  - It is **never** on the play screen.
  - It never powers a display off: that would cut power to things fed by the monitor's USB-C (a laptop, a lamp).
  - It rebuilds on `didChangeScreenParametersNotification`, so 1, 2 or 3+ displays all work.
- **Colors:** background gradient `rgb(0.008,0.016,0.05)` → `rgb(0.02,0.045,0.12)`, plus a centered radial glow `rgb(0.05,0.12,0.30)` at 55% opacity.
- **Timeline:**

| Time | What happens |
|---|---|
| 0–1.4 s | Hyperspace: 300 stars streak outward from the center |
| 0.9–2.5 s | Controller outline draws itself in (ease-out cubic), with a bright spark on the tip |
| 2.4 s | Center detail fades in (guide circle, or touchpad plus PS dot) |
| After that | Stars twinkle and drift slowly, bright stars get cross glints, 10% cyan and 7% violet stars |
| From 2.5 s, every 3.5 s | A shooting star (down-left, gradient tail) |
| From 3 s, every 6 s | A pulse ring expands from the controller; stars within 60 px flare |
| Throughout | Two nebula clouds (violet, teal) drift on slow loops, and the outline glow breathes |

- **Outline style by controller:** Xbox (vendor 0x045E / category "Xbox"), PlayStation (0x054C / "DualSense" or "DualShock"), Steam (0x28DE). The design box is 400×260; the Steam shape matches the reference photo the owner supplied.
- **Main display during startup:** plain black `LoadingCover` with "Starting Steam…" or "Adding new games…" text.
- Renders at 30 fps through a SwiftUI `TimelineView` + `Canvas`.
- `tools/render-preview.swift` renders sample frames to a JPEG (compile it together with `src/Common.swift src/Takeover.swift`).

---

## 8. Testing: what's verified and what isn't

**Verified live on the target Mac with the real controller:**
- Xbox press → game mode: 35–39 processes paused, Big Picture in front after about 3 s (the bottle's Big Picture took about 9 s)
- 6-second hold → back to PC: all processes resumed, `frozen.json` removed, both Steams closed
- Xbox + Y (stats panel), Xbox + D-pad up/down (volume)
- Pause/resume of a busy process (48% CPU → 0% `T` → 50%), and the watchdog recovering from a simulated crash
- `add-game` round-trip through Mac Steam, and `--sync` / `--check` against a fake bottle library
- Native Big Picture at 52–60 fps navigating (measured over the DevTools protocol, `tools/prof.js`)

**Not verified yet:**
- **Screenshot** (Xbox + View): the combo fires, but files only appear once Screen Recording is granted (section 5, step 6). The stable signature was added for exactly this; confirm it.
- **Launching a real bottle game from a Mac Steam tile**, including game-to-front and return-to-Big-Picture with a real game. It was tested with a stand-in Windows program (Notepad) in an earlier version.
- Whether **Mac Steam's Steam Input** also acts on the controller while a bottle game runs (double input). If it does: tile › Properties › Controller › disable Steam Input.
- The PlayStation and Steam controller paths (HID usage 13 for PS is assumed).
- The Focus Shortcuts (they only run if the user creates them).

**Diagnostic tools (`tools/`):**
- `hidprobe.swift` logs raw HID button changes from Microsoft controllers for 60 s.
- `cdp.js` / `prof.js` / `nav.js` talk to Steam's CEF over the DevTools protocol. They need Steam started with `-cef-enable-debugging` (port 8080, localhost). **Restart Steam without that flag afterwards.**
- Log file: `~/Library/Logs/ConsoleMode.log` (everything logs here).

---

## 9. Porting to another Mac: constants to check

| Constant | File | Value here |
|---|---|---|
| `gamesDrive` | `src/Common.swift` | `/Volumes/circular` |
| `wine` | `src/Common.swift`, `resources/bottle-launch` | CrossOverGPTK4 path |
| bottle name `Steam` | `bottle-launch`, `add-game`, `backup-saves`, `Common.swift` | `Steam` |
| backup destination | `resources/backup-saves` | `/Volumes/Storage/Console Mode/Save Backups` |
| `protectedPrefixes` | `src/Freezer.swift` | add anything that must keep running while gaming |
| `DOCUMENTS_SKIP` | `resources/backup-saves` | top-level `~/Documents` folders that are never saves |
| hold time | `src/Input.swift` `holdToExit` | 6 s (countdown from 2 s, in `main.swift`) |

Build requirements: Xcode Command Line Tools (`swiftc`, Swift 6 toolchain in Swift 5 language mode), `python3`, macOS 15+ (uses `yieldActivation`).

---

## 10. Ground rules the owner set

- Don't use the `Expansion` drive for any of this.
- The console look must never show on the play screen; other screens are taken over, never switched off.
- Pausing apps is fine even when it drops their connections ("nuclear is fine"). Nothing stays running during games (no Discord or music exceptions).
- Don't pop test windows (e.g. Notepad stand-ins) on the owner's screen without saying so.
- The Cyberpunk entry in the bottle's Steam is a non-Steam shortcut to a repack at `/Volumes/circular/Games/unpacked/…`. The previous assistant declined to launch it or add it as a tile; the owner can add any exe themselves with `add-game`.
