// Renders the app icon (docs/images/icon.png, app/AppIcon.icns) from the same controller outline
// the app draws on extra displays. Built by tools/render-icon.sh together with src/Takeover.swift.
import Cocoa
import SwiftUI

struct IconView: View {
    let size: CGFloat
    var body: some View {
        Canvas { gc, sz in
            let s = sz.width / 1024
            // macOS icon grid: 824 pt rounded square centred in 1024, continuous corners.
            let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
            let shape = Path(roundedRect: tile, cornerRadius: 185 * s, style: .continuous)
            var shadow = gc
            shadow.addFilter(.shadow(color: .black.opacity(0.35), radius: 18 * s, y: 10 * s))
            shadow.fill(shape, with: .color(.black))
            gc.clip(to: shape)
            gc.fill(shape, with: .radialGradient(Gradient(colors: [Color(red: 0.09, green: 0.16, blue: 0.40), Color(red: 0.03, green: 0.06, blue: 0.19), Color(red: 0.01, green: 0.02, blue: 0.08)]),
                                                  center: CGPoint(x: 512 * s, y: 470 * s), startRadius: 0, endRadius: 600 * s))
            // Stars
            for i in 0..<70 {
                let x = 100 + 824 * hash01(i, 11), y = 100 + 824 * hash01(i, 23)
                let r = (0.8 + 2.6 * pow(hash01(i, 37), 3)) * s
                let a = 0.25 + 0.7 * hash01(i, 41)
                gc.fill(Path(ellipseIn: CGRect(x: x * s - r, y: y * s - r, width: r * 2, height: r * 2)),
                        with: .color((hash01(i, 5) > 0.8 ? Color(red: 0.7, green: 0.8, blue: 1) : .white).opacity(a)))
            }
            // Soft halo ring behind the controller
            let ring = Path(ellipseIn: CGRect(x: 262 * s, y: 222 * s, width: 500 * s, height: 500 * s))
            gc.stroke(ring, with: .color(Color(red: 0.5, green: 0.65, blue: 1).opacity(0.28)), lineWidth: 3 * s)
            // Controller outline (400 x 280 design space), glowing.
            let k = 1.45 * s
            let t = CGAffineTransform(translationX: 512 * s - 200 * k, y: 470 * s - 150 * k).scaledBy(x: k, y: k)
            let pad = padOutline(.xbox).applying(t), dot = padDetail(.xbox).applying(t)
            for (w, o) in [(40.0, 0.10), (24.0, 0.18), (14.0, 0.35)] {
                var g = gc; g.addFilter(.blur(radius: w * s * 0.6))
                g.stroke(pad, with: .color(Color(red: 0.45, green: 0.65, blue: 1).opacity(o * 2)), style: StrokeStyle(lineWidth: w * s, lineCap: .round, lineJoin: .round))
            }
            gc.stroke(pad, with: .color(.white), style: StrokeStyle(lineWidth: 17 * s, lineCap: .round, lineJoin: .round))
            gc.stroke(dot, with: .color(.white), style: StrokeStyle(lineWidth: 10 * s))
            // A thin "frame" line: the screen the Mac turns into.
            let base = Path(roundedRect: CGRect(x: 332 * s, y: 790 * s, width: 360 * s, height: 10 * s), cornerRadius: 5 * s)
            gc.fill(base, with: .linearGradient(Gradient(colors: [.clear, Color(red: 0.6, green: 0.75, blue: 1).opacity(0.9), .clear]),
                                                 startPoint: CGPoint(x: 332 * s, y: 0), endPoint: CGPoint(x: 692 * s, y: 0)))
            // Top sheen
            gc.fill(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.08), .clear]), startPoint: CGPoint(x: 0, y: 100 * s), endPoint: CGPoint(x: 0, y: 500 * s)))
        }
        .frame(width: size, height: size)
    }
}

// 1280x640 card for link previews (GitHub social preview, the website's og:image).
struct SocialCard: View {
    var body: some View {
        ZStack {
            Canvas { gc, size in TakeoverView(pad: .xbox, start: Date(), showOutline: false).draw(gc: &gc, size: size, t: 5) }
            HStack(spacing: 56) {
                IconView(size: 360)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Mac-mini-Frame").font(.system(size: 76, weight: .bold, design: .rounded))
                    Text("Turn your Mac into a game console.").font(.system(size: 36, weight: .medium)).opacity(0.85)
                    Text("Xbox button → Steam Big Picture · Windows games via CrossOver + GPTK")
                        .font(.system(size: 22, weight: .medium)).opacity(0.55).padding(.top, 8)
                }
                .foregroundStyle(.white)
            }
        }
        .frame(width: 1280, height: 640)
    }
}

MainActor.assumeIsolated {
    let dir = CommandLine.arguments[1]
    let card = ImageRenderer(content: SocialCard()); card.scale = 1
    try! NSBitmapImageRep(cgImage: card.cgImage!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/social.png"))
    for px in [16, 32, 64, 128, 256, 512, 1024] {
        let r = ImageRenderer(content: IconView(size: CGFloat(px))); r.scale = 1
        let rep = NSBitmapImageRep(cgImage: r.cgImage!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/icon_\(px).png"))
    }
}
