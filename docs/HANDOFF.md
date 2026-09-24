# Console Mode: handoff

Everything needed to rebuild this project 1:1 on a Mac and continue it. It's written for another Claude (or a person) picking it up cold. Read it top to bottom once. Sections 4 and 5 are the ones people get wrong.

---

## 1. What this is

A macOS app that makes a Mac mini behave like a game console, driven entirely by a controller (built and tested with an **Xbox Wireless Controller**, model 0x0B13, over Bluetooth).

| Controller action | What happens |
|---|---|
| **Press the Xbox button** | **Game mode.** Other apps are hidden and *paused* (SIGSTOP). Every display except the main one shows an animated starfield "takeover", or a **Now Playing** card while a game runs. **Native Mac Steam Big Picture** opens on the main display. It's near-instant because Steam is preloaded and Big Picture is only un-minimized. Windows games from a **CrossOver bottle** show up in Big Picture as tiles and launch through the bottle, with a **launch screen** (game art plus a loading bar) until the game's window appears. |
| Press it again later | Brings Big Picture, or the running game, back to the front. |
| **Hold the Xbox button 6 s** | **Back to PC.** The game and the bottle's Windows Steam close; Mac Steam stays loaded with Big Picture minimized. Paused apps resume, hidden apps reappear and the takeover disappears. A countdown shows from the 2-second mark. Console Mode stays resident in standby. |
| Xbox + **D-pad up/down** | Volume ±6% (shows a notice) |
| Xbox + **Y** | Toggles a CPU / GPU / RAM / games-drive / clock overlay in the top-right corner |
| Xbox + **View** (on release) | Screenshot of the main display to `~/Pictures/Console Mode/` (flash and shutter sound) |
| Xbox + **X** | **Quick Resume:** suspend the game (frozen with SIGSTOP, 0% CPU, hidden, back to Big Picture); press again, or Play on its tile, to resume |
| Xbox + **Menu + View** | **Force quit** the game (press twice within 4 s to confirm) |
| Xbox + **LB** | **Save Rewind:** timeline of save snapshots; LB/RB or ◀▶ move through time, ▲▼ switch game, A restore (confirms), B close |
| Any other button while holding Xbox | Cancels the 6-second exit countdown for that hold |

**Save backups:**
- Snapshots are taken every ~30 s while playing (only when the saves changed, up to 40 kept per game) and when a game closes.
- The game's own folders are only read; copies are verified.
- They go to `/Volumes/Storage/Console Mode/Save Backups/`, and feed Save Rewind.
- A restore always snapshots the current save first ("before-restore"), so it can be undone.

**Status:**
- Entering game mode shows **one** heads-up with the controller battery and any drive under 50 GB free.
- After that, only a discrete chip in the corner of the extra displays (nothing further if there are none).

**Audio (trial):** switches the output to a configured device in game mode, and back on exit.

**Remote Play:** Mac Steam hosts streams to the Steam Link app (already enabled: `EnableStreaming = 1`).

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

A backup of the bottle settings from before the GPTK4 tuning is kept next to the bottle (`…/Bottles/Steam-GPTK4-settings-backup-<date>`).

Reference performance in this bottle: a demanding DX12 title's built-in benchmark at 1080p (Medium textures, FSR2) averaged **~60–73 FPS**.

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

### Standby, sessions, config

- **Standby:** Console Mode stays running in the background after "back to PC" (0% CPU, ~35 MB). The LaunchAgent `local.consolemode.standby` starts it at login with `--standby`, which preloads Mac Steam with `-silent`. The Xbox button then reaches the running app through `applicationShouldHandleReopen`, so there's no app-launch delay.
- **Instant Big Picture** needs the **Accessibility** permission for Console Mode. Back to PC minimizes and hides the Big Picture window through AX (`kAXMinimizedAttribute`, `kAXHiddenAttribute`); the Xbox button restores it (~0.1 s). Without the permission it quits Steam and cold-starts (~3–5 s).
- **Bottle warm-up** in game mode: `wineserver -p` (persistent) plus the bottle's Steam `-silent` if any tile is a bottle Steam game. `wineserver -k` runs on exit if no game is running.
- **Session file:** `~/Library/Application Support/Console Mode/session.json`.
  - bottle-launch writes `launching` → `playing` → `ended`.
  - Console Mode writes `suspended`.
  - bottle-launch writes `resume-request` when a suspended game's tile is launched again.
  - It also holds the game name, the Mac Steam shortcut id and the launch time.
  - The shortcut id comes from Steam's `SteamGameId` env var: an unsigned 64-bit value where `id = SteamGameId >> 32`. Don't use shell arithmetic for this; it overflows.
