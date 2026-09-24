import Cocoa
import GameController
import IOKit.hid

// Controller input for Console Mode.
//
// The home button (Xbox / PS / Steam) belongs to macOS: pressing it is what opens Console Mode,
// and the GameController framework never reports it as held. The raw HID report still does, so
// the hold is read from there (Button page, usage 13 on Xbox and DualSense controllers). The D-pad
// is also read from HID (hat switch), because GameController doesn't deliver it while Steam is in
// front. Everything else comes through GameController, which works in the background and labels
// buttons the same way on every controller.
//
//   Hold home 6 s               -> back to PC (ring shows after 2 s)
//   Home + View (on release)    -> screenshot
//   Home + Menu + View          -> force quit the game (press twice to confirm)
//   Home + D-pad up / down      -> volume
//   Home + Y                    -> performance overlay
//   Home + X                    -> Quick Resume: suspend / resume the game
//   Home + LB                   -> Save Rewind
// Pressing any other button while home is held cancels the countdown for that hold.
// While a Console Mode screen is open (Save Rewind), buttons go to it instead (`navSink`).

let holdToExit: TimeInterval = 6
let holdRingDelay: TimeInterval = 2
/// While the Xbox button is held the controller keeps dropping and re-announcing its HID interface.
/// A gap shorter than this is the same hold, not a release.
let holdGrace: TimeInterval = 0.6
let homeButtonPage: UInt32 = 0x09, homeButtonUsage: UInt32 = 0x0D
let padVendors: [Int: Pad] = [0x045E: .xbox, 0x054C: .playstation, 0x28DE: .steam]

enum Combo { case screenshot, volumeUp, volumeDown, stats, suspend, forceQuit, rewind }

@MainActor
final class Input {
    var onHoldProgress: (TimeInterval) -> Void = { _ in }   // seconds held, while no combo was used
    var onHoldCancelled: () -> Void = {}
    var onHoldComplete: () -> Void = {}
    var onCombo: (Combo) -> Void = { _ in }
    /// When set, plain button presses (home not held) are routed here instead of being ignored.
    var navSink: ((Nav) -> Void)?
    /// Home button went down (read straight from the controller, so it works even when macOS
    /// doesn't re-send its "open app" event to an already-running Console Mode).
    var onHomePressed: () -> Void = {}

    /// Which kind of controller was used most recently (picks the takeover animation).
    private(set) var lastPad: Pad = .xbox

