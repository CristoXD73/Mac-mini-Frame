# steam-tune: fix laggy Steam in CrossOver on macOS

Steam running in a CrossOver bottle on a Mac often feels slow: menus stutter, scrolling the library lags, Big Picture drops frames, and `steamwebhelper.exe` stops responding. `steam-tune` is a small command-line tool that tunes the bottle and starts Steam with settings that fix most of this. It works with both the desktop client and Big Picture (the controller/console UI).

## Why Steam lags under CrossOver

Steam's interface is a web browser: it runs on **steamwebhelper.exe**, which is Chromium (CEF). On Windows, Chromium draws with the GPU through D3D11. Under CrossOver the same drawing goes through several translation layers:

```
Chromium -> ANGLE -> Direct3D 11 -> (wined3d | DXMT | D3DMetal) -> Metal
```

Each layer adds latency, and the path is buggy under Wine. You get stutter, blank or black menus, and a UI drawn at 2x size. Rendering the UI in software is faster in practice, because it skips every translation layer, and a Steam menu is simple enough for the CPU. `steam-tune` also removes other overhead: Wine debug logging, MSync being off, Retina mode quadrupling the pixel count, and startup file checks.

**Your games are not affected.** These changes only apply to the Steam client UI. Games still use the GPU through D3DMetal, DXMT or DXVK.

## Quick start

```bash
git clone https://github.com/cristoxd73/pergolas.git steam-tune
cd steam-tune
./install.sh                      # puts `steam-tune` in ~/.local/bin

steam-tune doctor                 # find your bottle name and see what's wrong
# Quit Steam (Steam > Exit), then:
steam-tune apply                  # tune the bottle (makes a backup first)
steam-tune launch                 # start Steam with the low-lag profile
steam-tune launch --bigpicture    # ...or go straight into Big Picture
```

If your bottle is not called `Steam`, add `--bottle "My Bottle"` to every command, or run `export STEAM_BOTTLE="My Bottle"`.

To launch without Terminal, double-click **`macos/Steam Big Picture.command`** or **`macos/Steam Lite.command`**. You can drag either one to the Dock.

## What `apply` changes

Before changing anything, `apply` backs up `cxbottle.conf` and the bottle registry (`user.reg`). `steam-tune restore` undoes the last apply. `steam-tune restore original` puts the bottle back to how it was before steam-tune first touched it.

| Change | Where | Why |
|---|---|---|
| `WINEDEBUG=-all` | cxbottle.conf | Stops Wine's debug logging, which uses CPU on every call |
| `WINEMSYNC=1` | cxbottle.conf | MSync (Mach-semaphore sync) is lower-overhead than the default on macOS. Turn it off with `--no-msync` if a game breaks |
| `GPUAccelWebViewsV3=0` | `HKCU\Software\Valve\Steam` | Same as Steam > Settings > Interface > "GPU accelerated rendering in web views" = off. **This is the biggest fix** |
| `SmoothScrollWebViews=0` | same | Turns off smooth scrolling, which is janky under Wine |
| `DWriteEnable=0` | same | Turns off DirectWrite font rendering, which is slow under Wine |
| `H264HWAccel=0` | same | Turns off hardware video decode in web views (store trailers), which can hang CEF |
| `RetinaMode=n` | `HKCU\Software\Wine\Mac Driver` | Turns off High Resolution Mode. Otherwise Steam draws 4x the pixels. Keep it on with `--keep-retina` |

Optional flags:

- `--backend d3dmetal|dxmt|dxvk|wined3d|auto` sets the bottle's graphics backend.
  - D3DMetal is usually best for DX11/DX12 games on Apple silicon.
  - DXMT is a good choice for DX11 games.
  - `auto` lets CrossOver choose for each game.
- `--hud` turns on Apple's Metal performance HUD, which shows FPS in games.

## Launch profiles

`steam-tune launch --profile NAME` (run `steam-tune flags --profile NAME` to see the exact flags):

| Profile | Use when |
|---|---|
| `lite` (default) | Most cases. Chromium composites in software, D3D11 and DirectWrite off, startup file checks skipped |
| `nogpu` | `lite` still stutters, or menus are blank or black. Keeps Chromium off the GPU completely |
| `rescue` | steamwebhelper keeps crashing or shows "not responding". Adds in-process GPU and turns off the CEF sandbox |
| `stock` | Plain Steam, for comparison |

