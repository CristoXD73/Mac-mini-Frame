import AppKit
import IOKit

/// A floating panel above everything (including full-screen games) that never
/// takes focus or clicks.
@MainActor
private func overlayWindow(_ rect: NSRect) -> NSWindow {
    let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = .screenSaver
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    w.backgroundColor = .clear
    w.isOpaque = false
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.isReleasedWhenClosed = false
    return w
}

@MainActor
private func pill(_ label: NSTextField) -> NSView {
    let v = NSVisualEffectView()
    v.material = .hudWindow
    v.state = .active
    v.blendingMode = .behindWindow
    v.wantsLayer = true
    v.layer?.cornerRadius = 14
    v.layer?.masksToBounds = true
    label.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(label)
    NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 22),
        label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -22),
        label.topAnchor.constraint(equalTo: v.topAnchor, constant: 12),
        label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -12),
    ])
    return v
}

// MARK: - Toast

/// Short notice at the top of the main display (countdown, volume, screenshot).
@MainActor
final class Toast {
    private var window: NSWindow?
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, for seconds: Double = 1.6) {
        guard let screen = NSScreen.screens.first else { return }
        if window == nil {
            window = overlayWindow(.zero)
            label.font = .systemFont(ofSize: 22, weight: .semibold)
            label.textColor = .white
            label.alignment = .center
            window?.contentView = pill(label)
        }
        label.stringValue = text
        let size = window!.contentView!.fittingSize
        let f = screen.frame
        window!.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - 70,
                                width: size.width, height: size.height), display: true)
        window!.alphaValue = 1
        window!.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        window?.orderOut(nil)
    }

    /// White flash over the main display (screenshot feedback).
    static func flash() {
        guard let screen = NSScreen.screens.first else { return }
        let w = overlayWindow(screen.frame)
        w.setFrame(screen.frame, display: false)
        w.backgroundColor = .white
        w.alphaValue = 0.8
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            w.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { w.orderOut(nil) } })
    }
}

// MARK: - Stats overlay

/// CPU / GPU / RAM / clock in the top-right corner of the main display.
@MainActor
final class StatsOverlay {
    private var window: NSWindow?
    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var lastCPU: [(busy: UInt64, total: UInt64)] = []

    var isShown: Bool { window?.isVisible == true }

    func toggle() { isShown ? hide() : show() }

    func show() {
        if window == nil {
            window = overlayWindow(.zero)
            label.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
            label.textColor = .white
            window?.contentView = pill(label)
        }
        _ = cpuUsage()  // prime the delta
        update()
        window?.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
    }

    private func update() {
        guard let window, let screen = NSScreen.screens.first else { return }
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let gpu = gpuUsage().map { "\($0)%" } ?? "–"
        let (used, total) = memory()
        label.stringValue = String(format: "CPU %3.0f%%   GPU %@   RAM %.1f/%.0f GB   %@",
                                   cpuUsage(), gpu, used, total, time)
        let size = window.contentView!.fittingSize
        let f = screen.frame
        window.setFrame(NSRect(x: f.maxX - size.width - 24, y: f.maxY - size.height - 24,
                               width: size.width, height: size.height), display: true)
    }

    /// Whole-machine CPU % since the previous call (host_processor_info).
    private func cpuUsage() -> Double {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var now: [(UInt64, UInt64)] = []
        for i in 0..<Int(count) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            now.append((user + sys + nice, user + sys + nice + idle))
        }
        defer { lastCPU = now.map { (busy: $0.0, total: $0.1) } }
        guard lastCPU.count == now.count else { return 0 }
        var busy: UInt64 = 0, total: UInt64 = 0
        for (a, b) in zip(lastCPU, now) {
            busy &+= b.0 &- a.busy
            total &+= b.1 &- a.total
        }
        return total == 0 ? 0 : Double(busy) / Double(total) * 100
    }

    /// GPU utilization from IORegistry: IOAccelerator -> PerformanceStatistics.
    private func gpuUsage() -> Int? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Int?
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let util = stats["Device Utilization %"] as? Int {
                best = max(best ?? 0, util)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return best
    }

    /// (used GB, total GB) via host_statistics64: active + wired + compressed.
    private func memory() -> (Double, Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return (0, total) }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return (Double(pages) * Double(pageSize) / 1_073_741_824, total)
    }
}
