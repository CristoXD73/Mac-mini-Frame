import Cocoa
import SwiftUI

// Full-screen "console" look: dark blue starfield with a controller outline that draws itself in.
// Covers every display except the one being played on (never turns a display off, so USB-C power
// and anything else plugged into it keeps working). Also used as the loading screen on the main
// display while Steam starts.

enum Pad: String { case xbox, playstation, steam }

// MARK: - Controller outlines (400 x 260 design box)

func padOutline(_ pad: Pad) -> Path {
    var p = Path()
    switch pad {
    case .steam:
        // Flat-topped body with short grips and a gap in the bottom edge.
        p.move(to: .init(x: 185, y: 205)); p.addLine(to: .init(x: 110, y: 205)); p.addLine(to: .init(x: 102, y: 218))
        p.addCurve(to: .init(x: 55, y: 255), control1: .init(x: 90, y: 238), control2: .init(x: 78, y: 252))
        p.addCurve(to: .init(x: 8, y: 190), control1: .init(x: 28, y: 258), control2: .init(x: 2, y: 235))
        p.addLine(to: .init(x: 22, y: 90))
        p.addCurve(to: .init(x: 80, y: 40), control1: .init(x: 28, y: 55), control2: .init(x: 45, y: 40))
        p.addLine(to: .init(x: 320, y: 40))
        p.addCurve(to: .init(x: 378, y: 90), control1: .init(x: 355, y: 40), control2: .init(x: 372, y: 55))
        p.addLine(to: .init(x: 392, y: 190))
        p.addCurve(to: .init(x: 345, y: 255), control1: .init(x: 398, y: 235), control2: .init(x: 372, y: 258))
        p.addCurve(to: .init(x: 298, y: 218), control1: .init(x: 322, y: 252), control2: .init(x: 310, y: 238))
        p.addLine(to: .init(x: 290, y: 205)); p.addLine(to: .init(x: 215, y: 205))
    case .xbox:
        // Rounded shoulders, long grips angled outward, arched bottom.
        p.move(to: .init(x: 200, y: 52))
        p.addQuadCurve(to: .init(x: 105, y: 42), control: .init(x: 150, y: 40))
        p.addCurve(to: .init(x: 30, y: 130), control1: .init(x: 60, y: 45), control2: .init(x: 40, y: 80))
        p.addCurve(to: .init(x: 55, y: 248), control1: .init(x: 18, y: 190), control2: .init(x: 20, y: 240))
        p.addCurve(to: .init(x: 130, y: 190), control1: .init(x: 85, y: 255), control2: .init(x: 105, y: 215))
        p.addQuadCurve(to: .init(x: 270, y: 190), control: .init(x: 200, y: 178))
        p.addCurve(to: .init(x: 345, y: 248), control1: .init(x: 295, y: 215), control2: .init(x: 315, y: 255))
        p.addCurve(to: .init(x: 370, y: 130), control1: .init(x: 380, y: 240), control2: .init(x: 382, y: 190))
        p.addCurve(to: .init(x: 295, y: 42), control1: .init(x: 360, y: 80), control2: .init(x: 340, y: 45))
        p.addQuadCurve(to: .init(x: 200, y: 52), control: .init(x: 250, y: 40))
    case .playstation:
        // Wide wings flaring down into long grips.
        p.move(to: .init(x: 200, y: 60)); p.addLine(to: .init(x: 140, y: 60))
        p.addCurve(to: .init(x: 40, y: 110), control1: .init(x: 90, y: 40), control2: .init(x: 55, y: 55))
        p.addCurve(to: .init(x: 55, y: 255), control1: .init(x: 25, y: 170), control2: .init(x: 15, y: 245))
        p.addCurve(to: .init(x: 135, y: 205), control1: .init(x: 90, y: 262), control2: .init(x: 110, y: 225))
        p.addQuadCurve(to: .init(x: 265, y: 205), control: .init(x: 200, y: 195))
        p.addCurve(to: .init(x: 345, y: 255), control1: .init(x: 290, y: 225), control2: .init(x: 310, y: 262))
        p.addCurve(to: .init(x: 360, y: 110), control1: .init(x: 385, y: 245), control2: .init(x: 375, y: 170))
        p.addCurve(to: .init(x: 260, y: 60), control1: .init(x: 345, y: 55), control2: .init(x: 310, y: 40))
        p.closeSubpath()
    }
    return p
}

