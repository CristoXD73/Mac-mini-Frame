import AppKit
import Foundation

/// Hides and pauses (SIGSTOP) everything the user runs while in game mode, and
/// resumes it afterwards. The pid list is written to disk *before* any signal
/// is sent, so the watchdog LaunchAgent or the next launch can always undo it.
enum Freezer {
    struct State: Codable {
        var pids: [Int32]
        var hidden: [String]   // bundle ids of apps we hid
        var time: Double
    }

    /// Nothing whose own path, or any ancestor's path, starts with one of these
    /// is ever paused.
    static let protectedPrefixes: [String] = [
        "/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/",
        "/Library/Application Support/Apple/", "/Library/Developer/CommandLineTools/",
        Paths.macSteamApp + "/", Paths.macSteamSupport + "/",
        "/Applications/CrossOver", Paths.bottles + "/",
        "/Applications/Console Mode.app/", Bundle.main.bundlePath + "/",
        // Claude (the app, Claude Code, and everything they launched). Pausing
        // Claude cuts off the controlling session and the phone link.
        "/Applications/Claude.app/", Paths.home + "/.claude/", Paths.home + "/.local/share/claude/",
        Paths.home + "/.local/bin/claude", Paths.home + "/Library/Application Support/Claude/",
    ]

    /// Process names treated like protected paths (for Claude Code run via node etc.).
    static let protectedNames: Set<String> = ["claude", "Claude", "ConsoleMode", "loginwindow",
                                              "WindowServer", "launchd"]

    static func isProtected(_ p: ProcInfo, byPid: [pid_t: ProcInfo]) -> Bool {
        var cur: ProcInfo? = p
        var hops = 0
        while let c = cur, c.pid > 1, hops < 64 {
            if protectedNames.contains(c.name) { return true }
            if c.path.isEmpty && c.pid == p.pid { return true } // can't see it: leave it alone
            if protectedPrefixes.contains(where: { c.path.hasPrefix($0) }) { return true }
            if c.path.lowercased().contains("/claude") { return true }
            cur = byPid[c.ppid]
            hops += 1
        }
        return false
    }

    static func candidates() -> [ProcInfo] {
        let me = getpid()
        let all = ProcessList.all()
        let byPid = Dictionary(all.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        return all.filter { $0.pid != me && $0.pid > 1 && !isProtected($0, byPid: byPid) }
    }

    // MARK: freeze / resume

    /// Hide first (a paused app can't hide itself), then record, then pause.
    @MainActor
    static func freeze(completion: @escaping @MainActor (Int) -> Void) {
        let myPid = getpid()
        var hidden: [String] = []
        let byPid = Dictionary(ProcessList.all().map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard app.processIdentifier != myPid, !app.isHidden,
                  let info = byPid[app.processIdentifier], !isProtected(info, byPid: byPid)
            else { continue }
            if app.hide(), let id = app.bundleIdentifier { hidden.append(id) }
        }
        // Give apps a moment to process the hide before they stop running.
        onMain(after: 0.6) {
            let victims = candidates().filter { !$0.stopped }
            let state = State(pids: victims.map(\.pid), hidden: hidden, time: Date().timeIntervalSince1970)
            guard save(state) else {
                log("freeze: could not write \(Paths.frozenFile); not pausing anything")
                completion(0)
                return
            }
            for v in victims { kill(v.pid, SIGSTOP) }
            log("freeze: hid \(hidden.count) apps, paused \(victims.count) processes")
            completion(victims.count)
        }
    }

    /// Resume everything recorded. SIGCONT is harmless on a running process,
    /// so this is always safe to repeat.
    @MainActor
    static func resume() {
        guard let state = load() else { return }
        for pid in state.pids { kill(pid, SIGCONT) }
        for id in state.hidden {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) { app.unhide() }
        }
        try? FileManager.default.removeItem(atPath: Paths.frozenFile)
        log("resume: \(state.pids.count) processes, \(state.hidden.count) apps unhidden")
    }

    static var hasFrozenState: Bool { FileManager.default.fileExists(atPath: Paths.frozenFile) }

    static func save(_ s: State) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: Paths.support, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]  // compact: the watchdog greps "pids":[...]
            try enc.encode(s).write(to: URL(fileURLWithPath: Paths.frozenFile), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load() -> State? {
        guard let d = FileManager.default.contents(atPath: Paths.frozenFile) else { return nil }
        return try? JSONDecoder().decode(State.self, from: d)
    }

    // MARK: watchdog LaunchAgent

    static func installWatchdog() {
        let script = Paths.resource("watchdog")
        let plist: [String: Any] = [
            "Label": Paths.watchdogLabel,
            "ProgramArguments": ["/bin/zsh", script],
            "StartInterval": 15,
            "RunAtLoad": true,
            "ProcessType": "Background",
        ]
        let url = URL(fileURLWithPath: Paths.watchdogPlist)
        if let existing = NSDictionary(contentsOf: url) as? [String: Any],
           (existing["ProgramArguments"] as? [String]) == ["/bin/zsh", script] {
            return  // already installed and pointing at this build
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        } catch {
            log("watchdog: could not write plist: \(error)")
            return
        }
        let domain = "gui/\(getuid())"
        run("/bin/launchctl", ["bootout", domain + "/" + Paths.watchdogLabel])
        let r = run("/bin/launchctl", ["bootstrap", domain, Paths.watchdogPlist])
        log("watchdog: installed (launchctl bootstrap status \(r.status))")
    }
}
