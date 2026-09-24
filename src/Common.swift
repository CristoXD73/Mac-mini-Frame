import AppKit
import CoreGraphics
import Foundation

// MARK: - Paths and constants (see docs/HANDOFF.md section 9 when porting)

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let appName = "Console Mode"
    static let bundleID = "local.consolemode"
    static let processName = "ConsoleMode"

    static let support = home + "/Library/Application Support/Console Mode"
    static let frozenFile = support + "/frozen.json"
    static let logFile = home + "/Library/Logs/ConsoleMode.log"
    static let screenshots = home + "/Pictures/Console Mode"

    static let gamesDrive = "/Volumes/circular"
    static let crossOverApp = "/Applications/CrossOverGPTK4.app"
    static let wineDir = crossOverApp + "/Contents/SharedSupport/CrossOver"
    static let wine = wineDir + "/bin/wine"
    static let bottleName = "Steam"
    static let bottles = home + "/Library/Application Support/CrossOver/Bottles"
    static let bottle = bottles + "/" + bottleName

    static let macSteamApp = "/Applications/Steam.app"
    static let macSteamBundleID = "com.valvesoftware.steam"
    static let macSteamSupport = home + "/Library/Application Support/Steam"

    static let watchdogLabel = "local.consolemode.watchdog"
    static let watchdogPlist = home + "/Library/LaunchAgents/\(watchdogLabel).plist"

    static var resources: String { Bundle.main.resourcePath ?? (Bundle.main.bundlePath + "/Contents/Resources") }
    static func resource(_ name: String) -> String { resources + "/" + name }
}

// MARK: - Logging

private let logQueue = DispatchQueue(label: "log")
private let logDateFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

func log(_ message: String) {
    let line = "\(logDateFormat.string(from: Date())) [app] \(message)\n"
    logQueue.async {
        let url = URL(fileURLWithPath: Paths.logFile)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        } else {
            try? line.data(using: .utf8)!.write(to: url)
        }
    }
}

// MARK: - Processes

/// Runs a program to completion and returns (exit status, stdout).
@discardableResult
func run(_ path: String, _ args: [String] = [], env: [String: String]? = nil) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if let env { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch {
        log("run failed: \(path) \(args): \(error)")
        return (-1, "")
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// Starts a program without waiting; stdout/stderr go to the log file.
@discardableResult
func spawn(_ path: String, _ args: [String] = [], onExit: (@Sendable (Int32) -> Void)? = nil) -> Process? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if let h = FileHandle(forWritingAtPath: Paths.logFile) {
        h.seekToEndOfFile()
        p.standardOutput = h
        p.standardError = h
    }
    if let onExit { p.terminationHandler = { onExit($0.terminationStatus) } }
    do { try p.run() } catch {
        log("spawn failed: \(path) \(args): \(error)")
        return nil
    }
    return p
}

// MARK: - Activation

/// Brings another app forward from this accessory app. macOS 14+ refuses a
/// plain activate() from a background app, so use cooperative activation:
/// activate ourselves, yield to the target, then let the target activate.
@MainActor
func bringToFront(_ app: NSRunningApplication) {
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
    NSApp.activate()
    NSApp.yieldActivation(to: app)
    app.activate(from: NSRunningApplication.current, options: [.activateAllWindows])
}

func macSteam() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: Paths.macSteamBundleID).first
}

// MARK: - Windows

/// Bottle programs whose windows are never "the game".
let nonGameExes: Set<String> = [
    "steam.exe", "steamwebhelper.exe", "steamservice.exe", "gameoverlayui.exe",
    "explorer.exe", "services.exe", "winedevice.exe", "plugplay.exe", "rpcss.exe",
    "svchost.exe", "conhost.exe", "start.exe", "winemenubuilder.exe", "crashhandler.exe",
]

struct WindowInfo {
    let owner: String
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
}

func onScreenWindows() -> [WindowInfo] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                          kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { w in
        guard let owner = w[kCGWindowOwnerName as String] as? String,
              let pid = w[kCGWindowOwnerPID as String] as? pid_t,
              let b = w[kCGWindowBounds as String] as? [String: Double],
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0
        else { return nil }
        return WindowInfo(owner: owner, pid: pid,
                          layer: w[kCGWindowLayer as String] as? Int ?? 0,
                          bounds: CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                                         width: b["Width"] ?? 0, height: b["Height"] ?? 0))
    }
}

/// The owner (e.g. "Cyberpunk2077.exe") and pid of a large bottle game window.
/// Full-screen Wine windows sit at layer 26, windowed ones at 0.
func gameWindowOwner() -> (name: String, pid: pid_t)? {
    for w in onScreenWindows() {
        let lower = w.owner.lowercased()
        guard lower.hasSuffix(".exe"), !nonGameExes.contains(lower),
              w.bounds.width >= 640, w.bounds.height >= 400 else { continue }
        return (w.owner, w.pid)
    }
    return nil
}

/// True once Mac Steam shows a window covering most of the main display
/// (Big Picture is a single full-screen window).
func bigPictureReady() -> Bool {
    guard let steam = macSteam(), let main = NSScreen.screens.first else { return false }
    let area = main.frame.width * main.frame.height
    let steamPids = Set(steamProcessIDs()).union([steam.processIdentifier])
    return onScreenWindows().contains { w in
        steamPids.contains(w.pid) && w.bounds.width * w.bounds.height >= area * 0.8
    }
}

/// All Mac Steam processes (steam_osx and its helpers).
func steamProcessIDs() -> [pid_t] {
    ProcessList.all().filter { $0.path.hasPrefix(Paths.macSteamSupport + "/") || $0.path.hasPrefix(Paths.macSteamApp + "/") }
        .map(\.pid)
}

// MARK: - Process list (shared by Freezer and shutdown)

struct ProcInfo {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let path: String
    let stopped: Bool
}

enum ProcessList {
    /// Every process of the current user, via sysctl(KERN_PROC_UID).
    static func all() -> [ProcInfo] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 16)
        size = procs.count * stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        let count = size / stride
        var result: [ProcInfo] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            var kp = procs[i]
            let pid = kp.kp_proc.p_pid
            let name = withUnsafePointer(to: &kp.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
            }
            result.append(ProcInfo(pid: pid, ppid: kp.kp_eproc.e_ppid, name: name,
                                   path: path(of: pid), stopped: Int32(kp.kp_proc.p_stat) == SSTOP))
        }
        return result
    }

    static func path(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : ""
    }
}

// MARK: - Main-thread scheduling

/// Runs `work` on the main actor after `seconds`.
func onMain(after seconds: Double, _ work: @escaping @MainActor () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(work) }
}

/// Runs `work` on the main actor as soon as possible (from any thread).
func onMain(_ work: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated(work) }
}
