import AppKit
import KeyboardShortcuts
import SwiftUI

/// which keys are down while the setup is open, so its key caps can answer them
@MainActor
final class KeyPress: ObservableObject {
    @Published var modifiers: NSEvent.ModifierFlags = []
    /// the whole shortcut just went down
    @Published var shortcut = false
}

/// the first-run window, in the window's own look: what the app does, a check of what it needs,
/// the shortcut, and off you go. ⌘, in the window opens it again.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var monitor: Any?
    private let keys = KeyPress()
    /// the step shown, so the shortcut on the last one can finish
    private let state = OnboardingState()
    /// called when it is done (or closed): the window opens
    var onFinish: () -> Void = {}

    var isVisible: Bool { window?.isVisible == true }

    /// the shortcut pressed while the setup is open: its caps go down, and on the last step it opens
    /// the window
    func hotkey() {
        keys.shortcut = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self else { return }
            keys.shortcut = false
            if state.step == .done { finish() }
        }
    }

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = OnboardingView(finish: { [weak self] in self?.finish() }, state: state)
            .environmentObject(keys)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = KeyWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.keys.modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            return event
        }
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window?.orderOut(nil)
        window = nil
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        onFinish()
    }

    func windowWillClose(_ notification: Notification) { window = nil }

    static let doneKey = "didOnboard"
    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
}

/// borderless windows do not take the keys unless they say so
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// the step the setup is on, shared with its window
@MainActor
final class OnboardingState: ObservableObject {
    @Published var step: OnboardingView.Step

    init(step: OnboardingView.Step = .welcome) { self.step = step }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, checks, shortcut, done }

    var finish: () -> Void = {}
    @ObservedObject var state: OnboardingState
    private var step: Step { state.step }

    init(finish: @escaping () -> Void = {}, state: OnboardingState = OnboardingState()) {
        self.finish = finish
        self.state = state
    }

    /// for previews and snapshots: one step, nothing to finish
    init(step: Step) {
        self.init(state: OnboardingState(step: step))
    }
    private let theme = AppTheme.current

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep(theme: theme)
                case .checks: ChecksStep(theme: theme)
                case .shortcut: ShortcutStep(theme: theme)
                case .done: DoneStep(theme: theme)
                }
            }
            .id(step)
            .transition(.opacity.combined(with: .offset(x: 10)))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 330, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 30)

            Rectangle().fill(theme.divider).frame(height: 0.5)
            footer
        }
        .frame(width: 560)
        .background(LinearGradient(colors: [theme.gradientTop, theme.gradientBottom], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: MainView.radius))
        .overlay(RoundedRectangle(cornerRadius: MainView.radius).strokeBorder(theme.ring, lineWidth: 0.5))
        .animation(.easeOut(duration: 0.18), value: step)
    }

    /// the steps on the left, the buttons on the right, and the aaangelmartin wordmark centred in the
    /// room between them
    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Color.white.opacity(0.85) : Color.white.opacity(0.18))
                        .frame(width: s == step ? 16 : 6, height: 6)
                }
            }
            Spacer(minLength: 12)
            Signature().frame(height: 11)
            Spacer(minLength: 12)
            if step != .welcome {
                Button(theme.say("Back")) { move(-1) }
                    .buttonStyle(QuietButtonStyle(theme: theme))
                    .keyboardShortcut(.cancelAction)
            }
            Button(theme.say(step == .done ? "Get started" : "Continue")) {
                if step == .done { finish() } else { move(1) }
            }
            .buttonStyle(BrandButtonStyle(theme: theme))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
    }

    private func move(_ by: Int) {
        if let next = Step(rawValue: step.rawValue + by) { state.step = next }
    }
}

// MARK: steps

private struct StepTitle: View {
    let title: String
    let line: String
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(theme.say(title)).font(ClaudeFonts.display(28)).foregroundStyle(theme.text)
            Text(theme.say(line)).font(theme.row).foregroundStyle(theme.textSecondary)
        }
    }
}

