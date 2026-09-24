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

// A stand-in "game" behind the HUD: dusk sky, hills, a few lights. Purely procedural.
struct GameScene: View {
    var body: some View {
        Canvas { gc, size in
            let r = CGRect(origin: .zero, size: size)
            gc.fill(Path(r), with: .linearGradient(Gradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.32), Color(red: 0.55, green: 0.28, blue: 0.42), Color(red: 0.95, green: 0.55, blue: 0.35)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.72)))
            gc.fill(Path(ellipseIn: CGRect(x: size.width * 0.62, y: size.height * 0.46, width: 180, height: 180)), with: .color(Color(red: 1, green: 0.85, blue: 0.6).opacity(0.9)))
            for (i, (base, amp, col)) in [(0.66, 90.0, Color(red: 0.25, green: 0.16, blue: 0.30)), (0.76, 70.0, Color(red: 0.13, green: 0.09, blue: 0.20)), (0.86, 50.0, Color(red: 0.05, green: 0.04, blue: 0.10))].enumerated() {
                var p = Path(); p.move(to: CGPoint(x: 0, y: size.height))
                for x in stride(from: 0.0, through: size.width, by: 8) {
                    let y = size.height * base - amp * (0.6 * sin(x / (260 + Double(i) * 70) + Double(i)) + 0.4 * sin(x / 97 + Double(i) * 2))
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height)); p.closeSubpath()
                gc.fill(p, with: .color(col))
            }
            for i in 0..<14 {
                let x = size.width * (0.08 + 0.065 * Double(i)), y = size.height * (0.9 + 0.03 * sin(Double(i) * 1.7))
                gc.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 6, height: 6)), with: .color(Color(red: 1, green: 0.8, blue: 0.45)))
            }
        }
    }
}

// Made-up game art for the launch screen and Now Playing card.
@MainActor func makeArt() -> GameArt {
    let hero = image(ZStack { GameScene() }, 1920, 1080)
    let portrait = image(ZStack {
        GameScene()
        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
        VStack { Spacer(); Text("SKYLINE\nDRIFT").font(.system(size: 84, weight: .black, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.white).padding(.bottom, 60) }
    }, 600, 900)
    return GameArt(portrait: portrait, hero: hero, logo: nil)
}

@MainActor func renderTakeover() {
    for (pad, secs) in [(Pad.xbox, 6.0)] {
        let n = Int(secs * fps)
        for i in 0..<n {
            let t = Double(i) / fps
            save(Canvas { gc, size in TakeoverView(pad: pad, start: Date()).draw(gc: &gc, size: size, t: t) }, "takeover/\(String(format: "%04d", i)).png")
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
        save(ZStack { GameScene(); Color.black.opacity(m.hold == nil ? 0 : 0.25); HUDView(m: m) }, "hold/\(String(format: "%04d", i)).png", scale: 1)
    }
}

@MainActor func renderVolume() {
    Glass.previewFill = true
    let m = HUDModel()
    let levels: [Float] = [6, 7, 8, 9, 10, 11, 12, 12, 12, 11, 10, 9, 8, 8, 8].map { $0 / 16 }
    var i = 0
    for (k, v) in levels.enumerated() {
        m.volume = v
        for _ in 0..<(k == levels.count - 1 ? 12 : 4) { save(ZStack { GameScene(); HUDView(m: m) }, "volume/\(String(format: "%04d", i)).png", scale: 1); i += 1 }
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
        save(view, "launch/\(String(format: "%04d", i)).png")
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
    for idx in [8, 7, 6, 5, 4, 3] {
        m.index = idx
        for _ in 0..<(idx == 3 ? 10 : 6) { save(RewindView(model: m), "rewind/\(String(format: "%04d", i)).png"); i += 1 }
    }
    m.confirming = true
    for _ in 0..<20 { save(RewindView(model: m), "rewind/\(String(format: "%04d", i)).png"); i += 1 }
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