/// The small detail that fades in after the outline: guide button, touchpad, etc.
func padDetail(_ pad: Pad) -> Path {
    switch pad {
    case .steam: return Path(ellipseIn: CGRect(x: 184, y: 69, width: 32, height: 32))
    case .xbox: return Path(ellipseIn: CGRect(x: 182, y: 74, width: 36, height: 36))
    case .playstation:
        var p = Path(roundedRect: CGRect(x: 145, y: 62, width: 110, height: 52), cornerRadius: 10)
        p.addEllipse(in: CGRect(x: 193, y: 150, width: 14, height: 14))
        return p
    }
}

// MARK: - Starfield

struct Star { let x, y, size, phase, speed, depth: Double; let tint: Int }

let stars: [Star] = {
    var g = SystemRandomNumberGenerator()
    return (0..<300).map { _ in
        let roll = Double.random(in: 0...1, using: &g)
        return Star(x: .random(in: 0...1, using: &g), y: .random(in: 0...1, using: &g), size: .random(in: 1.8...4.4, using: &g),
                    phase: .random(in: 0...(2 * .pi), using: &g), speed: .random(in: 0.4...1.4, using: &g),
                    depth: .random(in: 0.2...1, using: &g), tint: roll < 0.10 ? 1 : roll < 0.17 ? 2 : 0)
    }
}()

let starColors = [Color(red: 0.62, green: 0.74, blue: 1.0),    // pale blue
                  Color(red: 0.45, green: 0.95, blue: 1.0),    // cyan
                  Color(red: 0.78, green: 0.58, blue: 1.0)]    // violet

/// Deterministic pseudo-random in 0...1 for shooting star n.
func hash01(_ n: Int, _ salt: Int) -> Double {
    var x = UInt64(bitPattern: Int64(n &* 7919 &+ salt &* 104729)) &+ 0x9E3779B97F4A7C15
    x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9; x = (x ^ (x >> 27)) &* 0x94D049BB133111EB; x ^= x >> 31
    return Double(x % 10_000) / 10_000
}

