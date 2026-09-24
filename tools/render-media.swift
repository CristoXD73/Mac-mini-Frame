// Renders the README images and GIFs from Console Mode's real SwiftUI views.
//   tools/render-media.sh   (compiles this with src/*.swift minus main.swift, writes docs/images/)
// Frames are written as PNGs into $OUT/<scene>/, then ffmpeg turns them into GIFs.
// All art is generated here (a made-up game), so no game's artwork ends up in the repo.
import Cocoa
import SwiftUI

let out = ProcessInfo.processInfo.environment["OUT"] ?? "media-frames"
let W = 1920.0, H = 1080.0
let fps = 15.0

@MainActor func save(_ view: some View, _ path: String, scale: CGFloat = 0.5) {
    let r = ImageRenderer(content: view.frame(width: W, height: H).environment(\.colorScheme, .dark))
    r.scale = scale
    guard let cg = r.cgImage else { print("render failed: \(path)"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    let url = URL(fileURLWithPath: "\(out)/\(path)")
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

@MainActor func image(_ view: some View, _ w: Double, _ h: Double) -> NSImage {
    let r = ImageRenderer(content: view.frame(width: w, height: h)); r.scale = 1
    return r.nsImage!
}

// A stand-in "game" behind the HUD: a neon night-city racer in the app's own palette (navy, pale
// blue, cyan, violet, like the starfield). Purely procedural; `t` scrolls the road.
struct GameScene: View {
    var t: Double = 0
    var body: some View {
        Canvas { gc, size in
            let w = size.width, h = size.height, hy = h * 0.56          // horizon
            let paleBlue = Color(red: 0.62, green: 0.74, blue: 1), cyan = Color(red: 0.45, green: 0.95, blue: 1), violet = Color(red: 0.78, green: 0.58, blue: 1)
            // Sky
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.008, green: 0.016, blue: 0.05), Color(red: 0.03, green: 0.06, blue: 0.18), Color(red: 0.16, green: 0.10, blue: 0.36)]),
                                                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: hy)))
            for i in 0..<160 {
                let x = w * hash01(i, 3), y = hy * 0.85 * hash01(i, 7), r = 0.8 + 2.2 * pow(hash01(i, 9), 3)
                gc.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color([paleBlue, cyan, violet][i % 3].opacity(0.3 + 0.6 * hash01(i, 11))))
            }
            // Horizon glow
            gc.fill(Path(CGRect(x: 0, y: hy - h * 0.25, width: w, height: h * 0.5)), with: .radialGradient(Gradient(colors: [violet.opacity(0.45), Color(red: 0.2, green: 0.3, blue: 0.9).opacity(0.18), .clear]),
                                                                                                          center: CGPoint(x: w / 2, y: hy), startRadius: 0, endRadius: w * 0.45))
            // Skyline: two layers of towers with lit windows
            for layer in 0..<2 {
                let n = layer == 0 ? 34 : 22, maxH = layer == 0 ? h * 0.22 : h * 0.34
                var x = -20.0
                for i in 0..<n {
                    let bw = w / Double(n) * (0.7 + 0.6 * hash01(i, 20 + layer))
                    let bh = maxH * (0.3 + 0.7 * hash01(i, 30 + layer)) * (1 - 0.55 * pow(1 - abs(x + bw / 2 - w / 2) / (w / 2), 2) * Double(layer))
                    let r = CGRect(x: x, y: hy - bh, width: bw - 4, height: bh)
                    gc.fill(Path(r), with: .color(layer == 0 ? Color(red: 0.06, green: 0.07, blue: 0.20) : Color(red: 0.02, green: 0.03, blue: 0.09)))
                    gc.stroke(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 0.5)), with: .color((layer == 0 ? violet : cyan).opacity(0.6)), lineWidth: 2)
                    for wy in stride(from: r.minY + 12, to: r.maxY - 8, by: 16) {
                        for wx in stride(from: r.minX + 6, to: r.maxX - 8, by: 12) where hash01(Int(wx * 7 + wy * 13), 50 + layer) > 0.72 {
                            gc.fill(Path(CGRect(x: wx, y: wy, width: 5, height: 7)), with: .color((hash01(Int(wx + wy), 60) > 0.5 ? cyan : paleBlue).opacity(layer == 0 ? 0.35 : 0.7)))
                        }
                    }
                    x += bw
                }
            }
            // Ground and neon perspective grid
            gc.fill(Path(CGRect(x: 0, y: hy, width: w, height: h - hy)), with: .linearGradient(Gradient(colors: [Color(red: 0.06, green: 0.04, blue: 0.16), Color(red: 0.008, green: 0.016, blue: 0.05)]),
                                                                                              startPoint: CGPoint(x: 0, y: hy), endPoint: CGPoint(x: 0, y: h)))
            let vp = CGPoint(x: w / 2, y: hy)
            for k in -14...14 {
                var p = Path(); p.move(to: vp); p.addLine(to: CGPoint(x: w / 2 + Double(k) * w * 0.16, y: h))
                gc.stroke(p, with: .color(violet.opacity(0.35)), lineWidth: 1.5)
            }
            let scroll = (t * 1.6).truncatingRemainder(dividingBy: 1)
            for j in 0..<14 {
                let z = pow((Double(j) + scroll) / 14, 2.2)
                let y = hy + (h - hy) * z
                gc.stroke(Path(CGRect(x: 0, y: y, width: w, height: 0.1)), with: .color(cyan.opacity(0.15 + 0.5 * z)), lineWidth: 1 + 2 * z)
            }
            gc.stroke(Path(CGRect(x: 0, y: hy, width: w, height: 0.1)), with: .color(cyan.opacity(0.9)), lineWidth: 3)
            // Road with glowing edges and light streaks rushing toward the viewer
            var road = Path(); road.move(to: CGPoint(x: w / 2 - 14, y: hy)); road.addLine(to: CGPoint(x: w / 2 + 14, y: hy))
            road.addLine(to: CGPoint(x: w * 0.82, y: h)); road.addLine(to: CGPoint(x: w * 0.18, y: h)); road.closeSubpath()
            gc.fill(road, with: .color(Color(red: 0.01, green: 0.02, blue: 0.06).opacity(0.85)))
            for (side, c) in [(-1.0, cyan), (1.0, violet)] {
                var e = Path(); e.move(to: CGPoint(x: w / 2 + side * 14, y: hy)); e.addLine(to: CGPoint(x: w / 2 + side * w * 0.32, y: h))
                var g = gc; g.addFilter(.blur(radius: 8)); g.stroke(e, with: .color(c), lineWidth: 8)
                gc.stroke(e, with: .color(.white.opacity(0.9)), lineWidth: 2)
            }
            for j in 0..<6 {
                let z0 = pow((Double(j) / 6 + t * 0.9).truncatingRemainder(dividingBy: 1), 2.4), z1 = min(1, z0 + 0.05 + 0.1 * z0)
                var d = Path()
                d.move(to: CGPoint(x: w / 2, y: hy + (h - hy) * z0)); d.addLine(to: CGPoint(x: w / 2, y: hy + (h - hy) * z1))
                gc.stroke(d, with: .color(paleBlue.opacity(0.85)), lineWidth: 2 + 10 * z0)
            }
        }
    }
}

