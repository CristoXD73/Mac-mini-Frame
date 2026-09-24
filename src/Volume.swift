import AudioToolbox
import CoreAudio

// System output volume through Core Audio: instant (no AppleScript process per press), same
// 16-step scale as the keyboard volume keys.

enum Volume {
    static let steps: Float = 16

    private static func device() -> AudioDeviceID? { Audio.defaultOutput() }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    /// nil when the current output has no volume control (e.g. HDMI / DisplayPort audio).
    static func level() -> Float? {
        guard let dev = device() else { return nil }
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(dev, &a) else { return nil }
        var v = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func isMuted() -> Bool {
        guard let dev = device() else { return false }
        var a = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(dev, &a) else { return false }
        var m = UInt32(0), size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &m) == noErr && m != 0
    }

    private static func setMuted(_ muted: Bool) {
        guard let dev = device() else { return }
        var a = address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(dev, &a), AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue else { return }
        var m = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }

    /// Move one step (±1/16), snapping to the step grid like the volume keys. Returns the new level,
    /// or nil if this output can't be controlled.
    @discardableResult
    static func step(_ direction: Int) -> Float? {
        guard let dev = device(), let current = level() else { return nil }
        var a = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue else { return nil }
        let snapped = (current * steps).rounded() / steps
        var next = min(1, max(0, snapped + Float(direction) / steps))
        if direction > 0 && isMuted() { setMuted(false) }
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &next)
        if next == 0 { setMuted(true) } else if isMuted() { setMuted(false) }
        return next
    }
}
