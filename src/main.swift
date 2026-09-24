import Cocoa

// Console Mode: opened by the Xbox button (System Settings > Game Controllers > Home button).
//
// Press once:  game mode. Other apps are hidden and paused, other displays show the console
//              starfield (or a Now Playing card), and the native Mac Steam Big Picture comes up
//              (GPU-rendered; the bottle's copy is forced onto the CPU by Steam under Wine).
//              Windows games from the CrossOver bottle appear in it as tiles that run
//              Contents/Resources/bottle-launch.
// Hold 6 s:    back to PC. The game and the bottle's Steam close, everything resumes and
//              reappears. Console Mode stays resident and Mac Steam stays loaded (Big Picture
//              minimized) so the next press is near-instant.
//
// Launched with --standby (login item): stays in the background and preloads Steam.

@MainActor
final class Controller: NSObject, NSApplicationDelegate {
    let freezer = Freezer()
    let takeover = Takeover()
    let cover = LoadingCover()
    let launchScreen = LaunchScreen()
    let rewind = RewindScreen()
    let input = Input()
    let power = Power()
    let audio = AudioRouting()
    let standby = Standby()
    let hud = HUD()
    let stats = StatsOverlay()
    let model = ScreenModel.shared
    var config = Config.load()

    var gameMode = false
    var hidden: [NSRunningApplication] = []
    var inGame: String?
    var gameStartedAt: Date?
    var suspended = false
    var suspendedPIDs: [pid_t] = []
    var forceQuitArmedAt: Date?
    var lastSnapshot = Date.distantPast
    var snapshotRunning = false
    var startedAt = Date()
    var starting = false
    var exiting = false
    var warnedStorage = Set<String>()
    var lastSummon = Date.distantPast
    var recentPresses: [Date] = []               // fallback exit when holds can't be detected
    var previousFront: NSRunningApplication?     // the app you were using before game mode
    var ignoreGamesUntil = Date.distantPast      // a game still closing after "back to PC" isn't a new game
    var pendingGameSince: Date?                  // game found, but its window isn't on this Space yet
    var scootingSince: Date?                     // "Scooting over…" is showing; the Space switch follows

