#!/usr/bin/env python3
"""Drive Console Mode through N full cycles via its test channel and record everything."""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SEND = os.path.join(HERE, "send")
DUMP = os.path.join(HERE, "state.json")
FRONT = os.path.join(HERE, "..", "front")
REPORT = os.path.join(HERE, "cycles-report.txt")
LOG = os.path.expanduser("~/Library/Logs/ConsoleMode.log")
FROZEN = os.path.expanduser("~/Library/Application Support/Console Mode/frozen.json")
N = int(sys.argv[1]) if len(sys.argv) > 1 else 10

out = open(REPORT, "w")
def rec(msg):
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True); out.write(line + "\n"); out.flush()

def send(cmd): subprocess.run([SEND, cmd])

def state():
    try: os.remove(DUMP)
    except OSError: pass
    send(f"dump:{DUMP}")
    for _ in range(40):
        if os.path.exists(DUMP):
            try: return json.load(open(DUMP))
            except ValueError: pass
        time.sleep(0.05)
    return None

def wait_for(pred, timeout):
    t0 = time.time()
    while time.time() - t0 < timeout:
        s = state()
        if s and pred(s): return s, time.time() - t0
        time.sleep(0.1)
    return state(), None

def volume():
    r = subprocess.run(["osascript", "-e", "output volume of (get volume settings)"], capture_output=True, text=True)
    try: return int(r.stdout.strip())
    except ValueError: return None

def stopped_procs():
    r = subprocess.run(["ps", "-U", str(os.getuid()), "-o", "stat=,comm="], capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip().startswith("T") and "qemu" not in l]

issues = []
def check(cond, what, cycle):
    if not cond:
        issues.append(f"cycle {cycle}: {what}"); rec(f"   ✗ {what}")
    return cond

log_start = sum(1 for _ in open(LOG))
start_volume = volume()
rec(f"start: volume {start_volume}%, cycles {N}")
enter_times, exit_times = [], []