struct TakeoverView: View {
    let pad: Pad
    let start: Date
    var showOutline = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            Canvas { gc, size in draw(gc: &gc, size: size, t: ctx.date.timeIntervalSince(start)) }
        }
        .ignoresSafeArea()
    }

    func draw(gc: inout GraphicsContext, size: CGSize, t: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let cx = size.width / 2, cy = size.height / 2
        let unit = size.height / 1080

        // Background: very deep navy, a touch lighter in the middle.
        gc.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(red: 0.008, green: 0.016, blue: 0.05), Color(red: 0.02, green: 0.045, blue: 0.12)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
        gc.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.30).opacity(0.55), .clear]),
                                                 center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: max(size.width, size.height) * 0.55))

        // Two slow nebula clouds drifting on long loops.
        for (i, c) in [(0, Color(red: 0.36, green: 0.18, blue: 0.62)), (1, Color(red: 0.08, green: 0.36, blue: 0.55))] {
            let a = t * 0.03 + Double(i) * 2.4
            let center = CGPoint(x: cx + cos(a) * size.width * 0.28, y: cy + sin(a * 1.3) * size.height * 0.22)
            gc.fill(Path(rect), with: .radialGradient(Gradient(colors: [c.opacity(0.16 * min(1, t / 2)), .clear]),
                                                     center: center, startRadius: 0, endRadius: size.height * 0.55))
        }

        // Pulse ring from the controller every 6 s; stars flare as it passes them.
        let ringPeriod = 6.0, ringStart = 3.0
        let ringPhase = t > ringStart ? (t - ringStart).truncatingRemainder(dividingBy: ringPeriod) / ringPeriod : -1
        let ringR = ringPhase >= 0 ? ringPhase * max(size.width, size.height) * 0.75 : -1000
        if ringPhase >= 0 {
            let fade = (1 - ringPhase) * 0.35
            gc.stroke(Path(ellipseIn: CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2)),
                      with: .color(Color(red: 0.5, green: 0.7, blue: 1).opacity(fade)), lineWidth: 2.5 * unit)
        }

        // Stars: hyperspace streaks for the first moments, then twinkle and slow drift.
        let warp = min(1, t / 1.4), warpEase = 1 - pow(1 - warp, 3)
        for s in stars {
            let tx = s.x * size.width, ty = s.y * size.height
            let drift = 1 + 0.05 * s.depth * sin(t * 0.07 + s.phase)
            var x = cx + (tx - cx) * drift, y = cy + (ty - cy) * drift
            let color = starColors[s.tint]
            var r = s.size * unit * (0.6 + 0.4 * s.depth)
            if warp < 1 {
                // Stars fly out from the center, leaving streaks.
                x = cx + (tx - cx) * warpEase; y = cy + (ty - cy) * warpEase
                let tail = max(0, warpEase - 0.35 * (1 - warp))
                var streak = Path()
                streak.move(to: CGPoint(x: cx + (tx - cx) * tail, y: cy + (ty - cy) * tail))
                streak.addLine(to: CGPoint(x: x, y: y))
                gc.stroke(streak, with: .color(color.opacity(0.75 * s.depth)), style: StrokeStyle(lineWidth: r * 0.9, lineCap: .round))
                continue
            }
            var alpha = (0.3 + 0.7 * (0.5 + 0.5 * sin(t * s.speed * 1.7 + s.phase))) * (0.35 + 0.65 * s.depth)
            let d = abs(hypot(x - cx, y - cy) - ringR)
            if d < 60 * unit { let k = 1 - d / (60 * unit); alpha = min(1, alpha + 0.8 * k); r *= 1 + 0.9 * k }
            gc.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(alpha)))
            if s.depth > 0.85 && alpha > 0.8 {   // brightest stars get a soft cross glint
                var glint = Path()
                glint.move(to: CGPoint(x: x - r * 3.5, y: y)); glint.addLine(to: CGPoint(x: x + r * 3.5, y: y))
                glint.move(to: CGPoint(x: x, y: y - r * 3.5)); glint.addLine(to: CGPoint(x: x, y: y + r * 3.5))
                gc.stroke(glint, with: .color(color.opacity((alpha - 0.8) * 2)), lineWidth: 0.8 * unit)
            }
        }

        // Shooting stars: one every ~3.5 s after the intro, each visible for about a second.
        if t > 2.5 {
            let period = 3.5, n = Int((t - 2.5) / period), q = ((t - 2.5) / period) - Double(n)
            let life = 0.3
            if q < life {
                let p = q / life
                let sx = size.width * (0.25 + 0.7 * hash01(n, 1)), sy = size.height * (0.05 + 0.35 * hash01(n, 2))
                let angle = Double.pi * (0.72 + 0.12 * hash01(n, 3))           // heading down-left
                let travel = size.width * 0.35
                let head = CGPoint(x: sx + cos(angle) * travel * p, y: sy + sin(angle) * travel * p)
                let tailLen = 220 * unit * min(1, p * 3)
                let tail = CGPoint(x: head.x - cos(angle) * tailLen, y: head.y - sin(angle) * tailLen)
                var trail = Path(); trail.move(to: tail); trail.addLine(to: head)
                let fade = p < 0.8 ? 1 : (1 - p) / 0.2
                gc.stroke(trail, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.9 * fade)]), startPoint: tail, endPoint: head),
                          style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round))
                gc.fill(Path(ellipseIn: CGRect(x: head.x - 2.5 * unit, y: head.y - 2.5 * unit, width: 5 * unit, height: 5 * unit)), with: .color(.white.opacity(fade)))
            }
        }

        guard showOutline else { return }
        // Controller outline draws itself in after the warp, then breathes softly.
        let scale = min(size.width * 0.34 / 400, size.height * 0.5 / 260)
        let transform = CGAffineTransform(translationX: cx - 200 * scale, y: cy - 150 * scale).scaledBy(x: scale, y: scale)
        let outline = padOutline(pad).applying(transform)
        let progress = min(1, max(0, (t - 0.9) / 1.6))
        let eased = 1 - pow(1 - progress, 3)
        let lw = 15 * scale
        // Glow brightens as each pulse ring leaves the controller.
        let pulseKick = ringPhase >= 0 && ringPhase < 0.12 ? (1 - ringPhase / 0.12) * 0.5 : 0
        let breathe = progress < 1 ? 1 : 0.7 + 0.25 * sin((t - 2.5) * 1.6) + pulseKick
        let drawn = outline.trimmedPath(from: 0, to: eased)
        gc.drawLayer { glow in
            glow.addFilter(.blur(radius: 20 * scale))
            glow.stroke(drawn, with: .color(Color(red: 0.4, green: 0.58, blue: 1).opacity(0.85 * breathe)), style: StrokeStyle(lineWidth: lw * 2.4, lineCap: .round, lineJoin: .round))
        }
        gc.stroke(drawn, with: .color(.white), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        // A bright spark rides the tip while the outline is being drawn.
        if progress > 0 && progress < 1, let tip = drawn.currentPoint {
            gc.fill(Path(ellipseIn: CGRect(x: tip.x - lw, y: tip.y - lw, width: lw * 2, height: lw * 2)), with: .color(.white))
            gc.drawLayer { spark in
                spark.addFilter(.blur(radius: 14 * scale))
                spark.fill(Path(ellipseIn: CGRect(x: tip.x - lw * 3, y: tip.y - lw * 3, width: lw * 6, height: lw * 6)), with: .color(Color(red: 0.6, green: 0.8, blue: 1)))
            }
        }
        let detailAlpha = min(1, max(0, (t - 2.4) / 0.5))
        if detailAlpha > 0 {
            gc.stroke(padDetail(pad).applying(transform), with: .color(.white.opacity(detailAlpha * 0.9)),
                      style: StrokeStyle(lineWidth: lw * 0.45, lineCap: .round))
        }
    }
}