- **Config** (optional): `~/Library/Application Support/Console Mode/config.json`:
  ```json
  { "gamingAudioOutput": "LG TV", "nowPlaying": true, "lowStorageGB": 50, "rewindSnapshots": true, "keepSteamLoaded": true }
  ```
- **Volume** goes through Core Audio (`Volume.swift`): the same 16 steps as the keyboard keys, instant (no AppleScript), and hold-to-repeat after 0.35 s, then every 75 ms, from the HID D-pad only.
- **HUD** (`HUD.swift`): frosted-glass volume pill (top-right), exit ring (center; appears at 2 s, fills to 6 s, then turns into a checkmark), and message pill (top-center). Its window exists only while something is showing.
- **Test channel:** when `~/Library/Application Support/Console Mode/test-mode` exists, Console Mode accepts `DistributedNotificationCenter` posts named `local.consolemode.test` with `press`, `hold:<s>`, `combo:<name>`, `nav:<dir>` or `dump:<file>` (a JSON state snapshot). These drive the same code paths as the controller. The 10-cycle driver used during development is `tools/cycles.py`. **Delete `test-mode` for normal use.**

### Source files (`src/`)

| File | Contents |
|---|---|
| `Common.swift` | Paths and constants, `log()`, `run()` / `spawn()`, `bringToFront()` (cooperative activation), `gameWindowOwner()`, `bigPictureReady()` |
| `Freezer.swift` | Process enumeration (`sysctl KERN_PROC_UID` + `proc_pidpath`), protection rules, freeze/resume, watchdog installer |
| `Takeover.swift` | Controller outlines (Xbox / PlayStation / Steam) as SwiftUI `Path`s, starfield renderer, `Takeover` (non-main displays), `LoadingCover` (main display) |
| `Input.swift` | IOHID manager (vendors 0x045E Microsoft, 0x054C Sony, 0x28DE Valve), home-button hold timer, hat-switch D-pad, GameController combos, de-duplication |
| `Overlays.swift` | `Toast` and `StatsOverlay` (CPU via `host_processor_info`, GPU via IORegistry `IOAccelerator` → `PerformanceStatistics` → `Device Utilization %`, RAM via `host_statistics64`) |
| `Power.swift` | Display-sleep assertion; runs Shortcuts named "Console Mode On" / "Console Mode Off" if they exist |
| `Session.swift` | Session file, `Config`, game artwork lookup (Mac Steam grid → bottle cache), `ScreenModel` (Now Playing, battery, storage), `freeGB()`, `gamePIDs()` |
| `Standby.swift` | Accessibility-based park/wake of Big Picture, Steam preload, bottle warm-up/cool-down |
| `LaunchScreen.swift` | Main-display launch screen (hero art, logo, loading bar) |
| `Rewind.swift` | Save Rewind model and UI (timeline, confirm dialog, restore through `backup-saves --restore`) |
| `Audio.swift` | CoreAudio default-output switching (trial) |
| `Volume.swift` | Core Audio volume in 16 steps, mute |
| `HUD.swift` | Glass volume pill, exit ring, message pill |
| `main.swift` | `Controller`: `summon()` / `showBigPicture()` / `enterGameMode()` / `startSteam()` / `watch()` / Quick Resume / force quit / `combo()` / `exitToPC()` / `restoreDesktop()` / login item |

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
10. **Processes started by other Claude Code sessions are protected**, including anything they spawned (e.g. a VM). If one is found paused (`T`), Console Mode didn't do it: leave its state alone.
12. **`NSRunningApplication.hide()` does nothing for Steam's Big Picture window.** The window belongs to `Steam Helper` (`com.valvesoftware.steam.helper`), which refuses hide requests. `steam://close/bigpicture` pops up Steam's desktop window instead. Only Accessibility (minimize and hide through AX) works reliably. A warm `steam://open/bigpicture` takes 0.4–0.7 s; a cold start takes 3–5 s.
13. **Never read a subprocess's output after `waitUntilExit()`.** If it prints more than 64 KB (`ps -Ao command` does), both sides deadlock. Use `capture()` in `Common.swift`, which reads first.
18. **Big Picture's full-screen window can't be minimized or moved.** AX minimize returns success but does nothing, and AX position fails. `Standby.park()` tries minimize → move → close and checks each result (`bigPictureReady()`); in practice it lands on **close** (`steam://close/bigpicture`, then minimizing the desktop window Steam opens). Re-entry is then a warm `steam://open/bigpicture` (~1.0 s, measured over 13 cycles). A cold start is 3–5 s.
19. **Input Monitoring is required for the raw controller reading.** `IOHIDManagerOpen` returns `0xe00002e2` (not permitted) when it's denied, although it sometimes succeeds anyway, which makes it look flaky. Console Mode logs `IOHIDCheckAccess` and calls `IOHIDRequestAccess` at start. Grant it under System Settings › Privacy & Security › **Input Monitoring**.
20. **The countdown-cancel flag must only change during a hold.** It used to be set by combos without an active hold and was only cleared when a hold ended, which blocked the next exit hold (the exit never completed and apps stayed paused). `cancelHold()` now requires the button to be held, and release always clears it.
29. **Root cause of the broken exit hold and the "HID watch: failed / Input Monitoring denied" errors.** The Xbox controller exposes several HID interfaces: the gamepad (all buttons, including Xbox = 13, and the D-pad hat) and a keyboard-like one that disconnects and reconnects on every Xbox press. (1) Matching by vendor opened the keyboard-like one too, which needs Input Monitoring, so `IOHIDManagerOpen` failed whenever it was present (0xe00002e2). (2) Treating its removal as "controller gone" wiped every hold after 1 s. **Fix:** match only DeviceUsagePage 1 with usage 5/4 (gamepad/joystick): 5/5 restarts connect immediately, with no Input Monitoring needed. A release is only inferred from removal of the specific interface that reported the Xbox press. Raw Xbox up/down and interface removals are logged (`hid: …`) for diagnosing real holds.
30. **Wine games and macOS Spaces.** A Wine game creates hidden helper windows on another Space, and its full-screen window (layer 26) shows up on the current Space a few seconds later. *Activating* the game makes macOS slide to the Space with its other windows (System Settings › Desktop & Dock › "When switching to an application, switch to a Space with open windows"). Turning that setting off removes the slide; that's the owner's choice. Console Mode's hand-off (`watch()`): it finds game windows on any Space (`.optionAll`), waits up to 4 s for the window to reach the current Space, and, if the game has windows elsewhere, shows **"Scooting over to your game…"** on the launch screen 0.8 s before activating. The launch screen stays up through the slide, and only Console Mode's hand-off closes it: not bottle-launch's "playing" state, which is written as soon as the window *exists*. Measured with `tools/spacewatch.swift`, which samples which windows are on the current Space every 100 ms.
31. **`build.sh` refuses to install during game mode** (while `frozen.json` exists; `--force` overrides), quits Console Mode cleanly (force-kill only after 10 s), and restarts it with `--standby`. Installing mid-session unpauses and re-pauses every app. A force-kill skips Console Mode's own cleanup, so the watchdog resumes the apps but hidden apps stay hidden.
27. **The bottle's Windows Steam takes the Xbox controller away from Console Mode.** With it running, a real Xbox hold showed "home button held" restarting every 1.5–2 s and the controller "gone for over a second", so the exit never completed. That's why the bottle-Steam warm-up was removed; it also showed up as a second Steam. Scripted tests can't catch this, because they inject input above the HID layer. Only a real controller hold verifies the exit. **Open risk:** while a bottle-Steam game (e.g. Portal 2) runs, the bottle's Steam has to run too. If the hold fails in that situation, turn off Xbox controller support in the bottle Steam's controller settings.
28. **Steam quitting from its own menu ends game mode immediately** (`didTerminateApplicationNotification`). It used to be a 1-second poll gated on 90 s.
23. **Mac Steam can only launch `.app` bundles as non-Steam games.** Pointing a tile at a plain script makes macOS show a "choose an application" dialog on every launch, and whatever gets picked runs the game outside Console Mode. `add-game` therefore creates one small wrapper app per tile in `~/Library/Application Support/Console Mode/Tiles/<Name>.app`. It exports `CM_TILE_NAME` / `CM_TILE_SHORTCUT` and runs `bottle-launch` with the target baked in. Old script-style tiles are migrated automatically on the next sync (which only runs while Mac Steam is closed).
24. **Never start a second copy, never run two games at once.** `bottle-launch` checks the session: the same tile while it's starting or playing → `focus-request` (Console Mode brings it forward); a different game while one is starting or running → a "Close X first" notice (`notice.txt` → HUD). The "Steam quit, leave game mode" rule is skipped while a game is running.
25. **The Xbox controller re-announces a HID interface on every Xbox press.** Resetting button state on "device matched" wiped the press itself, so it resets only on real removal or disconnect.
26. **Never leave a persistent Wine server running** (`wineserver -p` from the GPTK4 build). The CrossOver app then can't start Steam in the same bottle ("missing" errors). The warm-up only starts the bottle's Steam with `-silent`.
22. **Lost release events leave the Xbox button "stuck" as held.** This happens when the controller disconnects or reconnects mid-press, and it blocked the exit hold (seen in the 10-cycle run). HID device removal/matching and `GCControllerDidDisconnect` now reset button state, and the "ignore the entry press" rule expires after 8 s.
21. **Focus returns to the app you were using** before game mode (cooperative activation). The desktop is restored as soon as Big Picture is tucked away; the game and the bottle's Steam finish closing in the background, and game windows are ignored for 5 s so a closing game isn't mistaken for a new one.
15. **Don't rely on macOS re-opening a resident app.** Once Console Mode stays running (standby), the Home-button "open app" action does not reliably reach it (`applicationShouldHandleReopen` stops firing after returning to PC). The Xbox press is therefore also read straight from HID (`Input.onHomePressed`), and `summon()` de-duplicates within 0.8 s.
16. **Changing a privacy permission (Screen Recording, Accessibility) makes macOS kill the app.** The Home button relaunches it, but in the relaunched copy the first `IOHIDManagerOpen` can fail, so it retries every 5 s.
17. **The press that enters game mode must not count toward the 6-second exit hold.** `Input.ignoreCurrentHold()` ignores it until the button is released.
14. **The D-pad hat's value range varies** (0–7 or 1–8). The code uses the element's logical min/max.
11. **Save backups must never touch the game's files.** `backup-saves` only reads the sources and writes into its own folder. Each copy goes to `.incoming-<stamp>`, gets verified file-by-file (sizes), and then is renamed into place.

