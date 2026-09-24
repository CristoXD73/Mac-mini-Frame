import AppKit
import SwiftUI

// MARK: - Controller outlines (400 x 260 design box)

enum ControllerShape {
    static let box = CGSize(width: 400, height: 260)

    static func outline(_ style: ControllerStyle) -> Path {
        switch style {
        case .xbox: return xbox()
        case .playstation: return playstation()
        case .steam: return steam()
        }
    }

    /// Rounded body with two grips; drawn as one continuous stroke clockwise
    /// from the top middle so the draw-in animation reads naturally.
    private static func xbox() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 200, y: 38))
        p.addCurve(to: CGPoint(x: 318, y: 42), control1: CGPoint(x: 250, y: 38), control2: CGPoint(x: 290, y: 30))
        p.addCurve(to: CGPoint(x: 372, y: 120), control1: CGPoint(x: 350, y: 56), control2: CGPoint(x: 364, y: 88))
        p.addCurve(to: CGPoint(x: 382, y: 222), control1: CGPoint(x: 382, y: 158), control2: CGPoint(x: 394, y: 204))
        p.addCurve(to: CGPoint(x: 322, y: 214), control1: CGPoint(x: 370, y: 244), control2: CGPoint(x: 338, y: 240))
        p.addCurve(to: CGPoint(x: 270, y: 176), control1: CGPoint(x: 306, y: 190), control2: CGPoint(x: 292, y: 176))
        p.addLine(to: CGPoint(x: 130, y: 176))
        p.addCurve(to: CGPoint(x: 78, y: 214), control1: CGPoint(x: 108, y: 176), control2: CGPoint(x: 94, y: 190))
        p.addCurve(to: CGPoint(x: 18, y: 222), control1: CGPoint(x: 62, y: 240), control2: CGPoint(x: 30, y: 244))
        p.addCurve(to: CGPoint(x: 28, y: 120), control1: CGPoint(x: 6, y: 204), control2: CGPoint(x: 18, y: 158))
        p.addCurve(to: CGPoint(x: 82, y: 42), control1: CGPoint(x: 36, y: 88), control2: CGPoint(x: 50, y: 56))
        p.addCurve(to: CGPoint(x: 200, y: 38), control1: CGPoint(x: 110, y: 30), control2: CGPoint(x: 150, y: 38))
        p.closeSubpath()
        return p
    }

    private static func playstation() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 200, y: 44))
        p.addLine(to: CGPoint(x: 300, y: 44))
        p.addCurve(to: CGPoint(x: 360, y: 90), control1: CGPoint(x: 334, y: 44), control2: CGPoint(x: 352, y: 62))
        p.addCurve(to: CGPoint(x: 388, y: 214), control1: CGPoint(x: 374, y: 130), control2: CGPoint(x: 396, y: 184))
        p.addCurve(to: CGPoint(x: 330, y: 226), control1: CGPoint(x: 380, y: 244), control2: CGPoint(x: 346, y: 246))
        p.addCurve(to: CGPoint(x: 276, y: 170), control1: CGPoint(x: 310, y: 204), control2: CGPoint(x: 296, y: 170))
        p.addLine(to: CGPoint(x: 124, y: 170))
        p.addCurve(to: CGPoint(x: 70, y: 226), control1: CGPoint(x: 104, y: 170), control2: CGPoint(x: 90, y: 204))
        p.addCurve(to: CGPoint(x: 12, y: 214), control1: CGPoint(x: 54, y: 246), control2: CGPoint(x: 20, y: 244))
        p.addCurve(to: CGPoint(x: 40, y: 90), control1: CGPoint(x: 4, y: 184), control2: CGPoint(x: 26, y: 130))
        p.addCurve(to: CGPoint(x: 100, y: 44), control1: CGPoint(x: 48, y: 62), control2: CGPoint(x: 66, y: 44))
        p.addLine(to: CGPoint(x: 200, y: 44))
        p.closeSubpath()
        return p
    }

    /// Steam Controller: wide body, flat top, two short grips.
    private static func steam() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 200, y: 40))
        p.addLine(to: CGPoint(x: 312, y: 40))
        p.addCurve(to: CGPoint(x: 384, y: 100), control1: CGPoint(x: 352, y: 40), control2: CGPoint(x: 380, y: 64))
        p.addCurve(to: CGPoint(x: 376, y: 226), control1: CGPoint(x: 390, y: 150), control2: CGPoint(x: 394, y: 204))
        p.addCurve(to: CGPoint(x: 318, y: 222), control1: CGPoint(x: 362, y: 244), control2: CGPoint(x: 332, y: 242))
        p.addCurve(to: CGPoint(x: 260, y: 184), control1: CGPoint(x: 302, y: 198), control2: CGPoint(x: 284, y: 184))
        p.addLine(to: CGPoint(x: 140, y: 184))
        p.addCurve(to: CGPoint(x: 82, y: 222), control1: CGPoint(x: 116, y: 184), control2: CGPoint(x: 98, y: 198))
        p.addCurve(to: CGPoint(x: 24, y: 226), control1: CGPoint(x: 68, y: 242), control2: CGPoint(x: 38, y: 244))
        p.addCurve(to: CGPoint(x: 16, y: 100), control1: CGPoint(x: 6, y: 204), control2: CGPoint(x: 10, y: 150))
        p.addCurve(to: CGPoint(x: 88, y: 40), control1: CGPoint(x: 20, y: 64), control2: CGPoint(x: 48, y: 40))
        p.addLine(to: CGPoint(x: 200, y: 40))
        p.closeSubpath()
        return p
    }

    /// Detail that fades in at 2.4 s: guide circle, or touchpad + PS dot, or
    /// the Steam controller's two trackpads.
    static func detail(_ style: ControllerStyle) -> Path {
        var p = Path()
        switch style {
        case .xbox:
            p.addEllipse(in: CGRect(x: 182, y: 62, width: 36, height: 36))
        case .playstation:
            p.addRoundedRect(in: CGRect(x: 150, y: 56, width: 100, height: 56), cornerSize: CGSize(width: 10, height: 10))
            p.addEllipse(in: CGRect(x: 193, y: 128, width: 14, height: 14))
        case .steam:
            p.addEllipse(in: CGRect(x: 60, y: 70, width: 70, height: 70))
            p.addEllipse(in: CGRect(x: 270, y: 70, width: 70, height: 70))
            p.addEllipse(in: CGRect(x: 188, y: 62, width: 24, height: 24))
        }
        return p
    }
}

