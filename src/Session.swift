import Cocoa
import SwiftUI

// Shared state between Console Mode and bottle-launch, user config, and the observable model
// the extra displays render (Now Playing, controller battery, storage notes).

let sessionFile = supportDir + "/session.json"
let configFile = supportDir + "/config.json"
let steamUserdata = NSHomeDirectory() + "/Library/Application Support/Steam/userdata"
let bottleSteamDir = NSHomeDirectory() + "/Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam"

// MARK: - Config (~/Library/Application Support/Console Mode/config.json, all keys optional)

struct Config {
    /// Substring of the audio output to switch to in game mode (e.g. "LG TV", "AirPods"). Unset = don't switch.
    var gamingAudioOutput: String? = nil
    /// Show the Now Playing card on extra displays while a game runs.
    var nowPlaying = true
    /// Warn once per session when a drive has less than this many GB free.
    var lowStorageGB = 50.0
    /// Snapshot saves every time they change while playing (feeds Save Rewind).
    var rewindSnapshots = true
    /// Keep Mac Steam loaded (invisible) after "back to PC" so the next Xbox press opens in ~1 s.
    /// false = quit Steam completely on exit (next start ~3-5 s).
    var keepSteamLoaded = true

    static func load() -> Config {
        var c = Config()
        guard let d = FileManager.default.contents(atPath: configFile),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return c }
        c.gamingAudioOutput = j["gamingAudioOutput"] as? String
        c.nowPlaying = j["nowPlaying"] as? Bool ?? c.nowPlaying
        c.lowStorageGB = (j["lowStorageGB"] as? NSNumber)?.doubleValue ?? c.lowStorageGB
        c.rewindSnapshots = j["rewindSnapshots"] as? Bool ?? c.rewindSnapshots
        c.keepSteamLoaded = j["keepSteamLoaded"] as? Bool ?? c.keepSteamLoaded
        return c
    }
}

// MARK: - Session file (written by bottle-launch and Console Mode)

/// state: launching | playing | suspended | resume-request | ended
struct Session {
    var state: String
    var name: String
    var shortcut: UInt32      // Mac Steam shortcut app id (0 if unknown)
    var target: String        // "steam <appid>" or "exe <path>"
    var time: Double          // when the game was launched

    static func read() -> Session? {
        guard let d = FileManager.default.contents(atPath: sessionFile),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return Session(state: j["state"] as? String ?? "ended", name: j["name"] as? String ?? "Game",
                       shortcut: UInt32((j["shortcut"] as? NSNumber)?.uint64Value ?? 0),
                       target: j["target"] as? String ?? "", time: (j["time"] as? NSNumber)?.doubleValue ?? 0)
    }

    func write() {
        try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        let j: [String: Any] = ["state": state, "name": name, "shortcut": shortcut, "target": target, "time": time]
        if let d = try? JSONSerialization.data(withJSONObject: j) { try? d.write(to: URL(fileURLWithPath: sessionFile), options: .atomic) }
    }

    static func setState(_ s: String) { if var cur = read() { cur.state = s; cur.write() } }
}

// MARK: - Game artwork (Mac Steam grid folder, then the bottle's Steam cache)

struct GameArt { var portrait: NSImage?; var hero: NSImage?; var logo: NSImage? }

func gameArt(for session: Session) -> GameArt {
    var art = GameArt()
    let fm = FileManager.default
    func find(_ dir: String, _ names: [String]) -> NSImage? {
        for n in names { for ext in ["png", "jpg", "jpeg", "webp"] {
            let p = "\(dir)/\(n).\(ext)"
            if fm.fileExists(atPath: p), let img = NSImage(contentsOfFile: p) { return img }
        } }
        return nil
    }
    if session.shortcut != 0 {
        for user in (try? fm.contentsOfDirectory(atPath: steamUserdata)) ?? [] where user != "0" {
            let grid = "\(steamUserdata)/\(user)/config/grid", id = String(session.shortcut)
            art.portrait = art.portrait ?? find(grid, ["\(id)p"])
            art.hero = art.hero ?? find(grid, ["\(id)_hero", id])
            art.logo = art.logo ?? find(grid, ["\(id)_logo"])
        }
    }
    if session.target.hasPrefix("steam ") {
        let appid = String(session.target.dropFirst(6))
        let cache = "\(bottleSteamDir)/appcache/librarycache/\(appid)"
        func deep(_ file: String) -> NSImage? {
            guard let e = fm.enumerator(atPath: cache) else { return nil }
            for case let f as String in e where f.hasSuffix(file) { if let i = NSImage(contentsOfFile: "\(cache)/\(f)") { return i } }
            return nil
        }
        art.portrait = art.portrait ?? deep("library_600x900.jpg")
        art.hero = art.hero ?? deep("library_hero.jpg") ?? deep("header.jpg")
        art.logo = art.logo ?? deep("logo.png")
    }
    return art
}

// MARK: - What the extra displays show

struct NowPlaying: Equatable {
    var name: String
    var started: Date
    var suspended: Bool
    var art: GameArt
    static func == (a: NowPlaying, b: NowPlaying) -> Bool { a.name == b.name && a.started == b.started && a.suspended == b.suspended }
}

@MainActor
final class ScreenModel: ObservableObject {
    static let shared = ScreenModel()
    @Published var nowPlaying: NowPlaying?
    @Published var battery: Float?          // 0...1
    @Published var charging = false
    @Published var storageNote: String?     // e.g. "Games drive · 42 GB free"
}

// MARK: - Small helpers

/// GB free on the volume holding `path`.
func freeGB(_ path: String) -> Double? {
    guard let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
          let bytes = v.volumeAvailableCapacityForImportantUsage else {
        guard let a = try? FileManager.default.attributesOfFileSystem(forPath: path), let f = a[.systemFreeSize] as? NSNumber else { return nil }
        return f.doubleValue / 1e9
    }
    return Double(bytes) / 1e9
}

/// Every process belonging to a bottle game (the .exe itself plus Wine processes named after it).
func gamePIDs(_ exeName: String) -> [pid_t] {
    var pids = Set(NSWorkspace.shared.runningApplications.filter { $0.localizedName == exeName }.map(\.processIdentifier))
    do {
        let out = capture("/bin/ps", ["-Ao", "pid=,command="]).output
        for line in out.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let pid = pid_t(parts[0]) else { continue }
            // Wine shows the Windows path as the command: "C:\Program Files\...\Game.exe args" (paths can contain spaces)
            let cmd = parts[1].lowercased(), exe = "\\" + exeName.lowercased()
            let isWindowsPath = cmd.count > 2 && cmd.dropFirst().hasPrefix(":\\")
            if isWindowsPath, let r = cmd.range(of: exe),
               r.upperBound == cmd.endIndex || cmd[r.upperBound] == " " {
                pids.insert(pid)
            }
        }
    }
    return Array(pids)
}
