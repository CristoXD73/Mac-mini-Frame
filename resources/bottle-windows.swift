// Prints the owner name of a large on-screen window belonging to a bottle
// program (owner name ends in ".exe"), ignoring Steam's own windows.
// Prints nothing and exits 1 if there is none. Used by bottle-launch.
import CoreGraphics
import Foundation

let ignored: Set<String> = [
    "steam.exe", "steamwebhelper.exe", "steamservice.exe", "gameoverlayui.exe",
    "explorer.exe", "services.exe", "winedevice.exe", "plugplay.exe", "rpcss.exe",
    "svchost.exe", "conhost.exe", "start.exe", "winemenubuilder.exe", "crashhandler.exe",
]

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                      kCGNullWindowID) as? [[String: Any]] ?? []
for w in list {
    guard let owner = w[kCGWindowOwnerName as String] as? String,
          owner.lowercased().hasSuffix(".exe"),
          !ignored.contains(owner.lowercased()),
          (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
          let b = w[kCGWindowBounds as String] as? [String: Double],
          (b["Width"] ?? 0) >= 640, (b["Height"] ?? 0) >= 400
    else { continue }
    print(owner)
    exit(0)
}
exit(1)
