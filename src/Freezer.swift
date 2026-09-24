import Cocoa
import Darwin

// Game mode "freeze": pause (SIGSTOP) every app and background process the user runs, so the
// game gets the whole machine, then resume (SIGCONT) them on exit. Paused processes keep all
// their state; nothing is quit or restarted.
//
// Safety:
//  - macOS itself, Steam, CrossOver/Wine (the games), Console Mode and Claude are never paused,
//    including everything they launched.
//  - The paused list is written to disk first. If Console Mode dies, the watchdog LaunchAgent
//    (Resources/watchdog) resumes them, and so does the next Console Mode launch. SIGCONT on a
//    process that isn't stopped is harmless, so resuming is always safe to repeat.

let frozenFile = supportDir + "/frozen.json"
let home = NSHomeDirectory()

/// Never paused, and neither is anything they started.
let protectedPrefixes = [
    "/System/Library/", "/System/Cryptexes/", "/System/iOSSupport/",
    "/System/Volumes/Preboot/Cryptexes/OS/", "/System/Volumes/Preboot/Cryptexes/App/usr/", "/usr/", "/bin/", "/sbin/", "/private/",
    "/Library/Apple/", "/Library/Developer/", "/Library/Application Support/CrossOver",
    "/Applications/Claude.app", home + "/Library/Application Support/Claude/",
    "/Applications/Steam.app", home + "/Library/Application Support/Steam/",
    "/Applications/CrossOver", home + "/Library/Application Support/CrossOver/",
    "/Applications/Console Mode.app",
]

struct Proc { let pid: pid_t; let ppid: pid_t; let path: String }

func userProcesses() -> [Proc] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
    let stride = MemoryLayout<kinfo_proc>.stride
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
    size = procs.count * stride
    guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
    var buf = [CChar](repeating: 0, count: 4096)
    return procs.prefix(size / stride).compactMap { kp in
        let pid = kp.kp_proc.p_pid
        guard pid > 1, proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return Proc(pid: pid, ppid: kp.kp_eproc.e_ppid, path: String(cString: buf))
    }
}

@MainActor
final class Freezer {
    private(set) var frozen: [pid_t] = []
    var isFrozen: Bool { !frozen.isEmpty }

    /// What would be paused right now (used by freeze and for dry runs).
    func candidates() -> [Proc] {
        let procs = userProcesses()
        let me = getpid()
        let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        func isProtected(_ p: Proc) -> Bool {
            // Walk up the parent chain: protected if it, or anything that launched it, is protected.
            var cur: Proc? = p, hops = 0
            while let c = cur, hops < 64 {
                if c.pid == me || protectedPrefixes.contains(where: { c.path.hasPrefix($0) })
                    || (c.path as NSString).lastPathComponent == "claude" { return true }
                if c.ppid <= 1 { return false }
                cur = byPid[c.ppid]; hops += 1
            }
            return false
        }
        return procs.filter { !isProtected($0) }
    }

    func freeze() {
        guard !isFrozen else { return }
        let targets = candidates()
        frozen = targets.map(\.pid)
        // Record first, so a crash between here and the kill() calls still gets cleaned up.
        try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        let record = targets.map { ["pid": Int($0.pid), "path": $0.path] as [String: Any] }
        if let data = try? JSONSerialization.data(withJSONObject: record) {
            try? data.write(to: URL(fileURLWithPath: frozenFile), options: .atomic)
        }
        for p in targets { kill(p.pid, SIGSTOP) }
        let names = Set(targets.map { URL(fileURLWithPath: $0.path).lastPathComponent }).sorted()
        log("froze \(targets.count) processes: \(names.joined(separator: ", "))")
    }

    /// Resume everything we (or a previous, crashed run) paused.
    func resume() {
        var pids = Set(frozen)
        if let data = FileManager.default.contents(atPath: frozenFile),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            pids.formUnion(list.compactMap { ($0["pid"] as? Int).map(pid_t.init) })
        }
        guard !pids.isEmpty else { return }
        for pid in pids { kill(pid, SIGCONT) }
        try? FileManager.default.removeItem(atPath: frozenFile)
        frozen = []
        log("resumed \(pids.count) processes")
    }

    /// Install the LaunchAgent that resumes paused apps if Console Mode is gone.
    static func installWatchdog() {
        guard let script = resource("watchdog") else { return }
        let plistPath = home + "/Library/LaunchAgents/local.consolemode.watchdog.plist"
        let plist: [String: Any] = [
            "Label": "local.consolemode.watchdog",
            "ProgramArguments": [script],
            "StartInterval": 15,
            "RunAtLoad": true,
        ]
        if let existing = NSDictionary(contentsOfFile: plistPath), existing.isEqual(to: plist) { return }
        (plist as NSDictionary).write(toFile: plistPath, atomically: true)
        run("/bin/launchctl", ["bootout", "gui/\(getuid())/local.consolemode.watchdog"])
        run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistPath])
        log("watchdog installed")
    }
}
