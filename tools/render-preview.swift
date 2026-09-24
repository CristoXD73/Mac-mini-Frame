// Renders sample takeover frames into one JPEG strip.
//   swiftc -parse-as-library tools/render-preview.swift src/Common.swift src/Takeover.swift \
//     src/Input.swift -o /tmp/preview && /tmp/preview docs/images/takeover-frames.jpg
import AppKit
import SwiftUI

@main
struct Preview {
    @MainActor static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "takeover-frames.jpg"
        let times: [Double] = [0.5, 1.4, 2.0, 3.5, 5.0, 8.0]
        let size = CGSize(width: 640, height: 360)
        let strip = NSImage(size: CGSize(width: size.width * 3, height: size.height * 2))
        strip.lockFocus()
        for (i, t) in times.enumerated() {
            let view = Canvas { g, s in Starfield.draw(&g, size: s, t: t, style: i == 5 ? .playstation : .xbox) }
                .frame(width: size.width, height: size.height)
            let r = ImageRenderer(content: view)
            r.scale = 1
            guard let img = r.nsImage else { continue }
            img.draw(in: CGRect(x: CGFloat(i % 3) * size.width, y: CGFloat(1 - i / 3) * size.height,
                                width: size.width, height: size.height))
        }
        strip.unlockFocus()
        guard let tiff = strip.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            print("render failed"); exit(1)
        }
        try! jpg.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
