import Cocoa
// Print the owner of any large on-screen window from the bottle that isn't Steam or a system helper.
let skip: Set<String> = ["steam.exe", "steamwebhelper.exe", "explorer.exe", "services.exe", "winedevice.exe", "plugplay.exe",
    "svchost.exe", "rpcss.exe", "conhost.exe", "start.exe", "steamerrorreporter.exe", "crashhandler.exe"]
// All windows, not just the current Space's: Wine puts full-screen games in their own Space.
let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in info {
    guard let o = w[kCGWindowOwnerName as String] as? String, o.lowercased().hasSuffix(".exe"), !skip.contains(o.lowercased()),
          let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) >= 640, (b["Height"] ?? 0) >= 480 else { continue }
    print(o); break
}