// MARK: - Starfield renderer

struct Star {
    var angle: Double
    var radius: Double       // final distance from center, 0...1 of the half-diagonal
    var size: Double
    var brightness: Double
    var phase: Double
    var speed: Double
    var tint: Int            // 0 white, 1 cyan, 2 violet
}

/// Deterministic PRNG so every display (and every preview) shows the same sky.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum Starfield {
    static let stars: [Star] = {
        var rng = SplitMix64(state: 0xC0FFEE)
        return (0..<300).map { _ in
            let roll = Double.random(in: 0..<1, using: &rng)
            return Star(angle: .random(in: 0..<(2 * .pi), using: &rng),
                        radius: sqrt(Double.random(in: 0.02..<1, using: &rng)),
                        size: .random(in: 0.6..<2.2, using: &rng),
                        brightness: .random(in: 0.35..<1, using: &rng),
                        phase: .random(in: 0..<(2 * .pi), using: &rng),
                        speed: .random(in: 0.6..<2.2, using: &rng),
                        tint: roll < 0.10 ? 1 : (roll < 0.17 ? 2 : 0))
        }
    }()

    static let bgTop = Color(red: 0.008, green: 0.016, blue: 0.05)
    static let bgBottom = Color(red: 0.02, green: 0.045, blue: 0.12)
    static let glow = Color(red: 0.05, green: 0.12, blue: 0.30)
    static let outlineColor = Color(red: 0.55, green: 0.85, blue: 1.0)

    static func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 3) }

    static func tintColor(_ t: Int) -> Color {
        switch t {
        case 1: return Color(red: 0.55, green: 0.95, blue: 1.0)
        case 2: return Color(red: 0.78, green: 0.62, blue: 1.0)
        default: return .white
        }
    }

    /// Draws one frame at time `t` seconds since the takeover appeared.
    static func draw(_ g: inout GraphicsContext, size: CGSize, t: Double, style: ControllerStyle) {
        let rect = CGRect(origin: .zero, size: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let halfDiag = hypot(size.width, size.height) / 2

        // Background + centered glow.
        g.fill(Path(rect), with: .linearGradient(Gradient(colors: [bgTop, bgBottom]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        g.fill(Path(rect), with: .radialGradient(Gradient(colors: [glow.opacity(0.55), glow.opacity(0)]),
                                                 center: center, startRadius: 0, endRadius: halfDiag * 0.7))

        // Nebula clouds drifting on slow loops.
        for (i, color) in [Color(red: 0.45, green: 0.2, blue: 0.75), Color(red: 0.1, green: 0.55, blue: 0.6)].enumerated() {
            let a = t / (37 + Double(i) * 11) * 2 * .pi + Double(i) * 2.1
            let c = CGPoint(x: center.x + cos(a) * size.width * 0.28, y: center.y + sin(a * 0.8) * size.height * 0.22)
            let r = min(size.width, size.height) * 0.45
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(colors: [color.opacity(0.16), color.opacity(0)]),
                                         center: c, startRadius: 0, endRadius: r))
        }

        // Controller placement (used by stars for the pulse flare).
        let scale = min(size.width * 0.38 / ControllerShape.box.width, size.height * 0.42 / ControllerShape.box.height)
        let origin = CGPoint(x: center.x - ControllerShape.box.width * scale / 2,
                             y: center.y - ControllerShape.box.height * scale / 2)
        let pulseRadius: Double? = {
            guard t >= 3 else { return nil }
            let local = (t - 3).truncatingRemainder(dividingBy: 6)
            return local < 2.5 ? local / 2.5 * halfDiag * 0.9 : nil
        }()

        // Stars.
        let hyper = 1.4
        for s in stars {
            let dir = CGPoint(x: cos(s.angle), y: sin(s.angle))
            let finalR = s.radius * halfDiag
            let color = tintColor(s.tint)
            if t < hyper {
                // Hyperspace: streak outward from the center.
                let k = easeOutCubic(t / hyper)
                let r1 = finalR * k, r0 = max(0, r1 - (1 - k) * halfDiag * 0.35 - 2)
                var streak = Path()
                streak.move(to: CGPoint(x: center.x + dir.x * r0, y: center.y + dir.y * r0))
                streak.addLine(to: CGPoint(x: center.x + dir.x * r1, y: center.y + dir.y * r1))
                g.stroke(streak, with: .color(color.opacity(s.brightness)), lineWidth: s.size)
                continue
            }
            let tt = t - hyper
            let drift = CGPoint(x: sin(tt * 0.05 + s.phase) * 6, y: cos(tt * 0.04 + s.phase) * 4)
            let p = CGPoint(x: center.x + dir.x * finalR + drift.x, y: center.y + dir.y * finalR + drift.y)
            var alpha = s.brightness * (0.6 + 0.4 * sin(tt * s.speed + s.phase))
            var sz = s.size
            if let pr = pulseRadius, abs(hypot(p.x - center.x, p.y - center.y) - pr) < 60 {
                alpha = min(1, alpha + 0.6)
                sz *= 1.8
            }
            g.fill(Path(ellipseIn: CGRect(x: p.x - sz / 2, y: p.y - sz / 2, width: sz, height: sz)),
                   with: .color(color.opacity(alpha)))
            if s.brightness > 0.85 {  // cross glint
                var glint = Path()
                let l = sz * 3.5 * alpha
                glint.move(to: CGPoint(x: p.x - l, y: p.y)); glint.addLine(to: CGPoint(x: p.x + l, y: p.y))
                glint.move(to: CGPoint(x: p.x, y: p.y - l)); glint.addLine(to: CGPoint(x: p.x, y: p.y + l))
                g.stroke(glint, with: .color(color.opacity(alpha * 0.5)), lineWidth: 0.6)
            }
        }

        // Shooting star every 3.5 s from 2.5 s, heading down-left.
        if t >= 2.5 {
            let n = floor((t - 2.5) / 3.5)
            let local = (t - 2.5) - n * 3.5
            if local < 0.9 {
                var rng = SplitMix64(state: UInt64(n) &+ 77)
                let start = CGPoint(x: size.width * .random(in: 0.45..<0.95, using: &rng),
                                    y: size.height * .random(in: 0.05..<0.4, using: &rng))
                let travel = CGPoint(x: -size.width * 0.35, y: size.height * 0.28)
                let k = local / 0.9
                let head = CGPoint(x: start.x + travel.x * k, y: start.y + travel.y * k)
                let tail = CGPoint(x: head.x - travel.x * 0.25, y: head.y - travel.y * 0.25)
                var line = Path(); line.move(to: tail); line.addLine(to: head)
                g.stroke(line, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.9 * (1 - k))]),
                                                     startPoint: tail, endPoint: head), lineWidth: 1.6)
            }
        }

        // Pulse ring from the controller.
        if let pr = pulseRadius {
            let fade = 1 - pr / (halfDiag * 0.9)
            g.stroke(Path(ellipseIn: CGRect(x: center.x - pr, y: center.y - pr, width: 2 * pr, height: 2 * pr)),
                     with: .color(outlineColor.opacity(0.35 * fade)), lineWidth: 2)
        }

        // Controller outline drawing itself in (0.9 - 2.5 s), then breathing.
        let progress = easeOutCubic((t - 0.9) / 1.6)
        if progress > 0 {
            let transform = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
            let shape = ControllerShape.outline(style).applying(transform)
            let drawn = progress < 1 ? shape.trimmedPath(from: 0, to: progress) : shape
            let breathe = t > 2.5 ? 0.5 + 0.5 * sin((t - 2.5) * 1.3) : 1
            g.stroke(drawn, with: .color(outlineColor.opacity(0.12 + 0.10 * breathe)),
                     style: StrokeStyle(lineWidth: 14 + 6 * breathe, lineCap: .round, lineJoin: .round))
            g.stroke(drawn, with: .color(outlineColor.opacity(0.3)),
                     style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            g.stroke(drawn, with: .color(.white.opacity(0.95)),
                     style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            if progress < 1, let tip = drawn.currentPoint {  // bright spark on the tip
                let r = 7.0
                g.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: 2 * r, height: 2 * r)),
                       with: .radialGradient(Gradient(colors: [.white, outlineColor.opacity(0)]),
                                             center: tip, startRadius: 0, endRadius: r))
            }
            let detailAlpha = min(max((t - 2.4) / 0.6, 0), 1)
            if detailAlpha > 0 {
                g.stroke(ControllerShape.detail(style).applying(transform),
                         with: .color(.white.opacity(0.85 * detailAlpha)), lineWidth: 1.8)
            }
        }
    }
}