---

## 5. Things that live outside the repo (set these up by hand)

Do these once on a new Mac, in this order.

1. **CrossOver GPTK4 + bottle.** Install CrossOver with GPTK4/D3DMetal and create a bottle named **`Steam`** with Windows Steam in it. Apply the environment variables in section 2.
2. **Bottle D: drive:** `ln -sfn /Volumes/circular "~/Library/Application Support/CrossOver/Bottles/Steam/dosdevices/d:"`. Then, in the bottle's Steam, go to Settings › Storage › Add Drive › `D:` so installs go to the games drive and not the 256 GB internal disk.
3. **Mac Steam.** Install it and sign in once, which creates `~/Library/Application Support/Steam/userdata/<id>/`. **Remove Mac Steam from Login Items** (System Settings › General › Login Items). Otherwise its windows pop up at every boot.
4. **Build and install:** `./build.sh`, which puts the app at `/Applications/Console Mode.app`.
5. **Accessibility** (for instant start): System Settings › Privacy & Security › **Accessibility** › enable **Console Mode**. Console Mode shows the system prompt on its first non-standby launch.
5b. **Controller home button:** System Settings › **Game Controllers** › *Xbox Wireless Controller* › **Home button** → open app → **Console Mode**.
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

**Verified in round 2 (without the owner's hands):**
- All new modules compile, and standby starts cleanly (0% CPU, 35 MB, Steam preloaded invisibly, login agents installed).
- `gamePIDs` finds a Wine-style process with spaces in its path; suspend → `T`, resume → `S`.
- bottle-launch: a suspended tile's Play turns into `resume-request`; a fresh launch writes `launching` with the correct 64-bit-derived shortcut id.
- `backup-saves` round trip in a fake home: snapshot → change → restore oldest → undo via `before-restore`, the same-second name collision, and refusing to restore into `/etc`.
- Preview renders reviewed: launch screen, Now Playing (and suspended), Save Rewind (and confirm dialog).
- Warm Big Picture reopen 0.4–0.7 s, cold 5 s (measured).

**Not verified yet:**
- Anything needing the owner's controller or permissions: the instant restore through Accessibility, Quick Resume and force quit on a real game, Save Rewind with a controller, the battery reading from the Xbox controller, Now Playing with a real game's art, audio routing (only "Mac mini Speakers" exists today), and a Remote Play session.
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
- Only add games the owner has a right to play. The assistant doesn't add or launch pirated copies; `add-game` is there for the owner's own games.
