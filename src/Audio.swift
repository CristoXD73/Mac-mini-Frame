import CoreAudio
import Foundation

// Optional: switch the default audio output to a gaming device (TV, headset) in game mode and
// switch back afterwards. Configured with "gamingAudioOutput" in config.json (a substring of the
// device name). Does nothing if unset or if the device isn't connected.

enum Audio {
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultOutput() -> AudioDeviceID? {
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr ? id : nil
    }

    static func setDefaultOutput(_ id: AudioDeviceID) {
        var dev = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var a = address(sel)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, size, &dev)
        }
    }

    /// Output-capable devices by name.
    static func outputs() -> [(id: AudioDeviceID, name: String)] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var sSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &sSize) == noErr, sSize > 0 else { return nil }
            var nameAddr = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nSize, &name) == noErr, let n = name?.takeRetainedValue() else { return nil }
            return (id, n as String)
        }
    }
}

final class AudioRouting {
    private var previous: AudioDeviceID?

    func enterGameMode(preferred: String?) {
        guard let preferred, !preferred.isEmpty,
              let target = Audio.outputs().first(where: { $0.name.localizedCaseInsensitiveContains(preferred) }),
              let current = Audio.defaultOutput(), current != target.id else { return }
        previous = current
        Audio.setDefaultOutput(target.id)
        log("audio: switched output to \(target.name)")
    }

    func leaveGameMode() {
        guard let prev = previous else { return }
        previous = nil
        if Audio.outputs().contains(where: { $0.id == prev }) { Audio.setDefaultOutput(prev); log("audio: restored previous output") }
    }
}