// MARK: - Now Playing card and status chip (extra displays)

struct NowPlayingCard: View {
    let np: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            GeometryReader { g in
                let coverH = g.size.height * 0.56
                ZStack {
                    // Game art as a soft wash, pulled into the navy palette (not grey).
                    if let hero = np.art.hero ?? np.art.portrait {
                        Image(nsImage: hero).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: g.size.width, height: g.size.height).clipped()
                            .blur(radius: 60).saturation(1.3).opacity(0.5)
                        Color(red: 0.01, green: 0.03, blue: 0.10).opacity(0.62).blendMode(.multiply)
                        RadialGradient(colors: [.clear, Color(red: 0.005, green: 0.01, blue: 0.04).opacity(0.85)],
                                       center: .center, startRadius: g.size.height * 0.25, endRadius: g.size.width * 0.7)
                    }
                    HStack(spacing: g.size.width * 0.045) {
                        if let cover = np.art.portrait {
                            Image(nsImage: cover).resizable().aspectRatio(2 / 3, contentMode: .fill)
                                .frame(width: coverH * 2 / 3, height: coverH).clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
                                .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
                                .saturation(np.suspended ? 0.25 : 1).opacity(np.suspended ? 0.65 : 1)
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text(np.suspended ? "SUSPENDED" : "NOW PLAYING")
                                .font(.system(size: 17, weight: .semibold)).tracking(4)
                                .foregroundStyle(np.suspended ? Color(red: 1, green: 0.78, blue: 0.45).opacity(0.8) : Color(red: 0.6, green: 0.75, blue: 1).opacity(0.75))
                            if let logo = np.art.logo {
                                Image(nsImage: logo).resizable().aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: g.size.width * 0.34, maxHeight: g.size.height * 0.2, alignment: .leading)
                                    .shadow(color: .black.opacity(0.5), radius: 16)
                            } else {
                                Text(np.name).font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    .lineLimit(2).minimumScaleFactor(0.5)
                            }
                            Text(detail(ctx.date)).font(.system(size: 24, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(width: g.size.width * 0.36, alignment: .leading)
                    }
                    .frame(width: g.size.width, height: g.size.height)
                }
            }
        }
    }

    func detail(_ now: Date) -> String {
        if np.suspended { return "Xbox + X to resume" }
        let m = Int(now.timeIntervalSince(np.started) / 60)
        let played = m < 1 ? "just started" : m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
        return "Playing · \(played)"
    }
}

