import Cocoa
// Every 100 ms: which relevant windows are on the current Space, and which app is in front.
// Prints only when something changes.
var last = ""
let t0 = Date()
while Date().timeIntervalSince(t0) < Double(CommandLine.arguments[1])! {
    let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
    var parts: [String] = []
    for w in info {
        let o = w[kCGWindowOwnerName as String] as? String ?? ""
        let b = w[kCGWindowBounds as String] as! [String: CGFloat]
        guard (b["Width"] ?? 0) >= 1900, (b["Y"] ?? 0) == 0 else { continue }
        guard o == "portal2.exe" || o == "Steam Helper" || o == "Console Mode" else { continue }
        parts.append("\(o)[\((w[kCGWindowIsOnscreen as String] as? Bool ?? false) ? "ON" : "off") L\(w[kCGWindowLayer as String] ?? "")]")
    }
    let s = parts.sorted().joined(separator: " ") + " | front=" + (NSWorkspace.shared.frontmostApplication?.localizedName ?? "")
    if s != last { print(String(format: "%6.1fs  ", Date().timeIntervalSince(t0)) + s); fflush(stdout); last = s }
    usleep(100_000)
}