struct TakeoverView: View {
    let style: ControllerStyle
    let start: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            Canvas { g, size in
                Starfield.draw(&g, size: size, t: ctx.date.timeIntervalSince(start), style: style)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Windows

/// Starfield on every display EXCEPT the main (play) one. Never switches a
/// display off: monitors may power other devices over USB-C.
@MainActor
final class Takeover {
    private var windows: [NSWindow] = []
    private var style: ControllerStyle = .xbox
    private var start = Date()
    private var observer: NSObjectProtocol?

    var isShown: Bool { !windows.isEmpty }

    func show(style: ControllerStyle) {
        self.style = style
        start = Date()
        rebuild()
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { if self?.isShown == true { self?.rebuild() } }
            }
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        for screen in NSScreen.screens.dropFirst() {  // screens[0] is the main (menu bar) display
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.backgroundColor = .black
            w.isOpaque = true
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: TakeoverView(style: style, start: start))
            w.orderFrontRegardless()
            windows.append(w)
        }
        log("takeover: \(windows.count) display(s)")
    }
}

/// Plain black cover on the main display while Steam starts.
@MainActor
final class LoadingCover {
    private var window: NSWindow?
    private var label: NSTextField?

    func show(_ text: String) {
        guard let screen = NSScreen.screens.first else { return }
        if window == nil {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.backgroundColor = .black
            w.isOpaque = true
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 26, weight: .medium)
            l.textColor = NSColor(white: 0.75, alpha: 1)
            l.translatesAutoresizingMaskIntoConstraints = false
            let v = NSView()
            v.addSubview(l)
            NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: v.centerXAnchor),
                                         l.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
            w.contentView = v
            window = w
            label = l
        }
        label?.stringValue = text
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}