// MARK: - Controller overlay: which buttons are being pressed in each scene

struct PadState { var pressed: Set<String> = []; var keys = ""; var action = "" }

/// An Xbox controller seen from the front (same 400x280 outline the app draws), with the pressed
/// buttons lit, and a caption such as "Xbox + D-pad ↑  volume up".
struct PadOverlay: View {
    let s: PadState
    var scale: CGFloat = 0.8
    var body: some View {
        VStack(spacing: 16 * scale) {
            Canvas { gc, size in
                let k = size.width / 400
                gc.scaleBy(x: k, y: k)
                let accent = Color(red: 0.55, green: 0.75, blue: 1)
                func on(_ b: String) -> Bool { s.pressed.contains(b) }
                func glow(_ p: Path, _ c: Color) {
                    var g = gc; g.addFilter(.blur(radius: 10)); g.fill(p, with: .color(c.opacity(0.9)))
                    gc.fill(p, with: .color(c))
                }
                // Bumpers (drawn first, behind the body)
                for (name, x) in [("lb", 64.0), ("rb", 244.0)] {
                    let p = Path(roundedRect: CGRect(x: x, y: 20, width: 92, height: 26), cornerRadius: 12)
                    if on(name) { glow(p, accent) } else { gc.fill(p, with: .color(.white.opacity(0.10))) }
                    gc.stroke(p, with: .color(.white.opacity(0.55)), lineWidth: 2)
                    gc.draw(Text(name.uppercased()).font(.system(size: 13, weight: .bold)).foregroundColor(on(name) ? .black : .white.opacity(0.7)),
                            at: CGPoint(x: x + 46, y: 33))
                }
                let body = padOutline(.xbox)
                gc.fill(body, with: .color(Color(red: 0.06, green: 0.08, blue: 0.16)))
                gc.stroke(body, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                // Xbox button
                let xb = Path(ellipseIn: CGRect(x: 182, y: 70, width: 36, height: 36))
                if on("xbox") { glow(xb, Color(red: 0.75, green: 1, blue: 0.75)) } else { gc.fill(xb, with: .color(.white.opacity(0.12))) }
                gc.stroke(xb, with: .color(.white.opacity(0.8)), lineWidth: 2)
                gc.draw(Image(systemName: "xmark").resizable(), in: CGRect(x: 192, y: 80, width: 16, height: 16))
                // View / Menu
                for (name, x) in [("view", 164.0), ("menu", 236.0)] {
                    let p = Path(ellipseIn: CGRect(x: x - 9, y: 118, width: 18, height: 18))
                    if on(name) { glow(p, accent) } else { gc.fill(p, with: .color(.white.opacity(0.12))) }
                    gc.stroke(p, with: .color(.white.opacity(0.6)), lineWidth: 1.5)
                }
                // Sticks
                for c in [CGPoint(x: 110, y: 104), CGPoint(x: 252, y: 162)] {
                    gc.stroke(Path(ellipseIn: CGRect(x: c.x - 23, y: c.y - 23, width: 46, height: 46)), with: .color(.white.opacity(0.45)), lineWidth: 2)
                    gc.fill(Path(ellipseIn: CGRect(x: c.x - 14, y: c.y - 14, width: 28, height: 28)), with: .color(.white.opacity(0.14)))
                }
                // D-pad
                let dc = CGPoint(x: 150, y: 162), arm = 18.0, w = 13.0
                let arms: [(String, CGRect)] = [("up", CGRect(x: dc.x - w / 2, y: dc.y - arm - w / 2, width: w, height: arm)),
                                                ("down", CGRect(x: dc.x - w / 2, y: dc.y + w / 2, width: w, height: arm)),
                                                ("left", CGRect(x: dc.x - arm - w / 2, y: dc.y - w / 2, width: arm, height: w)),
                                                ("right", CGRect(x: dc.x + w / 2, y: dc.y - w / 2, width: arm, height: w))]
                gc.fill(Path(CGRect(x: dc.x - w / 2, y: dc.y - w / 2, width: w, height: w)), with: .color(.white.opacity(0.18)))
                for (name, r) in arms {
                    let p = Path(roundedRect: r, cornerRadius: 3)
                    if on(name) { glow(p, accent) } else { gc.fill(p, with: .color(.white.opacity(0.18))) }
                }
                // A B X Y
                let face: [(String, CGPoint, Color)] = [("y", CGPoint(x: 292, y: 80), Color(red: 1, green: 0.8, blue: 0.2)),
                                                        ("x", CGPoint(x: 268, y: 104), Color(red: 0.3, green: 0.6, blue: 1)),
                                                        ("b", CGPoint(x: 316, y: 104), Color(red: 1, green: 0.35, blue: 0.35)),
                                                        ("a", CGPoint(x: 292, y: 128), Color(red: 0.35, green: 0.85, blue: 0.4))]
                for (name, c, col) in face {
                    let p = Path(ellipseIn: CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24))
                    if on(name) { glow(p, col) } else { gc.fill(p, with: .color(.white.opacity(0.10))) }
                    gc.stroke(p, with: .color(col.opacity(0.9)), lineWidth: 2)
                    gc.draw(Text(name.uppercased()).font(.system(size: 13, weight: .heavy)).foregroundColor(on(name) ? .black : col), at: c)
                }
            }
            .frame(width: 400 * scale, height: 280 * scale)
            .shadow(color: .black.opacity(0.5), radius: 24 * scale, y: 10 * scale)

            if !s.keys.isEmpty {
                HStack(spacing: 12 * scale) {
                    Text(s.keys).font(.system(size: 24 * scale, weight: .bold))
                    if !s.action.isEmpty { Text(s.action).font(.system(size: 24 * scale, weight: .medium)).opacity(0.7) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22 * scale).frame(height: 48 * scale)
                .background(Capsule().fill(Color(white: 0.08).opacity(0.85)))
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            }
        }
        .frame(width: 520 * scale)
    }
}

extension View {
    func pad(_ s: PadState, at p: CGPoint, scale: CGFloat = 1.05) -> some View {
        ZStack { self; PadOverlay(s: s, scale: scale).position(p) }.frame(width: W, height: H)
    }
}

// Made-up game art for the launch screen and Now Playing card.
@MainActor func makeArt() -> GameArt {
    let hero = image(ZStack { GameScene() }, 1920, 1080)
    let portrait = image(ZStack {
        GameScene()
        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
        VStack { Spacer(); Text("SKYLINE\nDRIFT").font(.system(size: 84, weight: .black, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.white).shadow(color: Color(red: 0.45, green: 0.95, blue: 1).opacity(0.8), radius: 18).padding(.bottom, 60) }
    }, 600, 900)
    return GameArt(portrait: portrait, hero: hero, logo: nil)
}

@MainActor func renderTakeover() {
    for (pad, secs) in [(Pad.xbox, 6.0)] {
        let n = Int(secs * fps)
        for i in 0..<n {
            let t = Double(i) / fps
            let st = PadState(pressed: t < 0.5 ? ["xbox"] : [], keys: "Xbox", action: "game mode")
            save(Canvas { gc, size in TakeoverView(pad: pad, start: Date()).draw(gc: &gc, size: size, t: t) }.pad(st, at: CGPoint(x: 1560, y: 820)), "takeover/\(String(format: "%04d", i)).png")
        }
    }
    for (pad, t) in [(Pad.xbox, 5.0), (.playstation, 5.0), (.steam, 5.0)] {
        save(Canvas { gc, size in TakeoverView(pad: pad, start: Date()).draw(gc: &gc, size: size, t: t) }, "still-\(pad.rawValue).png")
    }
}

@MainActor func renderHold() {
    Glass.previewFill = true
    let m = HUDModel()
    // 0.6 s of game, ring appears at 2 s of holding (shown here from 0), fills over 4 s, then "Returning to PC".
    let frames = Int(6.2 * fps)
    for i in 0..<frames {
        let t = Double(i) / fps
        if t < 0.5 { m.hold = nil } else if t < 4.5 { m.hold = (t - 0.5) / 4; m.holdDone = false } else { m.hold = 1; m.holdDone = true }
        let held = t < 0.5 ? t / 0.5 * 2 : min(6, 2 + (t - 0.5))
        let st = m.holdDone ? PadState(pressed: [], keys: "Xbox held 6 s", action: "back to the desktop")
                            : PadState(pressed: ["xbox"], keys: "Hold Xbox", action: String(format: "%.1f s", held))
        save(ZStack { GameScene(t: t); Color.black.opacity(m.hold == nil ? 0 : 0.25); HUDView(m: m) }.pad(st, at: CGPoint(x: 960, y: 880), scale: 0.8), "hold/\(String(format: "%04d", i)).png", scale: 1)
    }
}

@MainActor func renderVolume() {
    Glass.previewFill = true
    let m = HUDModel()
    let levels: [Float] = [6, 7, 8, 9, 10, 11, 12, 12, 12, 11, 10, 9, 8, 8, 8].map { $0 / 16 }
    var i = 0
    for (k, v) in levels.enumerated() {
        m.volume = v
        let st = k <= 6 ? PadState(pressed: k == 0 ? [] : ["xbox", "up"], keys: "Xbox + D-pad ↑", action: "volume up")
               : k <= 8 ? PadState(pressed: ["xbox"], keys: "Xbox + D-pad", action: "volume")
               : k <= 12 ? PadState(pressed: ["xbox", "down"], keys: "Xbox + D-pad ↓", action: "volume down")
               : PadState(pressed: [], keys: "Xbox + D-pad", action: "volume")
        for _ in 0..<(k == levels.count - 1 ? 12 : 4) { save(ZStack { GameScene(t: Double(i) / fps); HUDView(m: m) }.pad(st, at: CGPoint(x: 1620, y: 310), scale: 0.85), "volume/\(String(format: "%04d", i)).png", scale: 1); i += 1 }
    }
}

@MainActor func renderMessages() {
    Glass.previewFill = true
    let items = [("camera.fill", "Screenshot saved"), ("pause.fill", "Game suspended · Xbox + X to resume"),
                 ("exclamationmark.triangle.fill", "Force quit Skyline Drift? Press Xbox + Menu + View again")]
    for (k, (icon, text)) in items.enumerated() {
        let m = HUDModel(); m.message = (icon, text)
        save(ZStack { GameScene(); HUDView(m: m) }, "message-\(k).png", scale: 1)
    }
}

// The launch screen's progress bar runs on the wall clock, so these frames are paced in real time.
@MainActor func renderLaunch(_ art: GameArt) {
    let model = LaunchModel()
    let view = LaunchView(name: "Skyline Drift", art: art, model: model)
    let n = Int(5.0 * fps)
    let t0 = Date()
    for i in 0..<n {
        let target = t0.addingTimeInterval(Double(i) / fps)
        let wait = target.timeIntervalSinceNow; if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        let t = Double(i) / fps
        model.status = t < 2.6 ? "Starting" : "Scooting over to your game…"
        save(view.pad(PadState(pressed: t < 0.5 ? ["a"] : [], keys: "A", action: "start the game"), at: CGPoint(x: 1560, y: 820)), "launch/\(String(format: "%04d", i)).png")
    }
}

@MainActor func renderNowPlaying(_ art: GameArt) {
    let np = NowPlaying(name: "Skyline Drift", started: Date().addingTimeInterval(-47 * 60), suspended: false, art: art)
    let bg = { (t: Double) in Canvas { gc, size in TakeoverView(pad: .xbox, start: Date(), showOutline: false).draw(gc: &gc, size: size, t: t) } }
    save(ZStack { bg(5).opacity(0.55); NowPlayingCard(np: np) }, "now-playing.png")
    var s = np; s.suspended = true
    save(ZStack { bg(5).opacity(0.55); NowPlayingCard(np: s) }, "now-playing-suspended.png")
}

@MainActor func renderRewind() {
    let m = RewindModel()
    let cal = Calendar.current, now = Date()
    let snaps = (0..<9).map { k -> RewindSnapshot in
        let d = cal.date(byAdding: .minute, value: -(8 - k) * 25, to: now)!
        return RewindSnapshot(id: "snap\(k)", time: d, files: k == 5 ? 4 : 3, kind: k == 5 ? "before-restore" : "auto")
    }
    m.groups = [RewindGroup(id: "Saved Games - Example Studio - Skyline Drift", snapshots: snaps),
                RewindGroup(id: "Documents - Other Studio - Another Game", snapshots: Array(snaps.prefix(3)))]
    var i = 0
    let at = CGPoint(x: 1560, y: 760)
    func frame(_ st: PadState) { save(RewindView(model: m).pad(st, at: at), "rewind/\(String(format: "%04d", i)).png"); i += 1 }
    for idx in [8, 7, 6, 5, 4, 3] {
        m.index = idx
        for f in 0..<(idx == 8 ? 12 : idx == 3 ? 10 : 6) {
            frame(idx == 8 ? PadState(pressed: f < 6 ? ["xbox", "lb"] : [], keys: "Xbox + LB", action: "open Save Rewind")
                           : PadState(pressed: f < 3 ? ["lb"] : [], keys: "LB", action: "back in time"))
        }
    }
    m.confirming = true
    for f in 0..<22 { frame(PadState(pressed: (4..<8).contains(f) ? ["a"] : [], keys: "A", action: "restore this save")) }
    m.confirming = false; m.index = 8
    save(RewindView(model: m), "rewind.png")
}

MainActor.assumeIsolated {
    let only = CommandLine.arguments.dropFirst()
    func want(_ s: String) -> Bool { only.isEmpty || only.contains(s) }
    let art = makeArt()
    if want("takeover") { renderTakeover() }
    if want("hold") { renderHold() }
    if want("volume") { renderVolume() }
    if want("messages") { renderMessages() }
    if want("launch") { renderLaunch(art) }
    if want("nowplaying") { renderNowPlaying(art) }
    if want("rewind") { renderRewind() }
    print("frames in \(out)")
}
