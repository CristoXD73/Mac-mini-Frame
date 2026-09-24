import Cocoa
import SwiftUI

// Save Rewind: a controller-driven timeline of every save snapshot (taken automatically while
// playing and when a game closes). Pick a point in time and restore it. The current save is
// always snapshotted first ("before-restore"), so a rewind can itself be undone.
//
//   LB / RB or D-pad ◀ ▶   move through time        D-pad ▲ ▼   switch game
//   A                        restore (asks to confirm)  B           back / close

struct RewindSnapshot: Identifiable, Hashable {
    let id: String          // snapshot folder
    let time: Date
    let files: Int
    let kind: String        // auto | before-restore
}

struct RewindGroup: Identifiable {
    let id: String          // "Saved Games - Studio - Game"
    let snapshots: [RewindSnapshot]   // oldest → newest
    var title: String { id.components(separatedBy: " - ").last ?? id }
    var location: String { id.components(separatedBy: " - ").dropLast().joined(separator: " › ") }
}

enum Nav { case left, right, up, down, a, b }

@MainActor
final class RewindModel: ObservableObject {
    @Published var groups: [RewindGroup] = []
    @Published var group = 0
    @Published var index = 0
    @Published var confirming = false
    @Published var message: String?
    @Published var busy = false
    var gameRunning: () -> Bool = { false }

    var current: RewindGroup? { groups.indices.contains(group) ? groups[group] : nil }
    var snapshot: RewindSnapshot? { current.flatMap { $0.snapshots.indices.contains(index) ? $0.snapshots[index] : nil } }

    func load() {
        guard let tool = resource("backup-saves") else { return }
        let data = Data(capture(tool, ["--list-json"]).output.utf8)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { groups = []; return }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH-mm-ss"
        groups = arr.compactMap { g in
            guard let name = g["group"] as? String, let snaps = g["snapshots"] as? [[String: Any]] else { return nil }
            let list = snaps.compactMap { s -> RewindSnapshot? in
                guard let dir = s["dir"] as? String, let t = s["time"] as? String,
                      let date = fmt.date(from: String(t.prefix(19))) else { return nil }
                return RewindSnapshot(id: dir, time: date, files: s["files"] as? Int ?? 0, kind: s["kind"] as? String ?? "auto")
            }.sorted { $0.time < $1.time || ($0.time == $1.time && $0.id < $1.id) }
            return list.isEmpty ? nil : RewindGroup(id: name, snapshots: list)
        }.sorted { ($0.snapshots.last?.time ?? .distantPast) > ($1.snapshots.last?.time ?? .distantPast) }
        group = 0
        index = max(0, (current?.snapshots.count ?? 1) - 1)
    }

    /// Returns true when the screen should close.
    func handle(_ nav: Nav) -> Bool {
        if busy { return false }
        if message != nil { message = nil; return false }
        if confirming {
            switch nav {
            case .a: restore()
            case .b: confirming = false
            default: break
            }
            return false
        }
        switch nav {
        case .left: index = max(0, index - 1)
        case .right: index = min((current?.snapshots.count ?? 1) - 1, index + 1)
        case .up: group = max(0, group - 1); index = max(0, (current?.snapshots.count ?? 1) - 1)
        case .down: group = min(groups.count - 1, group + 1); index = max(0, (current?.snapshots.count ?? 1) - 1)
        case .a:
            guard snapshot != nil else { return false }
            if gameRunning() { message = "Quit the game first: it keeps its save in memory and would overwrite the rewind." }
            else { confirming = true }
        case .b: return true
        }
        return false
    }

    private func restore() {
        guard let snap = snapshot, let tool = resource("backup-saves") else { return }
        confirming = false
        busy = true
        DispatchQueue.global().async {
            let out = Data(capture(tool, ["--restore", snap.id]).output.utf8)
            let res = (try? JSONSerialization.jsonObject(with: out) as? [String: Any]) ?? [:]
            DispatchQueue.main.async {
                self.busy = false
                let ok = res["ok"] as? Bool ?? false
                self.message = ok ? "Restored. Your previous save was kept, so you can rewind back to it."
                                  : "Restore failed: \(res["error"] as? String ?? "unknown error"). Nothing was changed."
                self.load()
            }
        }
    }
}