All profiles except `stock` also skip Steam's startup file checks and bootstrap updates (`-noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles`). Steam still updates itself when an update is actually needed.

To launch from CrossOver's own launcher instead: run `steam-tune flags --bigpicture`, then paste the output after `steam.exe` in the launcher's Command field.

## Compare profiles on your Mac

```bash
steam-tune launch --fresh --profile stock
steam-tune bench --seconds 30        # use Steam normally while it samples
steam-tune launch --fresh --profile lite
steam-tune bench --seconds 30
```

`bench` samples the CPU and RAM that all `steamwebhelper` processes use, and reports the average and peak. Lower is better. `--fresh` quits a running Steam first, which is needed because flags only take effect when Steam starts.

## Settings to change once inside Steam

These are stored in your Steam account config, so change them in Steam's Settings:

- **Library → Low Performance Mode: On.** Turns off animations and blur. Big win for Big Picture.
- **Library → Low Bandwidth Mode: On**, and **Show community content: Off**.
- **In Game → Steam Overlay: Off.** The overlay is another Chromium instance running inside every game.
- **Downloads → Allow downloads during gameplay: Off.**

## macOS tips

- **Turn Low Power Mode off** (System Settings → Battery). It throttles the CPU and GPU heavily. `doctor` checks this.
- **Play in full screen.** macOS turns on Game Mode automatically for full-screen games, which gives the game CPU/GPU priority and lowers controller latency.
- **Turn off VSync and frame caps in games.** macOS already syncs to the display, so an in-game VSync adds latency and often halves FPS.
- Close other Chromium-based apps you don't need (browsers, Discord, Slack). They compete for the same resources.
- Keep CrossOver up to date. Version 24 and later have better DXMT/D3DMetal and Steam fixes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Steam window is black or blank | `steam-tune launch --fresh --profile nogpu` |
| "steamwebhelper is not responding" | `steam-tune kill`, then `steam-tune launch --profile rescue` |
| Steam UI is tiny or blurry after `apply` | That's Retina mode being off. Run `steam-tune restore` and then `steam-tune apply --keep-retina` |
| A game broke after `apply` | Try `steam-tune apply --no-msync`, or `steam-tune restore original` |
| Anything else | `steam-tune restore original` undoes everything |

Launch logs are saved to `<bottle>/steam-tune-launch.log`.

## Development

The code is plain bash that runs on macOS's stock bash 3.2 with BSD awk/sed. Nothing needs to be installed.

```bash
bash tests/run.sh                                   # 54 tests, fake CrossOver install
shellcheck -x -e SC2012 bin/steam-tune lib/*.sh tests/run.sh
```

CI runs the tests on `macos-latest` (Apple's real `/bin/bash`) and on Ubuntu.

## Sources

- CodeWeavers: [Advanced Settings in CrossOver Mac 26](https://support.codeweavers.com/en_US/advanced-settings-in-crossover-mac-26) (DXMT, D3DMetal, MSync, High Resolution Mode)
- CodeWeavers forum: [Steam UI lag and the GPU-accelerated web views setting](https://www.codeweavers.com/support/forums/general/?t=27&forumcurPos=100&msg=279837), [steamwebhelper not responding](https://www.codeweavers.com/compatibility/crossover/forum/steam?msg=290823)
- [cxbottle.conf keys (`CX_GRAPHICS_BACKEND`, `WINEMSYNC`, …)](https://github.com/stoicswe/Endfield_FineWine/pull/15) and [ESync vs MSync notes](https://github.com/matthiasSchedel/rdr2-crossover-apple-silicon/blob/main/docs/esync-msync-ab.md)
- [winemac: Steam menus blank / UI at 2x (Retina + CEF GPU process)](https://github.com/dappermint/winecx-gptk/issues/11)
- [Steam Interface registry values (`GPUAccelWebViewsV3`, `H264HWAccel`, `DWriteEnable`)](https://github.com/xander27/steam-winreg)
- [Steam Big Picture UI lag and CEF GPU flags](https://github.com/ValveSoftware/steam-for-linux/issues/12694), [CEF on Wine/macOS needing GPU disabled](https://github.com/chromiumembedded/cef/issues/3028)
- [AppleGamingWiki: CrossOver](https://www.applegamingwiki.com/wiki/CrossOver)
