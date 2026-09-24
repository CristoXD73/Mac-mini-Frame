import Cocoa
import SwiftUI

// Shown on the main display from the moment a tile is launched until the game's window appears,
// so the wait for Wine is a proper loading screen instead of a frozen Big Picture.

@MainActor
final class LaunchModel: ObservableObject {
    @Published var status = "Starting"
}

struct LaunchView: View {
    let name: String
    let art: GameArt
    @ObservedObject var model: LaunchModel
    let start = Date()

    var body: some View {
        ZStack {
            Color.black
            if let hero = art.hero ?? art.portrait {
                Image(nsImage: hero).resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: 24).opacity(0.45).clipped()
            }
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 34) {
                Spacer()
                if let logo = art.logo {
                    Image(nsImage: logo).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 560, maxHeight: 200)
                        .shadow(color: .black.opacity(0.6), radius: 20)
                } else {
                    Text(name).font(.system(size: 54, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 20)
                }
                // Thin indeterminate bar: a soft highlight sweeping left to right.
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                    let t = ctx.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 1.6) / 1.6
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule().fill(LinearGradient(colors: [.clear, Color(red: 0.55, green: 0.72, blue: 1), .clear], startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * 0.35)
                                .offset(x: (g.size.width * 1.35) * t - g.size.width * 0.35)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(width: 320, height: 4)
                }
                Text(model.status).font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    .contentTransition(.opacity).animation(.easeInOut(duration: 0.25), value: model.status)
                Spacer().frame(height: 140)
            }
        }
        .ignoresSafeArea()
    }
}

@MainActor
final class LaunchScreen {
    private var window: NSWindow?
    private(set) var showingFor: Double?      // session time it's showing for
    private let model = LaunchModel()

    /// Change the line under the loading bar (e.g. right before switching to the game's Space).
    func setStatus(_ text: String) { model.status = text }

    func show(_ s: Session) {
        guard showingFor != s.time else { return }
        hide()
        let screen = NSScreen.screens.first!
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        w.level = .floating                    // above Big Picture; the game's own window replaces it
        w.backgroundColor = .black
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        model.status = "Starting"
        w.contentView = NSHostingView(rootView: LaunchView(name: s.name, art: gameArt(for: s), model: model))
        w.setFrame(screen.frame, display: true)
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; w.animator().alphaValue = 1 }
        window = w
        showingFor = s.time
        log("launch screen: \(s.name)")
    }

    func hide() {
        guard let w = window else { return }
        window = nil
        showingFor = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; w.animator().alphaValue = 0 }, completionHandler: { w.orderOut(nil) })
    }
}