struct StatusChip: View {
    @ObservedObject var model = ScreenModel.shared
    var body: some View {
        HStack(spacing: 18) {
            if let note = model.storageNote {
                Label(note, systemImage: "externaldrive").foregroundStyle(Color(red: 1, green: 0.78, blue: 0.4).opacity(0.75))
            }
            if let b = model.battery {
                Label("\(Int(b * 100))%", systemImage: model.charging ? "battery.100.bolt" : b < 0.15 ? "battery.0" : b < 0.4 ? "battery.25" : b < 0.7 ? "battery.50" : "battery.100")
                    .foregroundStyle(b < 0.15 && !model.charging ? Color(red: 1, green: 0.5, blue: 0.45).opacity(0.8) : .white.opacity(0.4))
            }
        }
        .font(.system(size: 15, weight: .medium))
        .padding(28)
    }
}

struct ExtraDisplayView: View {
    let pad: Pad
    let start: Date
    @ObservedObject var model = ScreenModel.shared
    let nowPlayingEnabled: Bool

    var body: some View {
        let np = nowPlayingEnabled ? model.nowPlaying : nil
        ZStack(alignment: .bottomTrailing) {
            TakeoverView(pad: pad, start: start, showOutline: np == nil)
                .opacity(np == nil ? 1 : 0.55)
            if let np { NowPlayingCard(np: np).transition(.opacity) }
            StatusChip()
        }
        .animation(.easeInOut(duration: 0.8), value: np)
        .ignoresSafeArea()
    }
}

// MARK: - Windows

/// Starfield on every display except the main one, where Steam and games run.
@MainActor
final class Takeover {
    private var windows: [NSWindow] = []
    private(set) var pad: Pad = .xbox
    private var start = Date()
    var nowPlayingEnabled = true

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.windows.isEmpty == false { self?.rebuild() } }   // a display was plugged in or removed
        }
    }

    var windowCount: Int { windows.count }

    func show(pad: Pad) {
        guard windows.isEmpty || pad != self.pad else { return }
        self.pad = pad
        start = Date()
        rebuild()
    }

    func hideAll() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        let screens = NSScreen.screens
        guard let main = screens.first else { return }
        for screen in screens where screen != main {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))   // above everything on that display
            w.backgroundColor = .black
            w.isOpaque = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.contentView = NSHostingView(rootView: ExtraDisplayView(pad: pad, start: start, nowPlayingEnabled: nowPlayingEnabled))
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }
}

/// Plain black cover on the main display while Steam starts, so the desktop isn't visible.
@MainActor
final class LoadingCover {
    private var window: NSWindow?
    private var label: NSTextField?

    func show(_ text: String) {
        if window == nil {
            let screen = NSScreen.screens.first!
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            w.backgroundColor = .black
            w.level = .normal                 // Steam and games come up on top of it
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let l = NSTextField(labelWithString: "")
            l.font = .systemFont(ofSize: 22, weight: .medium)
            l.textColor = NSColor(white: 1, alpha: 0.55)
            l.alignment = .center
            l.frame = NSRect(x: 0, y: screen.frame.height * 0.12, width: screen.frame.width, height: 30)
            w.contentView?.addSubview(l)
            w.setFrame(screen.frame, display: true)
            window = w; label = l
        }
        label?.stringValue = text
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() { window?.orderOut(nil) }
}