private struct WelcomeStep: View {
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                ClaudeMark(color: theme.mark).frame(width: 34, height: 34)
                StepTitle(title: "Claude Launcher", line: "Your Claude Code sessions, one shortcut away.", theme: theme)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("circle.dashed", "Running sessions", "Every session at a glance, and what it needs from you. ↵ takes you to its window.")
                feature("folder", "Any folder", "Type a folder to start a new session there, or to resume one of its past ones.")
                feature("folder.badge.plus", "New projects", "Type a name that is no folder yet, and Claude starts in a fresh one.")
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ line: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 34)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(theme.say(title)).font(theme.row).foregroundStyle(theme.text)
                Text(theme.say(line)).font(theme.label).foregroundStyle(theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ChecksStep: View {
    let theme: AppTheme
    @State private var claude = Setup.claudeCode()
    @State private var terminal = Setup.terminal()
    @State private var signIn = Setup.signIn()
    @State private var claudeApp = Setup.claudeApp()
    @State private var atLogin = Setup.startsAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                StepTitle(title: "Check your setup", line: "What Claude Launcher needs, and what it is better with.", theme: theme)
                Spacer()
                Button(theme.say("Check again")) { refresh() }
                    .buttonStyle(QuietButtonStyle(theme: theme))
            }
            VStack(spacing: 2) {
                row("Claude Code", claude) {
                    if case .missing = claude {
                        Link(theme.say("Get it"), destination: URL(string: "https://claude.com/claude-code")!)
                            .font(theme.label)
                    }
                }
                row("Control Terminal", terminal) {
                    if case .ok = terminal {} else {
                        Button(theme.say("Allow")) { terminal = Setup.askForTerminal() }
                            .buttonStyle(QuietButtonStyle(theme: theme))
                    }
                }
                row("Claude Code sign-in", signIn) { EmptyView() }
                row("Claude app", claudeApp) { EmptyView() }
                row("Start at login", atLogin ? .ok("Ready whenever you log in") : .optional("Open it yourself after logging in")) {
                    Toggle("", isOn: Binding(get: { atLogin }, set: { Setup.setStartsAtLogin($0); atLogin = Setup.startsAtLogin }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }
        }
    }

    private func refresh() {
        claude = Setup.claudeCode()
        terminal = Setup.terminal()
        signIn = Setup.signIn()
        claudeApp = Setup.claudeApp()
        atLogin = Setup.startsAtLogin
    }

    private func row<Action: View>(_ name: String, _ state: Setup.State, @ViewBuilder action: () -> Action) -> some View {
        let (icon, colour, line): (String, Color, String) = switch state {
        case let .ok(l): ("checkmark.circle.fill", Color(CC.success), l)
        case let .missing(l): ("exclamationmark.circle.fill", Color(CC.warning), l)
        case let .optional(l): ("minus.circle", theme.textMuted, l)
        case let .later(l): ("clock", theme.textMuted, l)
        }
        return HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(colour).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.say(name)).font(theme.row).foregroundStyle(theme.text)
                Text(theme.say(line)).font(theme.label).foregroundStyle(theme.textMuted)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ShortcutStep: View {
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            StepTitle(title: "Your shortcut", line: "Press it anywhere to bring up Claude Launcher. Press it again to start a session at once.", theme: theme)
            HStack {
                Spacer()
                KeyboardShortcuts.Recorder(for: .openClaude)
                    .controlSize(.large)
                Spacer()
            }
            .padding(.vertical, 26)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            Text(theme.say("Click the field and press the keys you want. ⌥C works well with one hand."))
                .font(theme.label)
                .foregroundStyle(theme.textMuted)
        }
    }
}

private struct DoneStep: View {
    let theme: AppTheme
    @EnvironmentObject private var keys: KeyPress

    /// a cap is down while its modifier is held, or with the whole shortcut
    private func isDown(_ key: String) -> Bool {
        if keys.shortcut { return true }
        switch key {
        case "⌘": return keys.modifiers.contains(.command)
        case "⌥": return keys.modifiers.contains(.option)
        case "⌃": return keys.modifiers.contains(.control)
        case "⇧": return keys.modifiers.contains(.shift)
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            ClaudeMark(color: theme.mark).frame(width: 38, height: 38)
            Text(theme.say("You're set")).font(ClaudeFonts.display(30)).foregroundStyle(theme.text)
            HStack(spacing: 8) {
                ForEach(Array(shortcutKeys.enumerated()), id: \.offset) { _, key in
                    let down = isDown(key)
                    Text(key)
                        .font(ClaudeFonts.sans(18, .medium))
                        .foregroundStyle(down ? Color.white : theme.text)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 6)
                        .background(down ? theme.brandFill.opacity(0.85) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(down ? theme.brandFillHover : Color.white.opacity(0.1), lineWidth: down ? 1 : 0.5))
                        .shadow(color: .black.opacity(down ? 0 : 0.35), radius: down ? 0 : 1.5, y: down ? 0 : 2)
                        .scaleEffect(down ? 0.94 : 1)
                        .offset(y: down ? 1.5 : 0)
                        .animation(.easeOut(duration: 0.08), value: down)
                }
            }
            Text(theme.say("Press it now, or anytime. ⌘, brings this setup back."))
                .font(theme.row)
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity)
    }

    /// the shortcut, a cap per key: "⌥", "C"
    private var shortcutKeys: [String] {
        let text = KeyboardShortcuts.getShortcut(for: .openClaude)?.description ?? "⌥C"
        return text.map(String.init)
    }
}

// MARK: buttons

private struct BrandButtonStyle: ButtonStyle {
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.buttonFont)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(configuration.isPressed ? theme.brandFillHover : theme.brandFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.buttonFont)
            .foregroundStyle(theme.textRow)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}
