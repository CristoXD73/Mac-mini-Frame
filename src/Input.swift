import Foundation
import GameController
import IOKit.hid

enum ControllerStyle: String {
    case xbox, playstation, steam

    static func from(vendor: Int) -> ControllerStyle {
        switch vendor {
        case 0x054C: return .playstation
        case 0x28DE: return .steam
        default: return .xbox
        }
    }

    static func from(category: String) -> ControllerStyle? {
        let c = category.lowercased()
        if c.contains("dualsense") || c.contains("dualshock") || c.contains("playstation") { return .playstation }
        if c.contains("xbox") { return .xbox }
        if c.contains("steam") { return .steam }
        return nil
    }
}

enum Combo: String {
    case volumeUp, volumeDown, stats, screenshot
}

@MainActor
protocol InputDelegate: AnyObject {
    func homeHoldProgress(_ seconds: Double)   // called ~10x/s while held
    func homeHoldCancelled()
    func homeHeldToExit()
    func combo(_ combo: Combo)
}

/// macOS owns the controller's home button: pressing it runs the System
/// Settings action (which opens this app), and GameController never reports it
/// as held. So the hold and the D-pad (not delivered while Steam is in front)
/// come from raw IOHID reports; Y and View come from GameController.
@MainActor
final class Input {
    static let holdToExit: Double = 6

    weak var delegate: InputDelegate?
    private(set) var style: ControllerStyle = .xbox

    private var manager: IOHIDManager?
    private var homeDown: Date?
    private var holdCancelled = false
    private var holdTimer: Timer?
    private var lastCombo: [Combo: Date] = [:]
    private var hatWasCentered = true

    // HID usages (verified with tools/hidprobe.swift on Xbox 0x0B13).
    private let buttonPage = 0x09
    private let homeUsage = 0x0D
    private let desktopPage = 0x01
    private let hatUsage = 0x39

    var homeHeld: Bool { homeDown != nil && !holdCancelled }

    func start() {
        startHID()
        startGameController()
    }

    // MARK: IOHID

    private func startHID() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let vendors = [0x045E, 0x054C, 0x28DE]  // Microsoft, Sony, Valve
        let matches = vendors.map { [kIOHIDVendorIDKey: $0] as CFDictionary }
        IOHIDManagerSetDeviceMatchingMultiple(m, matches as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "?"
            MainActor.assumeIsolated {
                let me = Unmanaged<Input>.fromOpaque(ctx).takeUnretainedValue()
                me.style = .from(vendor: vendor)
                log("hid: controller connected: \(product) vendor 0x\(String(vendor, radix: 16))")
            }
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(m, { ctx, _, _, value in
            guard let ctx else { return }
            let element = IOHIDValueGetElement(value)
            let page = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            let v = IOHIDValueGetIntegerValue(value)
            let min = IOHIDElementGetLogicalMin(element)
            MainActor.assumeIsolated {
                Unmanaged<Input>.fromOpaque(ctx).takeUnretainedValue()
                    .hidValue(page: page, usage: usage, value: v, logicalMin: min)
            }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess { log("hid: IOHIDManagerOpen failed: 0x\(String(r, radix: 16))") }
        manager = m
    }

    private func hidValue(page: Int, usage: Int, value: Int, logicalMin: Int) {
        if page == buttonPage && usage == homeUsage {
            value != 0 ? homePressed() : homeReleased()
        } else if page == buttonPage && value != 0 {
            otherButton()
        } else if page == desktopPage && usage == hatUsage {
            hat(value - logicalMin)
        }
    }

    // Hat directions run clockwise from "up" starting at the logical minimum;
    // anything out of 0...7 is centered.
    private func hat(_ index: Int) {
        let centered = !(0...7).contains(index)
        defer { hatWasCentered = centered }
        guard hatWasCentered, !centered else { return }
        if homeDown != nil {
            if index == 0 { fire(.volumeUp) } else if index == 4 { fire(.volumeDown) } else { otherButton() }
        }
    }

    // MARK: home hold

    private func homePressed() {
        guard homeDown == nil else { return }
        homeDown = Date()
        holdCancelled = false
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let down = homeDown, !holdCancelled else { return }
        let held = Date().timeIntervalSince(down)
        if held >= Self.holdToExit {
            holdTimer?.invalidate()
            holdTimer = nil
            holdCancelled = true  // fire once per hold
            delegate?.homeHeldToExit()
        } else {
            delegate?.homeHoldProgress(held)
        }
    }

    private func homeReleased() {
        holdTimer?.invalidate()
        holdTimer = nil
        if homeDown != nil && !holdCancelled { delegate?.homeHoldCancelled() }
        homeDown = nil
        holdCancelled = false
    }

    /// Any other button while holding the home button cancels the exit countdown.
    private func otherButton() {
        guard homeDown != nil, !holdCancelled else { return }
        holdCancelled = true
        delegate?.homeHoldCancelled()
    }

    // MARK: GameController (Y, View, which pad)

    private func startGameController() {
        GCController.shouldMonitorBackgroundEvents = true
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            guard let c = n.object as? GCController else { return }
            MainActor.assumeIsolated { self?.attach(c) }
        }
        GCController.controllers().forEach(attach)
    }

    private func attach(_ c: GCController) {
        if let s = ControllerStyle.from(category: c.productCategory) { style = s }
        log("gc: \(c.vendorName ?? "?") [\(c.productCategory)]")
        guard let pad = c.extendedGamepad else { return }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { if self?.homeDown != nil { self?.fire(.stats) } }
        }
        pad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { if self?.homeDown != nil { self?.fire(.screenshot) } }
        }
    }

    /// De-duplicates combos that can arrive twice (HID + GameController).
    private func fire(_ c: Combo) {
        let now = Date()
        if let last = lastCombo[c], now.timeIntervalSince(last) < 0.25 { return }
        lastCombo[c] = now
        delegate?.combo(c)
    }
}
