import Cocoa
import ApplicationServices

// Instant start. Console Mode stays resident after "back to PC", and Mac Steam stays loaded
// with Big Picture minimized, so the next Xbox press only has to un-minimize a window (~0.1 s
// instead of a 3-5 s cold start).
//
// Minimizing another app's window needs the Accessibility permission for Console Mode
// (System Settings > Privacy & Security > Accessibility). Without it Steam is quit on exit and
// cold-started on the next press, the same as before.

let steamHelperBundle = "com.valvesoftware.steam.helper"
let bottlePrefix = NSHomeDirectory() + "/Library/Application Support/CrossOver/Bottles/Steam"
let wineserver = "/Applications/CrossOverGPTK4.app/Contents/SharedSupport/CrossOver/bin/wineserver"

@MainActor
final class Standby {
    var trusted: Bool { AXIsProcessTrusted() }

    /// Ask macOS for the Accessibility permission once (shows the system prompt if not granted).
    func requestPermissionIfNeeded() {
        guard !trusted else { return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        log("Accessibility not granted yet: instant start disabled until it is")
    }

    private func helperElement() -> AXUIElement? {
        guard let h = NSRunningApplication.runningApplications(withBundleIdentifier: steamHelperBundle).first else { return nil }
        return AXUIElementCreateApplication(h.processIdentifier)
    }

    /// The Big Picture window: the Steam Helper window that covers the whole main display.
    private func bigPictureWindow() -> AXUIElement? {
        guard trusted, let app = helperElement(), let screen = NSScreen.screens.first else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for w in windows {
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef) == .success, let sizeRef else { continue }
            var size = CGSize.zero
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
            if size.width >= screen.frame.width && size.height >= screen.frame.height { return w }
        }
        return nil
    }

    /// Is Big Picture in a macOS native full-screen Space? (diagnostics)
    func bigPictureIsNativeFullScreen() -> Bool? {
        guard let win = bigPictureWindow() else { return nil }
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, "AXFullScreen" as CFString, &v) == .success else { return nil }
        return (v as? Bool) ?? false
    }

    /// How Big Picture was tucked away, so waking can undo exactly that.
    enum Parked { case none, minimized, moved(CGPoint), closed }
    private(set) var parked: Parked = .none

    private func position(_ w: AXUIElement) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &ref) == .success, let ref else { return nil }
        var p = CGPoint.zero; AXValueGetValue(ref as! AXValue, .cgPoint, &p); return p
    }

    private func setPosition(_ w: AXUIElement, _ p: CGPoint) -> Bool {
        var pt = p
        guard let v = AXValueCreate(.cgPoint, &pt) else { return false }
        return AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) == .success
    }

    /// Back to PC: keep Steam loaded, tuck Big Picture away. Tries each method and checks it really
    /// left the screen before moving on: minimize → move off-screen → close Big Picture.
    func park(done: @escaping () -> Void = {}) {
        guard let win = bigPictureWindow() else {
            NSRunningApplication.runningApplications(withBundleIdentifier: steamBundle).forEach { $0.terminate() }
            log("standby: no Accessibility or no Big Picture window, quit Steam instead")
            parked = .none; done(); return
        }
        let original = position(win) ?? .zero
        let r = AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            if !bigPictureReady() { parked = .minimized; log("standby: Big Picture parked (minimized)"); done(); return }
            // Full-screen Big Picture ignores minimize: move it past every display instead.
            let farRight = NSScreen.screens.map(\.frame.maxX).max() ?? 4000
            let moved = setPosition(win, CGPoint(x: farRight + 400, y: 0))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
                if moved && !bigPictureReady() { parked = .moved(original); log("standby: Big Picture parked (moved off-screen; minimize result \(r.rawValue))"); done(); return }
                // Last resort: let Steam close Big Picture, then tuck away the desktop window it opens.
                NSWorkspace.shared.open(URL(string: "steam://close/bigpicture")!)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                    minimizeHelperWindows()
                    parked = .closed
                    log("standby: Big Picture closed (minimize \(r.rawValue), move \(moved))")
                    done()
                }
            }
        }
    }

    private func minimizeHelperWindows() {
        guard let app = helperElement() else { return }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return }
        for w in windows { AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
    }

    /// Xbox press: bring a parked Big Picture straight back. Returns false if there's nothing parked.
    func wake() -> Bool {
        switch parked {
        case .none, .closed:
            parked = .none
            return false                         // caller opens Big Picture the normal (warm) way
        case .minimized, .moved:
            guard let win = bigPictureWindow() else { parked = .none; return false }
            if case .moved(let p) = parked { _ = setPosition(win, p) }
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            parked = .none
            bringToFront(bigPicture)
            log("standby: Big Picture restored")
            return true
        }
    }

    /// At login: start Steam invisibly so the first Xbox press only has to open Big Picture.
    func preloadSteam() {
        guard !steamRunning() else { return }
        DispatchQueue.global().async {
            if let sync = resource("add-game") { run(sync, ["--sync"]) }   // Steam is closed: safe to update tiles
            run("/usr/bin/open", ["-g", "-b", steamBundle, "--args", "-silent"])
            log("standby: Steam preloaded in the background")
        }
    }

    // MARK: Bottle warm-up

    /// Start the bottle's Steam quietly if any tile needs it for DRM, so the first game starts faster.
    /// (No persistent Wine server: it's a different build from the CrossOver app and stops the app
    /// from launching Steam in the same bottle.)
    func warmBottle() {
        DispatchQueue.global(qos: .utility).async {
            guard Standby.hasBottleSteamTiles(), !bottleSteamRunning() else { return }
            run(wine, ["--bottle", "Steam", "--no-wait", "C:\\Program Files (x86)\\Steam\\steam.exe", "-silent"])
            log("warm-up: bottle Steam started silently")
        }
    }

    nonisolated static func hasBottleSteamTiles() -> Bool {
        guard let tool = Bundle.main.path(forResource: "add-game", ofType: nil) else { return false }
        return capture(tool, ["--list"]).output.contains(": steam ")
    }
}
