import Cocoa
import ApplicationServices

// Shared paths, logging and small helpers for Console Mode.

/// Drive the games live on (Console Mode waits for it at start). Override with "gamesDrive" in
/// ~/Library/Application Support/Console Mode/config.json.
let gamesDrive: String = {
    let cfg = NSHomeDirectory() + "/Library/Application Support/Console Mode/config.json"
    if let d = FileManager.default.contents(atPath: cfg),
       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let v = j["gamesDrive"] as? String { return v }
    return "/Volumes/circular"
}()
let bigPicture = "Steam Helper"
let steamBundle = "com.valvesoftware.steam"
let wine = "/Applications/CrossOverGPTK4.app/Contents/SharedSupport/CrossOver/bin/wine"
let supportDir = NSString(string: "~/Library/Application Support/Console Mode").expandingTildeInPath
let logURL = URL(fileURLWithPath: NSString(string: "~/Library/Logs/ConsoleMode.log").expandingTildeInPath)

// Windows processes in the bottle that aren't games.
let notGames: Set<String> = ["steam.exe", "steamwebhelper.exe", "explorer.exe", "services.exe", "winedevice.exe",
    "plugplay.exe", "svchost.exe", "rpcss.exe", "conhost.exe", "start.exe", "steamerrorreporter.exe", "crashhandler.exe"]

func log(_ s: String) {
    let line = "[console-mode \(Date())] \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
}

@discardableResult
func run(_ path: String, _ args: [String]) -> Int32 {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return -1 }
    p.waitUntilExit(); return p.terminationStatus
}

/// Run a helper and return its exit status and output. Reads the output BEFORE waiting: a helper
/// that prints more than the pipe buffer (64 KB) would otherwise block forever.
@discardableResult
func capture(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
    let p = Process(); let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

/// Start a helper without waiting for it.
func spawn(_ path: String, _ args: [String]) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try? p.run()
}

func resource(_ name: String) -> String? { Bundle.main.path(forResource: name, ofType: nil) }

func steamRunning() -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: steamBundle).isEmpty }
func bottleSteamRunning() -> Bool { run("/usr/bin/pgrep", ["-f", "Steam\\\\steam.exe"]) == 0 }

func isRunning(_ name: String) -> Bool {
    NSWorkspace.shared.runningApplications.contains { $0.localizedName == name }
}

@MainActor
func bringToFront(_ name: String) {
    let match = name == bigPicture
        ? NSRunningApplication.runningApplications(withBundleIdentifier: steamBundle).first
        : NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })
    guard let app = match else { log("bringToFront: \(name) not running"); return }
    // Cooperative activation (macOS 14+): become active ourselves, then hand activation over.
    NSApp.activate()
    app.unhide()
    NSApp.yieldActivation(to: app)
    var ok = app.activate(from: .current, options: [])
    // Background apps can be refused; with Accessibility, raising through AX always works and also
    // switches to the Space the app's window is on (Wine puts full-screen games in their own Space).
    if AXIsProcessTrusted() {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        ok = AXUIElementSetAttributeValue(el, kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success || ok
    }
    log("bringToFront \(name): \(ok ? "ok" : "refused")")
}

// Owner of a large window from the bottle that isn't Steam itself. Includes windows that aren't on
// the current Space: Wine puts full-screen games in their own Space, and activating the game (what
// bringToFront does) switches to it.
func gameWindowOwner() -> String? { gameWindow()?.owner }

/// Does this app have windows on another Space? Activating such an app makes macOS slide over to that
/// Space (the "switch to a Space with open windows" setting). Wine games always keep a few there.
func hasWindowsOnOtherSpaces(_ owner: String) -> Bool {
    guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
    return info.contains { ($0[kCGWindowOwnerName as String] as? String) == owner && !($0[kCGWindowIsOnscreen as String] as? Bool ?? false)
        && ((($0[kCGWindowBounds as String] as? [String: CGFloat])?["Width"] ?? 0) >= 640) }
}

/// The game's main window and whether it's on the current Space yet. Bringing a game forward before
/// its window is on the current Space makes macOS slide to another Space (a visible animation).
func gameWindow() -> (owner: String, onCurrentSpace: Bool)? {
    guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    var found: (String, Bool)?
    for w in info {
        guard let owner = w[kCGWindowOwnerName as String] as? String, owner.lowercased().hasSuffix(".exe"),
              !notGames.contains(owner.lowercased()),
              let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) >= 640, (b["Height"] ?? 0) >= 480
        else { continue }
        let on = w[kCGWindowIsOnscreen as String] as? Bool ?? false
        if on { return (owner, true) }
        found = found ?? (owner, false)
    }
    return found
}

// Full-screen Big Picture window on the main display (not a login/update popup).
func bigPictureReady() -> Bool {
    guard let screen = NSScreen.screens.first,
          let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    return info.contains { w in
        guard (w[kCGWindowOwnerName as String] as? String) == bigPicture,
              let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
        return (b["Width"] ?? 0) >= screen.frame.width && (b["Height"] ?? 0) >= screen.frame.height
    }
}
