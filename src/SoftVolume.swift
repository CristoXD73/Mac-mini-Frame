import AudioToolbox
import CoreAudio
import Foundation

// Software volume for outputs macOS can't change: a TV or monitor over HDMI or DisplayPort has no
// volume control of its own (the Sound slider is greyed out), so Xbox + D-pad would do nothing.
//
// How: a Core Audio process tap captures everything the Mac plays and mutes it at the source,
// then a private aggregate device plays it back to the same output at the chosen level. Only runs
// in game mode, only while the current output has no hardware volume, and is torn down on exit
// (or automatically by macOS if Console Mode quits). Needs "System Audio Recording" permission.

final class SoftVolume: @unchecked Sendable {
    static let shared = SoftVolume()

    /// 0...1 in Apple's 16 steps; remembered between sessions.
    private(set) var level: Float
    private var gain: Float = 1          // read on the audio thread
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private(set) var outputUID: String?
    private let ioQueue = DispatchQueue(label: "local.consolemode.softvolume", qos: .userInteractive)
    var isActive: Bool { proc != nil }

    // Self-test counters (audio thread writes, main thread reads)
    private(set) var callbacks = 0
    private(set) var peakIn: Float = 0
    private(set) var peakOut: Float = 0
    private(set) var lastStartError: OSStatus = 0

    private init() {
        let saved = UserDefaults.standard.object(forKey: "softVolumeLevel") as? Float
        level = saved ?? 1
        gain = Self.curve(level)
    }

    /// Perceptual curve, so each of the 16 steps sounds about equally big.
    private static func curve(_ l: Float) -> Float { l <= 0 ? 0 : pow(l, 2.2) }

    /// Change the level by one step (starting the tap if needed). nil = couldn't start.
    func step(_ direction: Int) -> Float? {
        guard ensureRunning() else { return nil }
        level = max(0, min(1, (level * Volume.steps + Float(direction)).rounded() / Volume.steps))
        gain = Self.curve(level)
        UserDefaults.standard.set(level, forKey: "softVolumeLevel")
        return level
    }

    /// Set the level directly (tests), without saving it.
    func setForTest(_ l: Float) { level = l; gain = Self.curve(l); peakIn = 0; peakOut = 0 }

    /// Start (or restart, if the output changed) routing through the tap.
    @discardableResult
    func ensureRunning() -> Bool {
        guard let out = Audio.defaultOutput(), let uid = Self.uid(out) else { return false }
        if isActive, uid == outputUID { return true }
        stop()
        do { try start(outputUID: uid); return true } catch {
            log("soft volume: could not start (\(error))"); stop(); return false
        }
    }

    private struct Failure: Error, CustomStringConvertible { let description: String }

    private func start(outputUID uid: String) throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "Console Mode volume"
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var err = AudioHardwareCreateProcessTap(desc, &tapID)
        guard err == noErr else { throw Failure(description: "process tap error \(err)") }
        tap = tapID

        let aggUID = "local.consolemode.softvolume.\(UUID().uuidString)"
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Console Mode Volume",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var aggID = AudioObjectID(kAudioObjectUnknown)
        err = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard err == noErr else { throw Failure(description: "aggregate device error \(err)") }
        aggregate = aggID

        callbacks = 0; peakIn = 0; peakOut = 0
        var procID: AudioDeviceIOProcID?
        err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, ioQueue) { [unowned self] _, input, _, output, _ in
            let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outs = UnsafeMutableAudioBufferListPointer(output)
            let g = self.gain
            var peak: Float = 0, peakO: Float = 0
            for (i, o) in outs.enumerated() {
                guard let dst = o.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let n = Int(o.mDataByteSize) / MemoryLayout<Float>.size
                guard ins.count > 0, let src = ins[i % ins.count].mData?.assumingMemoryBound(to: Float.self) else {
                    dst.update(repeating: 0, count: n); continue
                }
                let m = min(n, Int(ins[i % ins.count].mDataByteSize) / MemoryLayout<Float>.size)
                for k in 0..<m { let v = src[k]; peak = max(peak, abs(v)); dst[k] = v * g; peakO = max(peakO, abs(dst[k])) }
                if m < n { (dst + m).update(repeating: 0, count: n - m) }
            }
            self.callbacks += 1
            if peak > self.peakIn { self.peakIn = peak }
            if peakO > self.peakOut { self.peakOut = peakO }
        }
        guard err == noErr, let procID else { throw Failure(description: "IOProc error \(err)") }
        proc = procID
        err = AudioDeviceStart(aggID, procID)
        lastStartError = err
        guard err == noErr else { throw Failure(description: "start error \(err)") }
        outputUID = uid
        log("soft volume: on for \(uid) at \(Int(level * 100))%")
    }

    func stop() {
        if let p = proc {
            AudioDeviceStop(aggregate, p)
            AudioDeviceDestroyIOProcID(aggregate, p)
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        if proc != nil { log("soft volume: off") }
        proc = nil; aggregate = AudioObjectID(kAudioObjectUnknown); tap = AudioObjectID(kAudioObjectUnknown); outputUID = nil
    }

    /// Diagnostics for the self-test.
    func diagnostics() -> [String: Any] {
        func u32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Int {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            var v: UInt32 = 0; var size = UInt32(4)
            return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr ? Int(v) : -1
        }
        func count(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr ? Int(size) / MemoryLayout<AudioStreamID>.size : -1
        }
        func rate(_ id: AudioObjectID) -> Double {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var v: Float64 = 0; var size = UInt32(8)
            return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr ? v : -1
        }
        var d: [String: Any] = ["active": isActive, "callbacks": callbacks, "peakIn": Double(peakIn), "peakOut": Double(peakOut), "gain": Double(gain), "startError": Int(lastStartError)]
        if aggregate != kAudioObjectUnknown {
            d["aggRunning"] = u32(aggregate, kAudioDevicePropertyDeviceIsRunning)
            d["aggRunningSomewhere"] = u32(aggregate, kAudioDevicePropertyDeviceIsRunningSomewhere)
            d["aggInStreams"] = count(aggregate, kAudioObjectPropertyScopeInput)
            d["aggOutStreams"] = count(aggregate, kAudioObjectPropertyScopeOutput)
            d["aggRate"] = rate(aggregate)
        }
        if let out = Audio.defaultOutput() { d["outRate"] = rate(out); d["outRunningSomewhere"] = u32(out, kAudioDevicePropertyDeviceIsRunningSomewhere); d["outOutStreams"] = count(out, kAudioObjectPropertyScopeOutput) }
        return d
    }

    static func uid(_ device: AudioDeviceID) -> String? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &s) == noErr, let v = s?.takeRetainedValue() else { return nil }
        return v as String
    }
}
