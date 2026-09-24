import Foundation
import IOKit.pwr_mgt

/// Keeps the displays awake during game mode (a controller doesn't count as
/// user activity) and runs the optional Focus shortcuts.
enum Power {
    private static var assertion: IOPMAssertionID = 0

    static func gameModeOn() {
        if assertion == 0 {
            let r = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Console Mode game mode" as CFString, &assertion)
            if r != kIOReturnSuccess { assertion = 0; log("power: assertion failed") }
        }
        runShortcut("Console Mode On")
    }

    static func gameModeOff() {
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        runShortcut("Console Mode Off")
    }

    /// Runs a Shortcut only if the user created one with that exact name.
    private static func runShortcut(_ name: String) {
        DispatchQueue.global(qos: .utility).async {
            let list = run("/usr/bin/shortcuts", ["list"]).output
            guard list.split(separator: "\n").contains(where: { $0 == name }) else { return }
            let r = run("/usr/bin/shortcuts", ["run", name])
            log("power: shortcut \(name) -> \(r.status)")
        }
    }
}