struct RewindView: View {
    @ObservedObject var model: RewindModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.01, green: 0.02, blue: 0.06), Color(red: 0.03, green: 0.06, blue: 0.15)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Save Rewind", systemImage: "clock.arrow.circlepath").font(.system(size: 30, weight: .bold))
                    Spacer()
                    if model.groups.count > 1 { Text("\(model.group + 1) / \(model.groups.count)").foregroundStyle(.white.opacity(0.4)) }
                }
                .padding(.bottom, 50)

                if let g = model.current {
                    Text(g.location.uppercased()).font(.system(size: 14, weight: .semibold)).tracking(2).foregroundStyle(.white.opacity(0.4))
                    Text(g.title).font(.system(size: 52, weight: .bold, design: .rounded)).padding(.bottom, 70)
                    timeline(g)
                } else {
                    Spacer()
                    Text("No save snapshots yet.").font(.system(size: 30, weight: .semibold))
                    Text("They're taken automatically while you play and when a game closes.").foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                hints
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 90).padding(.vertical, 70)

            if model.confirming, let s = model.snapshot { dialog("Restore the save from \(label(s.time))?", "Your current save is kept, so you can rewind back to it.", "A  Restore     B  Cancel") }
            if let m = model.message { dialog(m, nil, "Press any button") }
            if model.busy { dialog("Restoring…", nil, nil) }
        }
        .ignoresSafeArea()
    }

    func timeline(_ g: RewindGroup) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            GeometryReader { geo in
                let n = g.snapshots.count
                let step = n > 1 ? geo.size.width / CGFloat(n - 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                    Capsule().fill(Color(red: 0.45, green: 0.65, blue: 1).opacity(0.7))
                        .frame(width: n > 1 ? step * CGFloat(model.index) : 0, height: 3)
                    ForEach(Array(g.snapshots.enumerated()), id: \.element.id) { i, s in
                        let sel = i == model.index
                        Circle()
                            .fill(s.kind == "before-restore" ? Color(red: 1, green: 0.75, blue: 0.4) : (sel ? .white : Color(red: 0.55, green: 0.7, blue: 1)))
                            .frame(width: sel ? 22 : 10, height: sel ? 22 : 10)
                            .shadow(color: Color(red: 0.4, green: 0.6, blue: 1).opacity(sel ? 0.9 : 0), radius: 14)
                            .position(x: n > 1 ? step * CGFloat(i) : geo.size.width / 2, y: 1.5)
                    }
                }
            }
            .frame(height: 24)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.index)

            if let s = model.snapshot {
                VStack(alignment: .leading, spacing: 8) {
                    Text(label(s.time)).font(.system(size: 34, weight: .semibold))
                    Text("\(s.files) file\(s.files == 1 ? "" : "s")\(s.kind == "before-restore" ? " · saved automatically before a rewind" : "")")
                        .foregroundStyle(.white.opacity(0.55)).font(.system(size: 19))
                    Text("\(model.index + 1) of \(g.snapshots.count)\(model.index == g.snapshots.count - 1 ? " · latest" : "")")
                        .foregroundStyle(.white.opacity(0.35)).font(.system(size: 16))
                }
            }
        }
    }

    var hints: some View {
        HStack(spacing: 34) {
            hint("LB RB", "Move through time"); hint("▲ ▼", "Switch game"); hint("A", "Restore"); hint("B", "Close")
        }
    }

    func hint(_ k: String, _ t: String) -> some View {
        HStack(spacing: 10) {
            Text(k).font(.system(size: 15, weight: .heavy)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.14)))
            Text(t).font(.system(size: 17)).foregroundStyle(.white.opacity(0.65))
        }
    }

    func dialog(_ title: String, _ sub: String?, _ keys: String?) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 14) {
                Text(title).font(.system(size: 28, weight: .semibold)).multilineTextAlignment(.center)
                if let sub { Text(sub).font(.system(size: 18)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center) }
                if let keys { Text(keys).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.45)).padding(.top, 10) }
            }
            .padding(46).frame(maxWidth: 760)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.05, green: 0.09, blue: 0.2)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.1)))
        }
    }

    func label(_ d: Date) -> String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true; f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }
}

@MainActor
final class RewindScreen {
    let model = RewindModel()
    private var window: NSWindow?
    var isOpen: Bool { window != nil }

    func open() {
        model.load()
        model.confirming = false; model.message = nil
        let screen = NSScreen.screens.first!
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        w.level = .modalPanel
        w.backgroundColor = .black
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: RewindView(model: model))
        w.setFrame(screen.frame, display: true)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()          // take focus so Big Picture doesn't also react to the controller
        window = w
        log("rewind opened (\(model.groups.count) save folders)")
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    /// Returns true if the screen closed.
    func handle(_ nav: Nav) -> Bool {
        if model.handle(nav) { close(); return true }
        return false
    }
}
