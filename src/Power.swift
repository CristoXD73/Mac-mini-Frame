import Cocoa
import IOKit.pwr_mgt

// While in game mode: keep the Mac and its displays awake, and switch notifications off.
//
// macOS has no public API to turn a Focus on, so this runs two Shortcuts if they exist:
// "Console Mode On" (Set Focus: Do Not Disturb / Gaming → On) and "Console Mode Off".

@MainActor
final class Power {
    private var assertion: IOPMAssertionID = 0

    func enterGameMode() {
        if assertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Console Mode: gaming" as CFString, &assertion)
        }
        runShortcut("Console Mode On")
    }

    func leaveGameMode() {
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        runShortcut("Console Mode Off")
    }

    private func runShortcut(_ name: String) {
        DispatchQueue.global().async {
            let names = capture("/usr/bin/shortcuts", ["list"]).output.split(separator: "\n").map(String.init)
            guard names.contains(name) else { return }
            run("/usr/bin/shortcuts", ["run", name])
            log("ran shortcut: \(name)")
        }
    }
}
