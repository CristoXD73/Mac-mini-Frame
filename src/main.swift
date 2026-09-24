import AppKit
import Foundation

/// Game-mode state machine. Every press of the controller's home button opens
/// this app (System Settings > Game Controllers > Home button), which arrives
/// either as the first launch or as a "reopen" of the running app.
@MainActor
final class Controller: NSObject, NSApplicationDelegate, InputDelegate {
    enum Mode { case desktop, starting, game, exiting }

    private(set) var mode: Mode = .desktop
    private let input = Input()
    private let takeover = Takeover()
    private let cover = LoadingCover()
    private let toast = Toast()
    private let stats = StatsOverlay()

    private var watchTimer: Timer?
    private var game: (name: String, pid: pid_t, started: Date)?
    private var gameGoneSince: Date?

    // MARK: app lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        log("launch (pid \(getpid()))")
        if Freezer.hasFrozenState {  // we crashed or were killed mid-game
            log("launch: found frozen state from a previous run, resuming")
            Freezer.resume()
        }
        Freezer.installWatchdog()
        input.delegate = self
        input.start()
        summon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        summon()
        return false
    }

    func applicationWillTerminate(_ note: Notification) {
        if mode != .desktop { restoreDesktop() }
    }

    // MARK: home button press

    func summon() {
        switch mode {
        case .desktop:
            enterGameMode()
        case .starting, .exiting:
            break
        case .game:
            // Every combo press also opens us, so never re-activate what's
            // already in front (that flickers).
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if let g = game, let app = NSRunningApplication(processIdentifier: g.pid) {
                if front != g.pid { bringToFront(app) }
            } else if let steam = macSteam(), front != steam.processIdentifier,
                      !steamProcessIDs().contains(front ?? -1) {
                bringToFront(steam)
            }
        }
    }

    func enterGameMode() {
        mode = .starting
        log("game mode: enter (style \(input.style.rawValue))")
        Power.gameModeOn()
        takeover.show(style: input.style)
        cover.show("Starting Steam…")
        Freezer.freeze { [weak self] _ in self?.startSteam() }
    }

    // MARK: Steam

    private func startSteam() {
        guard mode == .starting else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let addGame = Paths.resource("add-game")
            let needsSync = run("/usr/bin/python3", [addGame, "--check"]).status == 10
            onMain { self.launchSteam(sync: needsSync) }
        }
    }

    private func launchSteam(sync: Bool) {
        guard mode == .starting else { return }
        if sync {
            cover.show("Adding new games…")
            // Mac Steam rewrites shortcuts.vdf on exit, so it must be closed to add tiles.
            quitMacSteam { [weak self] in
                DispatchQueue.global(qos: .userInitiated).async {
                    let r = run("/usr/bin/python3", [Paths.resource("add-game"), "--sync"])
                    log("add-game --sync: \(r.status)\n\(r.output)")
                    onMain { self?.openBigPicture() }
                }
            }
        } else {
            openBigPicture()
        }
    }

    private func openBigPicture() {
        guard mode == .starting else { return }
        cover.show("Starting Steam…")
        if macSteam() != nil {
            NSWorkspace.shared.open(URL(string: "steam://open/bigpicture")!)
        } else {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.arguments = ["-gamepadui"]
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: Paths.macSteamApp), configuration: cfg) { _, err in
                if let err { log("steam: launch failed: \(err)") }
            }
        }
        waitForBigPicture(deadline: Date().addingTimeInterval(45))
    }

    private func waitForBigPicture(deadline: Date) {
        guard mode == .starting else { return }
        if bigPictureReady() || Date() > deadline {
            if Date() > deadline { log("steam: Big Picture not detected in time; continuing") }
            cover.hide()
            if let steam = macSteam() { bringToFront(steam) }
            mode = .game
            startWatching()
            log("game mode: Big Picture up")
            return
        }
        onMain(after: 0.3) { [weak self] in self?.waitForBigPicture(deadline: deadline) }
    }

    // MARK: watching bottle games

    private func startWatching() {
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch() }
        }
    }

    private func watch() {
        guard mode == .game else { return }
        if let found = gameWindowOwner() {
            gameGoneSince = nil
            if game == nil || game?.name != found.name {
                game = (found.name, found.pid, game?.started ?? Date())
                log("game: \(found.name) (pid \(found.pid)) up")
                if let app = NSRunningApplication(processIdentifier: found.pid) { bringToFront(app) }
            }
        } else if let g = game {
            if gameGoneSince == nil { gameGoneSince = Date() }
            if Date().timeIntervalSince(gameGoneSince!) >= 3 {
                log("game: \(g.name) closed after \(Int(Date().timeIntervalSince(g.started)))s")
                game = nil
                gameGoneSince = nil
                backupSaves(since: g.started, label: g.name)
                if let steam = macSteam() { bringToFront(steam) }
            }
        }
    }

    private func backupSaves(since: Date, label: String) {
        spawn("/usr/sbin/taskpolicy", ["-b", "/usr/bin/python3", Paths.resource("backup-saves"),
                                       "--since", String(Int(since.timeIntervalSince1970)), "--label", label]) { status in
            log("backup-saves exited \(status)")
        }
    }

    // MARK: combos

    func combo(_ combo: Combo) {
        log("combo: \(combo.rawValue)")
        switch combo {
        case .volumeUp: changeVolume(+6)
        case .volumeDown: changeVolume(-6)
        case .stats: stats.toggle()
        case .screenshot: screenshot()
        }
    }

    private func changeVolume(_ delta: Int) {
        let script = """
        set v to (output volume of (get volume settings)) + (\(delta))
        if v < 0 then set v to 0
        if v > 100 then set v to 100
        set volume output volume v
        return v
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let out = run("/usr/bin/osascript", ["-e", script]).output.trimmingCharacters(in: .whitespacesAndNewlines)
            onMain { self.toast.show("Volume \(out)%") }
        }
    }

    private func screenshot() {
        try? FileManager.default.createDirectory(atPath: Paths.screenshots, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = (game?.name ?? "Console Mode").replacingOccurrences(of: ".exe", with: "")
        let path = "\(Paths.screenshots)/\(name) \(f.string(from: Date())).png"
        // -D1 = main display. No -x, so macOS plays the shutter sound.
        // Needs Screen Recording permission for Console Mode.
        DispatchQueue.global(qos: .userInitiated).async {
            let r = run("/usr/sbin/screencapture", ["-D1", "-tpng", path])
            let ok = r.status == 0 && FileManager.default.fileExists(atPath: path)
            log("screenshot: \(ok ? path : "failed (grant Screen Recording?)")")
            onMain {
                if ok { Toast.flash(); self.toast.show("Screenshot saved") }
                else { self.toast.show("Screenshot needs Screen Recording permission", for: 3) }
            }
        }
    }

    // MARK: hold to exit

    func homeHoldProgress(_ seconds: Double) {
        guard mode != .desktop, mode != .exiting, seconds >= 2 else { return }
        let left = Int(ceil(Input.holdToExit - seconds))
        toast.show("Keep holding to return to PC… \(left)", for: 0.5)
    }

    func homeHoldCancelled() {
        toast.hide()
    }

    func homeHeldToExit() {
        guard mode == .game || mode == .starting else { return }
        exitToPC()
    }

    func exitToPC() {
        mode = .exiting
        log("exit to PC")
        watchTimer?.invalidate()
        toast.show("Returning to PC…", for: 3)
        cover.hide()
        if let g = game { backupSaves(since: g.started, label: g.name) }
        game = nil
        closeBottle()
        quitMacSteam { [weak self] in self?.restoreDesktop() }
    }

    /// Everything we changed goes back: paused apps resume, hidden apps return,
    /// the takeover disappears.
    func restoreDesktop() {
        Freezer.resume()
        takeover.hide()
        stats.hide()
        cover.hide()
        Power.gameModeOff()
        mode = .desktop
        log("desktop restored")
    }

    // MARK: shutting things down

    /// Closes the game and the bottle's Windows Steam: every Wine process of
    /// the CrossOver build (not the CrossOver UI app itself).
    private func closeBottle() {
        let winePrefix = Paths.wineDir + "/"
        let wine = ProcessList.all().filter { $0.path.hasPrefix(winePrefix) }
        guard !wine.isEmpty else { return }
        for p in wine { kill(p.pid, SIGCONT); kill(p.pid, SIGTERM) }
        log("bottle: SIGTERM to \(wine.count) wine processes")
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            let left = ProcessList.all().filter { $0.path.hasPrefix(winePrefix) }
            for p in left { kill(p.pid, SIGKILL) }
            if !left.isEmpty { log("bottle: SIGKILL to \(left.count) leftovers") }
        }
    }

    private func quitMacSteam(then done: @escaping @MainActor () -> Void) {
        guard let steam = macSteam() else { done(); return }
        steam.terminate()
        let deadline = Date().addingTimeInterval(8)
        @MainActor func poll() {
            if steam.isTerminated && steamProcessIDs().isEmpty { done(); return }
            if Date() > deadline {
                log("steam: force quitting")
                steam.forceTerminate()
                for pid in steamProcessIDs() { kill(pid, SIGKILL) }
                onMain(after: 0.5) { done() }
                return
            }
            onMain(after: 0.25) { poll() }
        }
        poll()
    }
}

// Signals that should still restore the desktop before we die.
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig) { _ in
        if let state = Freezer.load() { for pid in state.pids { kill(pid, SIGCONT) } }
        try? FileManager.default.removeItem(atPath: Paths.frozenFile)
        exit(0)
    }
}

// Top-level code runs on the main thread, but isn't main-actor isolated.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = Controller()
    app.delegate = controller  // weak; `controller` lives until run() returns
    app.setActivationPolicy(.accessory)
    app.run()
}
