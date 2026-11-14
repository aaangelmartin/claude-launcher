import AppKit
import SwiftUI

/// a floating panel as claude's quick entry opens it: transparent, shadowed, above everything at
/// pop-up-menu level, dragged by its background. esc or a click outside closes it. it never activates
/// the app, so whatever was in front stays in front when it closes.
final class Panel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: MainView.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        // the shadow is drawn in swiftui, so it follows the card while it grows and shrinks
        hasShadow = false
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// the field's editor is swiftui's own (it must stay its type); only its colours change: a caret in
    /// the theme's colour (white for claude, as its quick entry draws it) and the system's selection
    /// colour, so selected text never turns invisible
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        let editor = super.fieldEditor(createFlag, for: object)
        Self.style(editor)
        return editor
    }

    static func style(_ editor: NSText?) {
        guard let editor = editor as? NSTextView else { return }
        editor.insertionPointColor = NSColor(AppTheme.current.caret)
        editor.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel = Panel()
    private let model = MainModel()
    private let hosting: NSHostingController<Stage>
    private var keyMonitor: Any?
    /// reads the active sessions again while the window is open, so their states stay current
    private var liveTimer: Timer?
    /// true while the code, not the user, moves the panel
    private var isPlacing = false
    private static let placeKey = "barTopLeft"

    override init() {
        hosting = NSHostingController(rootView: Stage(model: model))
        super.init()
        // the window keeps one size, tall enough for the card at its largest; the card grows and shrinks
        // inside it, animated, and the clear rest lets clicks through
        hosting.sizingOptions = []
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
        panel.contentViewController = hosting
        panel.delegate = self

        model.onOpen = { [weak self] raw, args in self?.open(raw, args: args) }
        model.onClose = { [weak self] in self?.hide() }
        model.onFocus = { [weak self] session in self?.focus(session) }
        model.caretAtEnd = { [panel] in
            guard let editor = panel.fieldEditor(false, for: nil) as? NSTextView else { return true }
            let range = editor.selectedRange()
            return range.length == 0 && range.location >= (editor.string as NSString).length
        }
    }

    var isVisible: Bool { panel.isVisible }
    /// ⌘, in the window: the setup again
    var onSetup: () -> Void = {}

    /// the hotkey: the first press opens the window, a second press while it is open acts as enter,
    /// so pressing it twice opens claude in the home folder straight away
    func hotkey() { isVisible ? model.hotkeyAgain() : show() }

    func show(keepingNotice: Bool = false) {
        if !keepingNotice { model.reset() }
        hosting.view.layoutSubtreeIfNeeded()
        position()
        panel.makeKeyAndOrderFront(nil) // no fade: claude's quick entry just appears
        NotificationCenter.default.post(name: .windowDidShow, object: nil)
        installKeyMonitor()
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshLive() }
        }
        // swiftui sets the editor up when the field takes focus: colour it once that has happened
        DispatchQueue.main.async { [panel] in Panel.style(panel.fieldEditor(false, for: nil)) }
    }

    func hide() {
        liveTimer?.invalidate()
        liveTimer = nil
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    // a click anywhere else takes the key away: that closes the window
    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { hide() }
    }

    // dragged by hand: remember where, as claude's quick entry does
    func windowDidMove(_ notification: Notification) {
        guard !isPlacing, panel.isVisible else { return }
        let card = Stage.card(in: panel.frame)
        UserDefaults.standard.set([card.minX, card.maxY], forKey: Self.placeKey)
    }

    // MARK: opening

    /// to a running session: its terminal tab or the app it runs in
    private func focus(_ session: LiveSession) {
        hide()
        if !LiveSessions.focus(session) {
            model.notice = .windowNotFound(session.name)
            show(keepingNotice: true)
        }
    }

    private func open(_ raw: String, args: [String]) {
        hide() // out of the way of macOS's permission prompt, and of terminal
        switch Terminal.run(FolderPath.command(for: raw, args: args)) {
        case .success:
            if FolderPath.isDirectory(FolderPath.resolve(raw)) { Recents.add(raw) }
        case .failure(.notAllowed):
            model.notice = .notAllowed
            show(keepingNotice: true)
        case let .failure(.other(message)):
            model.notice = .failed(message)
            show(keepingNotice: true)
        }
    }

    // MARK: keys

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command), event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
            return true
        }
        if mods.contains(.command), event.charactersIgnoringModifiers == "n" {
            return model.handle(.createFolder)
        }
        if mods.contains(.command), event.charactersIgnoringModifiers == "," {
            hide()
            onSetup()
            return true
        }
        if mods.contains(.command), event.charactersIgnoringModifiers == "w" {
            hide()
            return true
        }
        let command = mods.contains(.command)
        let option = mods.contains(.option)
        let key: MainModel.Key
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = command ? .openNew : .enter
        case 48: key = .tab
        case 49: key = .space
        case 125: key = option ? .optionsDown : command ? .jumpDown : .down
        case 126: key = option ? .optionsUp : command ? .jumpUp : .up
        case 123 where !command: key = .left
        case 124 where !command: key = .right
        default: return false
        }
        return model.handle(key)
    }

    // MARK: layout

    /// where the user last dragged the card, if that is still on a screen. otherwise as claude places its
    /// quick entry: centred on the main display, its 470 pt window centred vertically, the bar at its top.
    private func position() {
        let width = MainView.width
        var topLeft: NSPoint
        if let saved = UserDefaults.standard.array(forKey: Self.placeKey) as? [CGFloat], saved.count == 2,
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(NSPoint(x: saved[0] + width / 2, y: saved[1] - 1)) }) {
            topLeft = NSPoint(x: saved[0], y: saved[1])
        } else {
            guard let area = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame else { return }
            topLeft = NSPoint(x: area.minX + (area.width - width) / 2, y: area.maxY - (area.height - 470) / 2)
        }
        isPlacing = true
        panel.setFrame(Stage.frame(cardTopLeft: topLeft), display: true)
        isPlacing = false
    }
}

/// the window's content: the card at the top, a clear margin round it for its shadow.
struct Stage: View {
    @ObservedObject var model: MainModel

    static let side: CGFloat = 40
    static let top: CGFloat = 24
    static let height: CGFloat = 820

    static func frame(cardTopLeft p: NSPoint) -> NSRect {
        NSRect(x: p.x - side, y: p.y + top - height, width: MainView.width + side * 2, height: height)
    }

    static func card(in frame: NSRect) -> NSRect {
        NSRect(x: frame.minX + side, y: frame.maxY - top, width: MainView.width, height: 0)
    }

    var body: some View {
        MainView(model: model)
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.38), radius: 22, y: 14)
            .padding(.horizontal, Self.side)
            .padding(.top, Self.top)
            .frame(width: MainView.width + Self.side * 2, height: Self.height, alignment: .top)
    }
}

enum Permissions {
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