    func applicationDidFinishLaunching(_ n: Notification) {
        freezer.resume()                 // leftovers from a crashed session
        Freezer.installWatchdog()
        installLoginItem()
        input.onHoldProgress = { [weak self] t in
            guard let self, self.gameMode, t >= holdRingDelay, !self.exiting else { return }
            self.hud.hold(t / holdToExit)            // ring appears at 2 s already a third full, completes at 6 s
        }
        input.onHoldCancelled = { [weak self] in if self?.exiting == false { self?.hud.holdCancel() } }
        input.onHoldComplete = { [weak self] in if self?.gameMode == true { self?.exitToPC() } }
        input.onCombo = { [weak self] in if self?.gameMode == true { self?.combo($0) } }
        // In PC mode, an Xbox press starts game mode directly (don't rely on macOS re-opening us).
        input.onHomePressed = { [weak self] in
            guard let self, !self.gameMode, !self.exiting else { return }
            log("Xbox press seen on the controller")
            self.summon()
        }
        input.start()
        rewind.model.gameRunning = { [weak self] in self?.inGame != nil }

        // Every start is set up the same way. Only the login item (--standby) stays in the background;
        // any other start (the Xbox button, a program opening Console Mode, macOS relaunching it after a
        // permission change) is handled exactly like an Xbox press once input is ready.
        standby.requestPermissionIfNeeded()
        if CommandLine.arguments.contains("--standby") {
            log("started in standby")
            standby.preloadSteam()                 // a press start launches Steam itself
        } else {
            log("started by an Xbox press or another program: treating it as a press")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.summon() }
        }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.watch() } }   // quick game hand-off
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshStatus(announce: false) } }
        startTestChannel()
        // Steam quit (from its own menu, not the Xbox hold): leave game mode right away.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == steamBundle else { return }
            MainActor.assumeIsolated {
                guard let self, self.gameMode, !self.starting, !self.exiting else { return }   // our own restarts set `starting`
                log("Steam quit: leaving game mode")
                self.hud.hideAll()
                self.restoreDesktop()
            }
        }
    }

    // Xbox button pressed again while running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Without the raw controller reading (Input Monitoring blocked) a long press is invisible,
        // so three quick Xbox presses return to PC instead. macOS delivers these presses itself.
        if gameMode && !input.rawInputAvailable {
            recentPresses = recentPresses.filter { Date().timeIntervalSince($0) < 2 } + [Date()]
            if recentPresses.count >= 3 { recentPresses = []; log("triple press (no raw controller access): returning to PC"); exitToPC(); return false }
            if recentPresses.count == 2 { hud.message("hand.tap.fill", "Press Xbox once more to return to PC", for: 2) }
        }
        summon(); return false
    }

    func applicationWillTerminate(_ n: Notification) {
        if suspended { suspendedPIDs.forEach { kill($0, SIGCONT) } }
        restoreDesktop()
    }

    // MARK: Entering game mode

    func summon() {
        guard !exiting else { return }
        // macOS's "open app" event and our own controller reading can both fire for one press.
        guard Date().timeIntervalSince(lastSummon) > 0.8 else { return }
        lastSummon = Date()
        log("Xbox button")
        startedAt = Date()
        if rewind.isOpen { closeRewind(); return }
        if !gameMode { enterGameMode(); input.ignoreCurrentHold() }
        let front = NSWorkspace.shared.frontmostApplication
        if let g = inGame, isRunning(g) {
            if suspended { showBigPicture(front) }
            else if front?.localizedName != g { bringToFront(g) }
            return
        }
        if steamRunning(), !starting, needsSync() {
            // New game installed in the bottle: Steam must be closed to add its tile.
            log("bottle library changed: restarting Steam to add tiles")
            starting = true
            cover.show("Adding new games…")
            NSRunningApplication.runningApplications(withBundleIdentifier: steamBundle).forEach { $0.terminate() }
            DispatchQueue.global().async {
                for _ in 0..<60 where steamRunning() { Thread.sleep(forTimeInterval: 0.5) }
                DispatchQueue.main.async { self.starting = false; self.startSteam() }
            }
            return
        }
        if steamRunning() { showBigPicture(front); return }
        startSteam()
    }

    /// Steam is running: show Big Picture as fast as possible.
    func showBigPicture(_ front: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        if standby.wake() { return }                                   // parked: ~instant
        if bigPictureReady() {
            if front?.bundleIdentifier != steamBundle && front?.bundleIdentifier != steamHelperBundle { bringToFront(bigPicture) }
            return
        }
        NSWorkspace.shared.open(URL(string: "steam://open/bigpicture")!)   // Steam loaded but not in Big Picture
        DispatchQueue.global().async {
            for _ in 0..<60 where !bigPictureReady() { Thread.sleep(forTimeInterval: 0.1) }
            DispatchQueue.main.async { bringToFront(bigPicture); self.cover.hide() }
        }
    }

    func enterGameMode() {
        if let f = NSWorkspace.shared.frontmostApplication, f != .current,
           ![steamBundle, steamHelperBundle].contains(f.bundleIdentifier ?? "") { previousFront = f }
        gameMode = true
        config = Config.load()
        log("entering game mode (\(input.lastPad.rawValue) controller)")
        takeover.nowPlayingEnabled = config.nowPlaying
        takeover.show(pad: input.lastPad)
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        power.enterGameMode()
        audio.enterGameMode(preferred: config.gamingAudioOutput)
        // (No bottle warm-up: the Windows Steam in the bottle grabs the controller for its own Steam
        //  Input, which breaks the Xbox hold, and it showed up as a second Steam. It only starts when a
        //  game that needs it is launched.)
        // Hide first (a paused app can't hide itself), then pause everything.
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app != .current && app.bundleIdentifier != steamBundle
            && app.bundleIdentifier != steamHelperBundle && !app.isHidden && !(app.localizedName ?? "").lowercased().hasSuffix(".exe") {
            app.hide()
            hidden.append(app)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.gameMode, !self.exiting else { return }
            self.freezer.freeze()
        }
        // One heads-up about the controller battery and low storage, then only the discrete chip.
        warnedStorage = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.refreshStatus(announce: true) }
    }

    func needsSync() -> Bool {
        guard let sync = resource("add-game") else { return false }
        return run(sync, ["--check"]) == 10
    }

    func startSteam() {
        guard !starting else { return }
        starting = true
        cover.show("Starting Steam…")
        NSApp.activate()
        DispatchQueue.global().async {
            for _ in 0..<30 where !FileManager.default.fileExists(atPath: gamesDrive) { Thread.sleep(forTimeInterval: 1) }
            if !FileManager.default.fileExists(atPath: gamesDrive) { log("games drive not connected (\(gamesDrive))") }
            // Mirror the bottle's installed games into Mac Steam (must happen while Steam is closed).
            if let sync = resource("add-game") { run(sync, ["--sync"]) }
            log("starting Steam Big Picture")
            run("/usr/bin/open", ["-b", steamBundle, "--args", "-gamepadui"])
            for _ in 0..<600 {
                if bigPictureReady() { break }
                Thread.sleep(forTimeInterval: 0.2)
            }
            DispatchQueue.main.async {
                self.starting = false
                bringToFront(bigPicture)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.cover.hide() }
            }
        }
    }

    // MARK: Status (battery, storage)

    func refreshStatus(announce: Bool) {
        guard gameMode else { return }
        var notes: [String] = []
        if let b = input.battery() {
            model.battery = b.level; model.charging = b.charging
            if announce { notes.append("Controller \(Int(b.level * 100))%\(b.charging ? " · charging" : "")") }
        }
        var storage: String?
        for (label, path) in [("Games drive", gamesDrive), ("Mac", "/")] {
            guard let gb = freeGB(path), gb < config.lowStorageGB else { continue }
            storage = "\(label) · \(Int(gb)) GB free"
            if !warnedStorage.contains(label) { warnedStorage.insert(label); notes.append("\(label) is low: \(Int(gb)) GB free") }
        }
        model.storageNote = storage
        if !notes.isEmpty { hud.message(model.battery != nil ? "gamecontroller.fill" : "externaldrive.fill", notes.joined(separator: "   ·   "), for: 3.5) }
    }

    // MARK: While playing

    func watch() {
        let session = Session.read()
        if session?.state == "resume-request" { resumeGame() }
        if session?.state == "focus-request" {
            Session.setState("playing")
            if let g = inGame { if suspended { resumeGame() } else { bringToFront(g) } }
        }
        // Messages from bottle-launch (e.g. "Close <game> first").
        let noticeFile = supportDir + "/notice.txt"
        if let note = try? String(contentsOfFile: noticeFile, encoding: .utf8) {
            try? FileManager.default.removeItem(atPath: noticeFile)
            hud.message("exclamationmark.circle.fill", note.trimmingCharacters(in: .whitespacesAndNewlines), for: 3)
        }
        let found = Date() < ignoreGamesUntil ? nil : gameWindow()
        var game = found?.owner
        // Hand-off to a new game, without surprises:
        //  1. wait (up to 4 s) for its window to reach the current Space, launch screen still up;
        //  2. if activating it will make macOS slide Spaces (Wine games keep windows on another Space),
        //     say "Scooting over to your game…" first and slide 0.8 s later;
        //  3. keep the launch screen up through the slide, then drop it (see below).
        if let f = found, f.owner != inGame {
            if pendingGameSince == nil { pendingGameSince = Date(); log("game \(f.owner) found (on this Space: \(f.onCurrentSpace))") }
            if !f.onCurrentSpace && Date().timeIntervalSince(pendingGameSince!) < 4 {
                game = nil
            } else if hasWindowsOnOtherSpaces(f.owner) {
                if scootingSince == nil {
                    scootingSince = Date()
                    launchScreen.setStatus("Scooting over to your game…")
                    log("game \(f.owner): scooting over (it has windows on another Space)")
                }
                if Date().timeIntervalSince(scootingSince!) < 0.8 { game = nil }
            }
        }
        let scooted = scootingSince != nil
        if game != nil { pendingGameSince = nil; scootingSince = nil }

        // Launch screen: up from Play until Console Mode hands off to the game (below), or the launch
        // ends / times out. Not closed when bottle-launch says "playing": the window may not be visible yet.
        if gameMode, inGame == nil, let s = session, s.state == "launching" || (s.state == "playing" && found != nil),
           Date().timeIntervalSince1970 - s.time < 180 {
            launchScreen.show(s)
        } else if launchScreen.showingFor != nil, inGame == nil,
                  session?.state == "ended" || (session?.state == "playing" && found == nil)
                    || Date().timeIntervalSince1970 - (session?.time ?? 0) >= 180 {
            launchScreen.hide()
        }

        if let g = game, g != inGame {
            log("game window: \(g) -> front")
            inGame = g
            suspended = false
            gameStartedAt = session.map { Date(timeIntervalSince1970: $0.time) } ?? Date()
            let name = (session?.state == "launching" || session?.state == "playing") ? session!.name : g.replacingOccurrences(of: ".exe", with: "")
            model.nowPlaying = NowPlaying(name: name, started: gameStartedAt!, suspended: false, art: session.map(gameArt) ?? GameArt())
            bringToFront(g)
            // Drop the launch screen once the game is in front, after the Space slide if there was one.
            DispatchQueue.main.asyncAfter(deadline: .now() + (scooted ? 0.9 : 0.3)) { [weak self] in self?.launchScreen.hide() }
        } else if game == nil, let g = inGame, !suspended, !isRunning(g) {
            log("game closed -> Big Picture")
            backupSaves(for: g, keep: nil)
            inGame = nil
            model.nowPlaying = nil
            if gameMode { showBigPicture() }
        }

        // Save Rewind: snapshot saves every time they change while playing.
        if let g = inGame, !suspended, config.rewindSnapshots, !snapshotRunning, Date().timeIntervalSince(lastSnapshot) > 30 {
            lastSnapshot = Date()
            backupSaves(for: g, keep: 40, keepStart: true)
        }

        // Steam was shut down from Big Picture: back to PC.
        if gameMode && !starting && !exiting && inGame == nil && Date().timeIntervalSince(startedAt) > 90 && !steamRunning() {
            log("Steam closed, leaving game mode")
            restoreDesktop()
        }
    }

    func backupSaves(for game: String, keep: Int?, keepStart: Bool = false) {
        guard let script = resource("backup-saves"), let since = gameStartedAt else { return }
        if !keepStart { gameStartedAt = nil }
        var args = [script, "--since", String(since.timeIntervalSince1970), "--label", game]
        if let keep { args += ["--keep", String(keep)] }
        snapshotRunning = true
        DispatchQueue.global(qos: .background).async {
            run("/usr/sbin/taskpolicy", ["-b"] + args)       // background priority: never competes with the game
            DispatchQueue.main.async { self.snapshotRunning = false }
        }
    }

    // MARK: Quick Resume

    func suspendGame() {
        guard let g = inGame, !suspended else { return }
        suspendedPIDs = gamePIDs(g)
        guard !suspendedPIDs.isEmpty else { return }
        NSWorkspace.shared.runningApplications.filter { $0.localizedName == g }.forEach { $0.hide() }
        suspendedPIDs.forEach { kill($0, SIGSTOP) }
        suspended = true
        Session.setState("suspended")
        model.nowPlaying?.suspended = true
        log("quick resume: suspended \(g) (\(suspendedPIDs.count) processes)")
        showBigPicture()
        hud.message("pause.fill", "Game suspended · Xbox + X to resume", for: 2.5)
    }

    func resumeGame() {
        guard let g = inGame, suspended else { return }
        suspendedPIDs.forEach { kill($0, SIGCONT) }
        suspendedPIDs = []
        suspended = false
        Session.setState("playing")
        model.nowPlaying?.suspended = false
        NSWorkspace.shared.runningApplications.filter { $0.localizedName == g }.forEach { $0.unhide() }
        bringToFront(g)
        log("quick resume: resumed \(g)")
    }

    // MARK: Force quit

    func forceQuit() {
        guard let g = inGame else { hud.message("gamecontroller", "No game running", for: 1.5); return }
        if let t = forceQuitArmedAt, Date().timeIntervalSince(t) < 4 {
            forceQuitArmedAt = nil
            let pids = gamePIDs(g)
            pids.forEach { kill($0, SIGCONT); kill($0, SIGKILL) }
            suspended = false; suspendedPIDs = []
            Session.setState("ended")
            log("force quit \(g) (\(pids.count) processes)")
            hud.message("xmark.circle.fill", "Game closed", for: 1.5)
        } else {
            forceQuitArmedAt = Date()
            hud.message("exclamationmark.triangle.fill", "Force quit \(g.replacingOccurrences(of: ".exe", with: ""))? Press Xbox + Menu + View again", for: 4)
        }
    }

    // MARK: Combos

    func combo(_ c: Combo) {
        switch c {
        case .screenshot:
            let dir = NSHomeDirectory() + "/Pictures/Console Mode"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let file = dir + "/Screenshot \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")).png"
            DispatchQueue.global().async {
                let ok = run("/usr/sbin/screencapture", ["-x", "-m", file]) == 0 && FileManager.default.fileExists(atPath: file)
                DispatchQueue.main.async {
                    if ok { self.flash(); NSSound(named: "Grab")?.play() ?? NSSound(named: "Tink")?.play() }
                    self.hud.message(ok ? "camera.fill" : "exclamationmark.triangle.fill", ok ? "Screenshot saved" : "Screenshot failed · allow Screen Recording for Console Mode", for: ok ? 2 : 5)
                }
            }
        case .volumeUp, .volumeDown:
            hud.volume(Volume.step(c == .volumeUp ? 1 : -1))
        case .stats:
            stats.toggle()
        case .suspend:
            if suspended { resumeGame() } else if inGame != nil { suspendGame() } else { hud.message("gamecontroller", "No game running", for: 1.5) }
        case .forceQuit:
            forceQuit()
        case .rewind:
            openRewind()
        }
    }

    func openRewind() {
        rewind.open()
        input.navSink = { [weak self] nav in
            guard let self else { return }
            if self.rewind.handle(nav) { self.closeRewind() }
        }
    }

    func closeRewind() {
        rewind.close()
        input.navSink = nil
        if let g = inGame, !suspended { bringToFront(g) } else { showBigPicture() }
    }

    /// Quick white flash over the main display, like a camera shutter.
    func flash() {
        let screen = NSScreen.screens.first!
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        w.level = .screenSaver; w.backgroundColor = .white; w.ignoresMouseEvents = true; w.alphaValue = 0.7
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; w.animator().alphaValue = 0 }, completionHandler: { w.orderOut(nil) })
    }

    // MARK: Back to PC

    func exitToPC() {
        guard !exiting else { return }
        exiting = true
        hud.holdDone()
        log("long press: returning to PC")
        if rewind.isOpen { rewind.close(); input.navSink = nil }
        if suspended { suspendedPIDs.forEach { kill($0, SIGCONT) } }
        let games = NSWorkspace.shared.runningApplications.filter {
            let n = ($0.localizedName ?? "").lowercased(); return n.hasSuffix(".exe") && !notGames.contains(n)
        }
        games.forEach { $0.terminate() }
        if let g = inGame { backupSaves(for: g, keep: nil) }
        let finish = { [self] in
            // Desktop back right away; the game and the bottle's Steam finish closing in the background.
            inGame = nil; suspended = false; suspendedPIDs = []
            ignoreGamesUntil = Date().addingTimeInterval(5)
            Session.setState("ended")
            restoreDesktop()
            exiting = false
            log("back to PC (Console Mode stays in standby)")
            DispatchQueue.global().async {
                if bottleSteamRunning() {
                    run(wine, ["--bottle", "Steam", "C:\\Program Files (x86)\\Steam\\steam.exe", "-shutdown"])
                }
                Thread.sleep(forTimeInterval: 3)
                DispatchQueue.main.async {
                    games.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
                }
            }
        }
        if config.keepSteamLoaded {
            standby.park(done: finish)     // Steam stays loaded with Big Picture tucked away (or quits without Accessibility)
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: steamBundle).forEach { $0.terminate() }
            finish()
        }
    }

    /// Resume paused apps, show hidden ones, drop the overlays. Safe to call more than once.
    func restoreDesktop() {
        freezer.resume()
        hidden.forEach { $0.unhide() }
        hidden = []
        takeover.hideAll()
        cover.hide()
        launchScreen.hide()
        stats.hide()
        hud.hideAll()
        model.nowPlaying = nil
        NSApp.presentationOptions = []
        if gameMode { power.leaveGameMode(); audio.leaveGameMode() }
        gameMode = false
        // Give focus back to whatever you were using before game mode.
        if let app = previousFront, !app.isTerminated {
            NSApp.activate(); NSApp.yieldActivation(to: app); _ = app.activate(from: .current, options: [])
        }
        previousFront = nil
    }

    // MARK: Test channel
    // Drives Console Mode through the same code paths the controller uses. Only active while
    // ~/Library/Application Support/Console Mode/test-mode exists. Send with:
    //   DistributedNotificationCenter post "local.consolemode.test", object "<command>"
    //   press | hold:<seconds> | combo:<name> | nav:<left|right|up|down|a|b> | dump:<file>

    func startTestChannel() {
        DistributedNotificationCenter.default().addObserver(forName: .init("local.consolemode.test"), object: nil, queue: .main) { [weak self] n in
            guard let self, FileManager.default.fileExists(atPath: supportDir + "/test-mode"), let cmd = n.object as? String else { return }
            MainActor.assumeIsolated { self.test(cmd) }
        }
    }

    func test(_ cmd: String) {
        let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
        log("TEST \(cmd)")
        switch parts[0] {
        case "press": input.simulatePress()
        case "hold": input.simulateHold(Double(parts.count > 1 ? parts[1] : "7") ?? 7)
        case "flickerhold": input.simulateFlickeringHold(Double(parts.count > 1 ? parts[1] : "5") ?? 5)
        case "combo":
            let map: [String: Combo] = ["screenshot": .screenshot, "volumeUp": .volumeUp, "volumeDown": .volumeDown, "stats": .stats,
                                        "suspend": .suspend, "forceQuit": .forceQuit, "rewind": .rewind]
            if let c = map[parts.count > 1 ? parts[1] : ""] { input.simulateCombo(c) }
        case "nav":
            let map: [String: Nav] = ["left": .left, "right": .right, "up": .up, "down": .down, "a": .a, "b": .b]
            if let n = map[parts.count > 1 ? parts[1] : ""] { input.simulateNav(n) }
        case "dump":
            let screens = NSScreen.screens.count
            let state: [String: Any] = [
                "gameMode": gameMode, "starting": starting, "exiting": exiting, "inGame": inGame ?? "", "suspended": suspended,
                "frozen": freezer.frozen.count, "hiddenApps": hidden.count, "takeoverWindows": takeover.windowCount, "screens": screens,
                "rewindOpen": rewind.isOpen, "statsShowing": stats.isShowing,
                "hudVolume": hud.model.volume.map { Double($0) } ?? -1, "hudHold": hud.model.hold ?? -1, "hudMessage": hud.model.message?.text ?? "",
                "steamRunning": steamRunning(), "bigPictureReady": bigPictureReady(),
                "front": NSWorkspace.shared.frontmostApplication?.localizedName ?? "", "axTrusted": standby.trusted,
                "presentation": NSApp.presentationOptions.rawValue,
                "bigPictureNativeFullScreen": standby.bigPictureIsNativeFullScreen().map { $0 ? "yes" : "no" } ?? "unknown",
            ]
            if parts.count > 1, let d = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
                try? d.write(to: URL(fileURLWithPath: parts[1]))
            }
        default: break
        }
    }

    /// Start Console Mode in standby at login so the Xbox button never waits for an app launch.
    func installLoginItem() {
        let path = NSHomeDirectory() + "/Library/LaunchAgents/local.consolemode.standby.plist"
        let plist: [String: Any] = [
            "Label": "local.consolemode.standby",
            "ProgramArguments": ["/usr/bin/open", "-g", "-a", Bundle.main.bundlePath, "--args", "--standby"],
            "RunAtLoad": true,
        ]
        if let existing = NSDictionary(contentsOfFile: path), existing.isEqual(to: plist) { return }
        (plist as NSDictionary).write(toFile: path, atomically: true)
        log("login item installed (standby at login)")   // takes effect at next login; not loaded now to avoid a second instance
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = Controller()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(controller) { app.run() }
}
