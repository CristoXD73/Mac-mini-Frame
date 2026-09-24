import Cocoa
import IOKit

// Small panels drawn above everything on the main display, including full-screen games:
// the hold-to-exit countdown, volume/screenshot notices, and the performance overlay.

@MainActor
func makePanel(size: NSSize, at origin: (NSRect, NSSize) -> NSPoint) -> (NSWindow, NSTextField) {
    let screen = NSScreen.screens.first!
    let w = NSWindow(contentRect: NSRect(origin: origin(screen.frame, size), size: size), styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
    w.level = .screenSaver
    w.isOpaque = false
    w.backgroundColor = .clear
    w.ignoresMouseEvents = true
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    let box = NSView(frame: NSRect(origin: .zero, size: size))
    box.wantsLayer = true
    box.layer?.backgroundColor = NSColor(red: 0.04, green: 0.08, blue: 0.2, alpha: 0.92).cgColor
    box.layer?.cornerRadius = 18
    box.layer?.borderColor = NSColor(red: 0.45, green: 0.62, blue: 1, alpha: 0.35).cgColor
    box.layer?.borderWidth = 1
    let label = NSTextField(labelWithString: "")
    label.textColor = .white
    label.maximumNumberOfLines = 0
    label.frame = box.bounds.insetBy(dx: 18, dy: 12)
    box.addSubview(label)
    w.contentView = box
    return (w, label)
}

/// CPU / GPU / memory panel in the top-right corner, toggled with Home + Y.
@MainActor
final class StatsOverlay {
    private let window: NSWindow
    private let label: NSTextField
    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?

    init() {
        (window, label) = makePanel(size: NSSize(width: 290, height: 142)) { f, s in
            NSPoint(x: f.maxX - s.width - 30, y: f.maxY - s.height - 30)
        }
        label.font = .monospacedSystemFont(ofSize: 17, weight: .medium)
    }

    var isShowing: Bool { window.isVisible }

    func toggle() { isShowing ? hide() : show() }

    func show() {
        update()
        window.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
    }

    func hide() { timer?.invalidate(); timer = nil; window.orderOut(nil) }

    private func update() {
        let cpu = cpuPercent().map { String(format: "%3.0f%%", $0) } ?? "  –"
        let gpu = gpuPercent().map { String(format: "%3.0f%%", $0) } ?? "  –"
        let mem = String(format: "%.1f / %.0f GB", memoryUsedGB(), Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824)
        let games = freeGB(gamesDrive).map { String(format: "%.0f GB free", $0) } ?? "not connected"
        label.stringValue = "CPU   \(cpu)\nGPU   \(gpu)\nRAM   \(mem)\nGAMES \(games)\n\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
    }

    private func cpuPercent() -> Double? {
        var count: natural_t = 0, info: processor_info_array_t?, infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(count) {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(info[base + Int(CPU_STATE_USER)]), sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)]), idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            busy += user + sys + nice; total += user + sys + nice + idle
        }
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return nil }
        return 100 * Double(busy - last.busy) / Double(total - last.total)
    }

    private func gpuPercent() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let util = stats["Device Utilization %"] as? Int {
                return Double(util)
            }
        }
        return nil
    }

    private func memoryUsedGB() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard ok == KERN_SUCCESS else { return 0 }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return Double(pages * UInt64(vm_kernel_page_size)) / 1_073_741_824
    }
}