for c in range(1, N + 1):
    rec(f"── cycle {c} ──")
    # 1. Enter
    send("press")
    s, dt = wait_for(lambda s: s["gameMode"] and s["bigPictureReady"] and not s["starting"], 30)
    if dt is not None: enter_times.append(dt)
    rec(f"enter: {'%.2fs' % dt if dt is not None else 'TIMEOUT'} | front={s and s['front']} frozen={s and s['frozen']} hidden={s and s['hiddenApps']} takeover={s and s['takeoverWindows']}/{s and s['screens'] - 1}")
    time.sleep(1.5)                                   # freeze happens ~1.2 s after entering
    s = state()
    check(s and s["gameMode"], "game mode not active after press", c)
    check(s and s["frozen"] > 0, f"nothing paused (frozen={s and s['frozen']})", c)
    check(s and s["takeoverWindows"] == s["screens"] - 1, f"takeover windows {s and s['takeoverWindows']} != extra screens {s and s['screens'] - 1}", c)
    check(s and s["front"] in ("Steam Helper", "Steam"), f"Big Picture not in front (front={s and s['front']})", c)

    # 2. Volume
    v0 = volume()
    for _ in range(3): send("combo:volumeUp"); time.sleep(0.12)
    v1 = volume()
    for _ in range(3): send("combo:volumeDown"); time.sleep(0.12)
    v2 = volume()
    s = state()
    rec(f"volume: {v0}% → up×3 → {v1}% → down×3 → {v2}% | HUD volume={s and s['hudVolume']}")
    check(v1 is not None and v0 is not None and (v1 > v0 or v0 >= 100), f"volume up did nothing ({v0}→{v1})", c)
    check(v2 is not None and v0 is not None and abs(v2 - v0) <= 7, f"volume didn't return near start ({v0}→{v2})", c)

    # 3. Stats, screenshot, suspend / force quit with no game
    send("combo:stats"); time.sleep(0.4); s1 = state()
    send("combo:stats"); time.sleep(0.4); s2 = state()
    rec(f"stats: on={s1 and s1['statsShowing']} off={s2 and not s2['statsShowing']}")
    check(s1 and s1["statsShowing"] and s2 and not s2["statsShowing"], "stats toggle wrong", c)
    send("combo:screenshot"); time.sleep(1.2); s = state()
    rec(f"screenshot: HUD says '{s and s['hudMessage']}'")
    send("combo:suspend"); time.sleep(0.4); s = state()
    rec(f"suspend (no game): HUD says '{s and s['hudMessage']}' suspended={s and s['suspended']}")
    check(s and not s["suspended"], "suspended with no game", c)
    send("combo:forceQuit"); time.sleep(0.4); s = state()
    rec(f"force quit (no game): HUD says '{s and s['hudMessage']}'")

    # 4. Save Rewind: open, navigate, close
    send("combo:rewind"); time.sleep(0.8); s = state()
    check(s and s["rewindOpen"], "rewind didn't open", c)
    for n in ["right", "left", "down", "up", "a", "b"]: send(f"nav:{n}"); time.sleep(0.2)   # a with no snapshots / b dismisses
    send("nav:b"); time.sleep(0.6); s = state()
    rec(f"rewind: opened, navigated, closed={s and not s['rewindOpen']} front={s and s['front']}")
    check(s and not s["rewindOpen"], "rewind didn't close", c)

    # 5. Second Xbox press while in game mode
    send("press"); time.sleep(1.0); s = state()
    check(s and s["gameMode"] and s["front"] in ("Steam Helper", "Steam"), f"second press lost Big Picture (front={s and s['front']})", c)

    # 6. Exit with the hold
    send("hold:7")
    s, dt = wait_for(lambda s: not s["gameMode"] and not s["exiting"], 15)
    if dt is not None: exit_times.append(dt)
    rec(f"exit: {'%.2fs' % dt if dt is not None else 'TIMEOUT'} after hold start (6 s hold + teardown)")
    if dt is None:
        issues.append(f"cycle {c}: exit hold never completed; aborting and restoring the desktop")
        rec("   ✗ exit failed: quitting Console Mode to restore everything, stopping the run")
        subprocess.run(["osascript", "-e", 'quit app "Console Mode"']); time.sleep(3)
        subprocess.run(["open", "-g", "-a", "/Applications/Console Mode.app", "--args", "--standby"])
        break
    time.sleep(1.0); s = state()
    left = stopped_procs()
    rec(f"after exit: gameMode={s and s['gameMode']} frozen={s and s['frozen']} hidden={s and s['hiddenApps']} takeover={s and s['takeoverWindows']} BP visible={s and s['bigPictureReady']} presentation={s and s['presentation']} HUD hold={s and s['hudHold']} stoppedProcs={len(left)} frozen.json={os.path.exists(FROZEN)}")
    check(s and not s["gameMode"], "still in game mode after hold", c)
    check(s and s["frozen"] == 0 and not left and not os.path.exists(FROZEN), f"processes left paused: {left[:3]}", c)
    check(s and s["takeoverWindows"] == 0, "takeover still showing after exit", c)
    check(s and not s["bigPictureReady"], "Big Picture still on screen after exit", c)
    check(s and s["presentation"] == 0, "Dock/menu bar still hidden after exit", c)

    # 7. Watch for spontaneous re-entry
    reentered = False
    for _ in range(25):
        s = state()
        if s and (s["gameMode"] or s["takeoverWindows"] > 0): reentered = True; break
        time.sleep(0.2)
    check(not reentered, "game mode / takeover came back on its own after exit", c)
    rec(f"idle watch 5 s: {'RE-ENTERED' if reentered else 'stayed in PC mode'}")
    time.sleep(1.0)

subprocess.run(["osascript", "-e", f"set volume output volume {start_volume}"])
rec(f"volume restored to {volume()}%")
avg = lambda xs: sum(xs) / len(xs) if xs else float("nan")
rec(f"SUMMARY: enter avg {avg(enter_times):.2f}s (min {min(enter_times, default=0):.2f} max {max(enter_times, default=0):.2f}) | exit avg {avg(exit_times):.2f}s | issues: {len(issues)}")
for i in issues: rec("  - " + i)
lines = open(LOG).read().splitlines()[log_start:]
errs = [l for l in lines if any(k in l.lower() for k in ("fail", "refused", "error", "not running", "timeout"))]
rec(f"log lines during run: {len(lines)}, suspicious: {len(errs)}")
for l in errs[:40]: rec("  log: " + l[:200])