    private var hid: IOHIDManager?
    private var hidOK = false
    private var hidHomeDown = false
    private var simulatedHoldUntil: Date?        // test channel: pretend the home button is held
    private var volumeRepeat: Timer?
    private var holdStart: Date?
    private var lastHeldAt = Date.distantPast
    private var lastHomeDownEvent = Date.distantPast
    /// The HID interface that reported the Xbox button. The controller exposes several; only losing
    /// *this* one can mean the button was released.
    private var homeDevice: IOHIDDevice?
    private var comboUsedThisHold = false
    private var completed = false
    private var viewPressedAt: Date?
    /// The press that started game mode must be released before a hold can mean "back to PC".
    private var ignoreHoldUntilRelease = false
    private var ignoreHoldSince = Date.distantPast
    private var menuUsedWithView = false

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        GCController.startWirelessControllerDiscovery {}
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? GCController { MainActor.assumeIsolated { self?.attach(c) } }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? GCController { MainActor.assumeIsolated { self?.notePad(c) } }
        }
        // A controller that disconnects mid-press never sends the release: forget any held state.
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            // Only a real "no controller left" counts; a controller re-announcing itself doesn't.
            MainActor.assumeIsolated { if GCController.controllers().isEmpty { self?.resetButtons("all controllers disconnected") } }
        }
        GCController.controllers().forEach(attach)
        startHID()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    /// False while macOS blocks the raw controller reading (Input Monitoring missing): holds can't be seen.
    var rawInputAvailable: Bool { hidOK }

    var homeHeld: Bool {
        hidHomeDown || (simulatedHoldUntil.map { Date() < $0 } ?? false)
            || GCController.controllers().contains { $0.extendedGamepad?.buttonHome?.isPressed == true }
    }

    /// Test channel: behave exactly as if the home button were held for `seconds`.
    func simulateHold(_ seconds: TimeInterval) { simulatedHoldUntil = Date().addingTimeInterval(seconds) }

    /// Test channel: a hold with the short drops a real Xbox controller produces (held 0.7 s,
    /// gone 0.3 s, repeated), including the "controller removed" callbacks.
    func simulateFlickeringHold(_ seconds: TimeInterval) {
        let start = Date()
        func pulse() {
            guard Date().timeIntervalSince(start) < seconds else { return }
            simulatedHoldUntil = Date().addingTimeInterval(0.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.deviceDropped()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { pulse() }
            }
        }
        pulse()
    }
    /// Test channel: a home-button press edge.
    func simulatePress() { onHomePressed() }

    /// Battery of the controller in use, if it reports one.
    func battery() -> (level: Float, charging: Bool)? {
        guard let c = GCController.current ?? GCController.controllers().first, let b = c.battery,
              b.batteryState != .unknown || b.batteryLevel > 0 else { return nil }
        return (b.batteryLevel, b.batteryState == .charging || b.batteryState == .full)
    }

    // MARK: HID (home button hold, D-pad, which controller is in use)

    /// Reading the controller's raw HID reports counts as "Input Monitoring" to macOS.
    static func inputMonitoringStatus() -> String {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return "granted"
        case kIOHIDAccessTypeDenied: return "denied"
        default: return "not decided"
        }
    }

    private var requestedAccess = false

    private func startHID() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Only the gamepad/joystick interfaces. Controllers also expose keyboard-like interfaces (the Xbox
        // one's comes and goes), and opening one of those needs Input Monitoring and fails without it.
        let matches: [[String: Int]] = padVendors.keys.flatMap { v in
            [[kIOHIDVendorIDKey: v, kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x05],
             [kIOHIDVendorIDKey: v, kIOHIDDeviceUsagePageKey: 0x01, kIOHIDDeviceUsageKey: 0x04]]
        }
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)
        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx else { return }
            let e = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(e), usage = IOHIDElementGetUsage(e)
            let raw = IOHIDValueGetIntegerValue(value)
            let vendor = (IOHIDDeviceGetProperty(IOHIDElementGetDevice(e), kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            let me = Unmanaged<Input>.fromOpaque(ctx).takeUnretainedValue()
            let device = IOHIDElementGetDevice(e)
            if page == 0x01 && usage == 0x39 {
                // D-pad hat switch. Directions run clockwise from "up" starting at the logical minimum
                // (0...7 or 1...8 depending on the controller); anything outside that range is "centered".
                let lo = IOHIDElementGetLogicalMin(e), hi = IOHIDElementGetLogicalMax(e)
                let dir = (raw >= lo && raw <= hi && hi - lo == 7) ? Int(raw - lo) : -1
                MainActor.assumeIsolated { me.hat(dir) }
                return
            }
            guard page == 0x09 else { return }   // buttons only
            let down = raw != 0
            MainActor.assumeIsolated {
                if let pad = padVendors[vendor] { me.lastPad = pad }
                if usage == homeButtonUsage {
                    // A "down" right after a drop is the same hold coming back, not a new press.
                    let reappearing = down && Date().timeIntervalSince(me.lastHeldAt) < holdGrace
                    if down && !me.hidHomeDown && !reappearing { me.onHomePressed() }
                    if down { me.lastHomeDownEvent = Date(); me.homeDevice = device }
                    me.hidHomeDown = down
                    log("hid: Xbox button \(down ? "down" : "up") (interface \(Unmanaged.passUnretained(device).toOpaque()))")
                }
                else if down && me.homeHeld { me.cancelHold() }   // any other button cancels the countdown
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, device in
            guard let ctx else { return }
            let me = Unmanaged<Input>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.deviceRemoved(device) }
        }, Unmanaged.passUnretained(self).toOpaque())
        // (No reset on "device matched": the Xbox controller re-announces an interface on every
        //  Xbox press, which would wipe the press itself.)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        hid = mgr
        hidOK = r == kIOReturnSuccess
        if r == kIOReturnSuccess {
            log("controller HID watch: ok")
        } else {
            // Seen right after macOS restarted the app for a permission change. Try again shortly.
            log("controller HID watch: failed (0x\(String(UInt32(bitPattern: r), radix: 16)), Input Monitoring \(Input.inputMonitoringStatus())), retrying in 5 s")
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.startHID() }
        }
    }

    private var lastHat = -1

    private func hat(_ dir: Int) {
        defer { lastHat = dir }
        guard dir != lastHat else { return }
        volumeRepeat?.invalidate(); volumeRepeat = nil
        guard dir >= 0 else { return }
        if homeHeld {
            cancelHold()
            if dir == 0 || dir == 4 { startVolume(dir == 0 ? .volumeUp : .volumeDown) }
        } else if let sink = navSink {
            let nav: [Int: Nav] = [0: .up, 2: .right, 4: .down, 6: .left]
            if let n = nav[dir] { sendNav(n, sink) }
        }
    }

    /// One step right away, then keep stepping while the D-pad stays held (like a held volume key).
    private func startVolume(_ c: Combo) {
        log("combo: \(c)")
        onCombo(c)
        volumeRepeat = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.volumeRepeat = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] t in
                    MainActor.assumeIsolated {
                        guard let self, self.homeHeld else { t.invalidate(); return }
                        self.onCombo(c)
                    }
                }
            }
        }
    }

    /// Test channel: a combo exactly as the controller would produce it.
    func simulateCombo(_ c: Combo) {
        if c == .volumeUp || c == .volumeDown { startVolume(c); volumeRepeat?.invalidate(); return }
        cancelHold(); fire(c)
    }

    /// Test channel: navigation input for a Console Mode screen.
    func simulateNav(_ n: Nav) { if let sink = navSink { sink(n) } }

    private func cancelHold() {
        guard homeHeld else { return }     // only a button pressed *during* a hold cancels it
        if !comboUsedThisHold { onHoldCancelled() }
        comboUsedThisHold = true
    }

    /// The same press can arrive from both HID and GameController: act on it once.
    private var lastFired: [String: Date] = [:]
    private func once(_ key: String, within: TimeInterval) -> Bool {
        if let t = lastFired[key], Date().timeIntervalSince(t) < within { return false }
        lastFired[key] = Date(); return true
    }

    private func fire(_ combo: Combo) {
        guard once("\(combo)", within: 0.3) else { return }
        log("combo: \(combo)")
        onCombo(combo)
    }

    private func sendNav(_ n: Nav, _ sink: (Nav) -> Void) {
        guard once("nav-\(n)", within: 0.15) else { return }
        sink(n)
    }

    // MARK: GameController (combos + navigation)

    private func notePad(_ c: GCController) {
        let cat = c.productCategory.lowercased()
        if cat.contains("dualsense") || cat.contains("dualshock") { lastPad = .playstation }
        else if cat.contains("xbox") { lastPad = .xbox }
        else if cat.contains("steam") { lastPad = .steam }
    }

    private func attach(_ c: GCController) {
        guard let pad = c.extendedGamepad else { return }
        notePad(c)
        log("controller connected: \(c.vendorName ?? "?") (\(c.productCategory))")
        pad.valueChangedHandler = { [weak self] gp, element in
            MainActor.assumeIsolated { self?.handle(gp, element) }
        }
    }

    private func handle(_ gp: GCExtendedGamepad, _ element: GCControllerElement) {
        guard element !== gp.buttonHome else { return }
        let pressed: (GCControllerButtonInput?) -> Bool = { $0 != nil && element === $0 && $0!.isPressed }
        let released: (GCControllerButtonInput?) -> Bool = { $0 != nil && element === $0 && !$0!.isPressed }

        // Screens that take the controller (Save Rewind).
        if !homeHeld, let sink = navSink {
            if pressed(gp.buttonA) { sendNav(.a, sink) }
            else if pressed(gp.buttonB) { sendNav(.b, sink) }
            else if pressed(gp.leftShoulder) { sendNav(.left, sink) }
            else if pressed(gp.rightShoulder) { sendNav(.right, sink) }
            else if pressed(gp.dpad.left) { sendNav(.left, sink) }
            else if pressed(gp.dpad.right) { sendNav(.right, sink) }
            else if pressed(gp.dpad.up) { sendNav(.up, sink) }
            else if pressed(gp.dpad.down) { sendNav(.down, sink) }
            return
        }

        // Screenshot fires when View is released, unless Menu joined in (that's force quit).
        if released(gp.buttonOptions), let t = viewPressedAt {
            viewPressedAt = nil
            if !menuUsedWithView && Date().timeIntervalSince(t) < 3 { fire(.screenshot) }
            menuUsedWithView = false
            return
        }
        guard homeHeld else { return }
        var combo: Combo?
        if pressed(gp.buttonOptions) {
            viewPressedAt = Date(); menuUsedWithView = gp.buttonMenu.isPressed
            if menuUsedWithView { combo = .forceQuit }
        } else if pressed(gp.buttonMenu), gp.buttonOptions?.isPressed == true {
            menuUsedWithView = true; combo = .forceQuit
        }
        else if !hidOK && pressed(gp.dpad.up) { combo = .volumeUp }       // HID handles the D-pad when it can
        else if !hidOK && pressed(gp.dpad.down) { combo = .volumeDown }
        else if pressed(gp.buttonY) { combo = .stats }
        else if pressed(gp.buttonX) { combo = .suspend }
        else if pressed(gp.leftShoulder) { combo = .rewind }
        let anyPress = (element as? GCControllerButtonInput)?.isPressed == true || element is GCControllerDirectionPad
        if combo != nil || anyPress { cancelHold() }
        if let combo { fire(combo) }
    }

    // MARK: Hold timer

    /// Called when a press has just entered game mode.
    func ignoreCurrentHold() { ignoreHoldUntilRelease = homeHeld; ignoreHoldSince = Date() }

    /// A HID interface went away. The Xbox controller drops one of its *other* interfaces on every
    /// Xbox press while the one carrying the button stays connected, so only losing that one counts.
    func deviceRemoved(_ device: IOHIDDevice) {
        let isHome = homeDevice.map { CFEqual($0, device) } ?? false
        log("hid: interface removed (\(Unmanaged.passUnretained(device).toOpaque()))\(isHome ? ": the one carrying the Xbox button" : ": not the Xbox button's, ignored")")
        if isHome { homeDevice = nil; resetButtons("Xbox button's interface disconnected") }
    }

    /// Kept for the test channel: a drop of some other interface (ignored, like the real thing).
    func deviceDropped() {}

    /// Forget any "button is down" state (lost release events after a disconnect would otherwise
    /// leave the Xbox button stuck as held, which blocks the exit hold).
    func resetButtons(_ why: String) {
        guard hidHomeDown || ignoreHoldUntilRelease || lastHat != -1 else { return }
        hidHomeDown = false; lastHat = -1; ignoreHoldUntilRelease = false
        volumeRepeat?.invalidate(); volumeRepeat = nil
        log("input reset: \(why)")
    }

    private func tick() {
        if homeHeld { lastHeldAt = Date() }
        // A short gap (controller re-announcing itself) doesn't end the hold.
        if !homeHeld, holdStart != nil, Date().timeIntervalSince(lastHeldAt) < holdGrace { return }
        guard homeHeld else {
            // Released: always start the next hold clean.
            ignoreHoldUntilRelease = false; comboUsedThisHold = false; completed = false
            if holdStart != nil { holdStart = nil; onHoldCancelled() }
            return
        }
        // Backstop: never ignore holds for more than 8 s, even if a release was lost.
        if ignoreHoldUntilRelease && Date().timeIntervalSince(ignoreHoldSince) > 8 { ignoreHoldUntilRelease = false }
        guard !ignoreHoldUntilRelease else { return }
        if holdStart == nil { holdStart = Date(); log("home button held") }
        guard !comboUsedThisHold, !completed else { return }
        let t = Date().timeIntervalSince(holdStart!)
        onHoldProgress(t)
        if t >= holdToExit { completed = true; onHoldComplete() }
    }
}
