import Cocoa
import SwiftUI

// On-screen feedback in the style of macOS's own HUDs: frosted glass that samples what's behind it.
//   • Volume:  glass pill, top-right, speaker icon + smoothly animating bar (no numbers, like macOS)
//   • Hold:    glass circle in the middle whose ring fills while the Xbox button is held
//   • Message: glass pill, top-center, icon + short text (screenshot, suspended, force quit …)
// The window only exists while something is showing, so it costs nothing during gameplay.

/// Frosted glass. `previewFill` stands in for it when rendering preview images (the image renderer
/// can't capture a live NSVisualEffectView).
struct Glass: View {
    nonisolated(unsafe) static var previewFill = false
    var body: some View {
        if Glass.previewFill { Color(white: 0.16).opacity(0.72) } else { GlassEffect() }
    }
}

struct GlassEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var volume: Float?             // 0...1 while the volume pill is showing
    @Published var volumeUnsupported = false
    @Published var muted = false
    @Published var hold: Double?              // 0...1 while the exit ring is showing
    @Published var holdDone = false
    @Published var message: (icon: String, text: String)?
    var isEmpty: Bool { volume == nil && !volumeUnsupported && hold == nil && message == nil }
}

struct HUDView: View {
    @ObservedObject var m: HUDModel

    var body: some View {
        ZStack {
            // Volume: top-right
            VStack {
                HStack {
                    Spacer()
                    if m.volume != nil || m.volumeUnsupported { volumePill.transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing))) }
                }
                Spacer()
            }
            .padding(.top, 28).padding(.trailing, 28)

            // Message: top-center
            VStack {
                if let msg = m.message { messagePill(msg.icon, msg.text).transition(.opacity.combined(with: .move(edge: .top))) }
                Spacer()
            }
            .padding(.top, 36)

            // Exit ring: center
            if let p = m.hold { holdRing(p).transition(.opacity.combined(with: .scale(scale: 0.85))) }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: m.volume)
        .animation(.easeOut(duration: 0.22), value: m.volumeUnsupported)
        .animation(.easeOut(duration: 0.25), value: m.hold == nil)
        .animation(.easeOut(duration: 0.25), value: m.message?.text)
        .animation(.easeInOut(duration: 0.2), value: m.holdDone)
    }

    var volumeIcon: String {
        guard let v = m.volume, !m.muted, v > 0 else { return "speaker.slash.fill" }
        return v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    var volumePill: some View {
        HStack(spacing: 14) {
            Image(systemName: m.volumeUnsupported ? "speaker.slash.fill" : volumeIcon)
                .font(.system(size: 17, weight: .semibold)).frame(width: 26)
                .contentTransition(.symbolEffect(.replace))
            if m.volumeUnsupported {
                Text("This output has no volume control").font(.system(size: 14, weight: .medium))
            } else {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(.white).frame(width: max(0, g.size.width * CGFloat(m.muted ? 0 : (m.volume ?? 0))))
                    }
                }
                .frame(width: 190, height: 7)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20).frame(height: 52)
        .background(Glass().clipShape(Capsule()))
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }

    func messagePill(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
            Text(text).font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).frame(height: 50)
        .background(Glass().clipShape(Capsule()))
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }

    func holdRing(_ p: Double) -> some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(.clear).background(Glass().clipShape(Circle()))
                Circle().stroke(.white.opacity(0.16), lineWidth: 7).padding(14)
                Circle().trim(from: 0, to: p)
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(14)
                    .shadow(color: Color(red: 0.55, green: 0.72, blue: 1).opacity(0.7), radius: 8)
                Image(systemName: m.holdDone ? "checkmark" : "desktopcomputer")
                    .font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 168, height: 168)
            .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)

            Text(m.holdDone ? "Returning to PC" : "Keep holding to return to PC")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 22).frame(height: 44)
                .background(Glass().clipShape(Capsule()))
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.8))
        }
    }
}

@MainActor
final class HUD {
    let model = HUDModel()
    private var window: NSWindow?
    private var volumeHide: DispatchWorkItem?
    private var messageHide: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?

    private func ensureWindow() {
        closeWork?.cancel()
        guard window == nil, let screen = NSScreen.screens.first else { return }
        let w = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
        w.level = .screenSaver
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.contentView = NSHostingView(rootView: HUDView(m: model))
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w
    }

    /// Close the window once everything has faded out.
    private func closeIfEmpty() {
        guard model.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.isEmpty else { return }
            self.window?.orderOut(nil); self.window = nil
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func volume(_ level: Float?) {
        ensureWindow()
        if let level { model.volumeUnsupported = false; model.muted = Volume.isMuted(); model.volume = level }
        else { model.volume = nil; model.volumeUnsupported = true }
        volumeHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.model.volume = nil; self?.model.volumeUnsupported = false; self?.closeIfEmpty()
        }
        volumeHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    func message(_ icon: String, _ text: String, for seconds: TimeInterval = 2) {
        ensureWindow()
        model.message = (icon, text)
        messageHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.model.message = nil; self?.closeIfEmpty() }
        messageHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hold(_ progress: Double) {
        ensureWindow()
        model.holdDone = false
        model.hold = min(1, progress)
    }

    func holdDone() {
        ensureWindow()
        model.hold = 1
        model.holdDone = true
    }

    func holdCancel() {
        guard model.hold != nil, !model.holdDone else { return }
        model.hold = nil
        closeIfEmpty()
    }

    func hideAll() {
        volumeHide?.cancel(); messageHide?.cancel()
        model.volume = nil; model.volumeUnsupported = false; model.hold = nil; model.holdDone = false; model.message = nil
        closeIfEmpty()
    }
}
