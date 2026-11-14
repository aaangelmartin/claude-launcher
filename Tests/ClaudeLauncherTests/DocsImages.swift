@testable import ClaudeLauncher
import AppKit
import SwiftUI
import Testing

/// the readme's images, drawn from the app's own views: a banner and each view framed on a warm
/// backdrop. runs only with DOCS_DIR set: DOCS_DIR=docs swift test --filter DocsImages
@MainActor
@Suite struct DocsImages {
    let dir = ProcessInfo.processInfo.environment["DOCS_DIR"]

    private func render<V: View>(_ name: String, _ view: V) {
        guard let dir else { return }
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    private static func sample(_ m: MainModel) {
        let home = FolderPath.home
        let now = Date()
        let titles = ["Add plan usage to the launcher", "Fuzzy project search", "Fix the effort slider", "Translate everything to English"]
        let sessions = (0..<4).map { SessionInfo(id: "s\($0)", title: titles[$0], updated: now.addingTimeInterval(-Double($0 + 1) * 5000)) }
        m.projects = [home + "/Developer/claude-launcher": ProjectInfo(path: home + "/Developer/claude-launcher", lastUsed: now.addingTimeInterval(-600), sessions: sessions, branch: "main")]
        m.usage = Usage(session: .init(percent: 17, resetsAt: now.addingTimeInterval(3960)), week: .init(percent: 64, resetsAt: now.addingTimeInterval(200_000)))
    }

    private static func running(_ m: MainModel) {
        let home = FolderPath.home
        let now = Date()
        m.live = [
            LiveSession(pid: 1, sessionId: "a", cwd: home + "/Developer/website", name: "Landing page copy", state: .waiting, waitingFor: nil, since: now.addingTimeInterval(-40)),
            LiveSession(pid: 2, sessionId: "b", cwd: home + "/Developer/claude-launcher", name: "Release notes", state: .busy, waitingFor: nil, since: now.addingTimeInterval(-300)),
            LiveSession(pid: 3, sessionId: "c", cwd: home + "/Developer/api", name: "Rate limiter", state: .busy, waitingFor: nil, since: now.addingTimeInterval(-90)),
            LiveSession(pid: 4, sessionId: "d", cwd: home + "/Developer/notes", name: "Weekly summary", state: .idle, waitingFor: nil, since: now.addingTimeInterval(-7200)),
        ]
    }

    @Test func images() {
        let running = MainModel(); running.reset(); Self.sample(running); Self.running(running); running.selected = 1
        render("running", Backdrop { MainView(model: running) })

        let folder = MainModel(); folder.reset(); Self.sample(folder); folder.live = []
        folder.text = "Developer/claude-launcher"; _ = folder.handle(.enter)
        render("folder", Backdrop { MainView(model: folder) })


        render("setup", Backdrop { OnboardingView(step: .welcome).environmentObject(KeyPress()) })
        render("banner", Banner())
    }
}

/// a warm dark ground with a glow of claude's orange behind the window, as the app sits on screen
private struct Backdrop<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
            .padding(.horizontal, 64)
            .padding(.vertical, 56)
            .background {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x1F1D1B), Color(hex: 0x141312)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color(hex: 0xD97757).opacity(0.22), .clear], center: .top, startRadius: 10, endRadius: 520)
                }
            }
    }
}

/// the readme's banner: the starburst, the name in anthropic serif, what it does, the wordmark
private struct Banner: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2B2826), Color(hex: 0x161514)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: 0xD97757).opacity(0.28), .clear], center: UnitPoint(x: 0.18, y: 0.3), startRadius: 0, endRadius: 560)
            VStack(alignment: .leading, spacing: 26) {
                ClaudeMark(color: Color(hex: 0xD97757)).frame(width: 72, height: 72)
                Text("Claude Launcher")
                    .font(ClaudeFonts.display(96))
                    .foregroundStyle(.white)
                Text("Your Claude Code sessions, one shortcut away.")
                    .font(ClaudeFonts.sans(34))
                    .foregroundStyle(Color(hex: 0xC2C0B6))
                HStack(spacing: 10) {
                    ForEach(["⌥", "C"], id: \.self) { key in
                        Text(key)
                            .font(ClaudeFonts.sans(26, .medium))
                            .foregroundStyle(.white)
                            .frame(minWidth: 56, minHeight: 56)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 110)
            Signature()
                .frame(height: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(48)
        }
        .frame(width: 1280, height: 640)
    }
}
