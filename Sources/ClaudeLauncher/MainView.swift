import AppKit
import LaaabsKit
import SwiftUI

/// the window, built as claude desktop's quick entry: one 56 pt bar with the starburst in a 56 pt
/// cell and the field beside it, no field border, no focus ring. folders (recent while empty, matching
/// while typing) open under a hairline inside the same card and scroll past seven. at the bottom, the
/// launch options: one summary line that opens into four rows, each changed with ← →.
struct MainView: View {
    @ObservedObject var model: MainModel
    @FocusState private var fieldFocused: Bool
    /// the lit row's light: one shape that glides from row to row
    @Namespace private var lit
    /// the window comes in with a short fade and a hint of scale
    @State private var shown = false
    private let theme = AppTheme.current

    /// claude's quick entry window is 606 wide; its bar fills it
    static let width: CGFloat = 606
    static let radius: CGFloat = 16
    static let barHeight: CGFloat = 56
    static let rowHeight: CGFloat = 36
    static let visibleRows = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar

            if let notice = model.notice {
                divider
                noticeView(notice)
            }

            divider
            Group {
                switch model.moment {
                case .running:
                    if model.live.isEmpty {
                        hint("No sessions running. Type a folder to start one.")
                    } else {
                        RunningList(model: model, theme: theme)
                    }
                case .folders:
                    if !model.rows.isEmpty { rowsView }
                    if let path = model.newFolder, let index = model.newFolderIndex {
                        // a name that is no folder yet: make it, for a new project
                        NewFolderLine(model: model, index: index, path: path, theme: theme)
                            .padding(.bottom, 8)
                    } else if model.rows.isEmpty, let folder = model.typedFolder {
                        hint("↵  Open \(folder.isEmpty ? "~" : folder)")
                    } else if model.rows.isEmpty {
                        hint("No folder matches.")
                    }
                case .step:
                    StepList(model: model, theme: theme)
                }
            }
            // a folder slides in from the right; going back, it fades
            .id(model.moment == .step ? "step:\(model.stepFolder ?? "")" : model.moment == .running ? "running" : "folders")
            .transition(model.moment == .step
                        ? .asymmetric(insertion: .opacity.combined(with: .offset(x: 12)), removal: .opacity)
                        : .opacity)

            // how a session starts, where one does
            // in a folder, the launch options open under the list (⌥↓, or a click on a value on the
            // New session line); folded they take no room
            if model.moment == .step {
                OptionsSection(model: model, theme: theme)
            }
            // the keys that act here, and the plan's use, everywhere
            divider
            CommandBar(model: model, theme: theme)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        // the card grows and shrinks smoothly as what it shows changes
        .animation(.easeOut(duration: 0.18), value: model.moment)
        .animation(.easeOut(duration: 0.18), value: model.stepFolder)
        .animation(.easeOut(duration: 0.1), value: model.selected)
        .environment(\.litNamespace, lit)
        .background(
            LinearGradient(colors: [theme.gradientTop, theme.gradientBottom], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.radius))
        .overlay(RoundedRectangle(cornerRadius: Self.radius).strokeBorder(theme.ring, lineWidth: 0.5))
        .opacity(shown ? 1 : 0)
        .onAppear { fieldFocused = true; appear() }
        .onReceive(NotificationCenter.default.publisher(for: .windowDidShow)) { _ in fieldFocused = true; appear() }
    }

    private func appear() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { shown = false }
        withAnimation(.easeOut(duration: 0.1)) { shown = true }
    }

    // MARK: the bar

    private var bar: some View {
        HStack(spacing: 0) {
            ClaudeMark(color: theme.mark)
                .frame(width: 18, height: 18)
                .frame(width: Self.barHeight, height: Self.barHeight)
            TextField(
                "", text: $model.text,
                prompt: Text(theme.say(placeholder)).foregroundStyle(theme.placeholder)
            )
            .textFieldStyle(.plain)
            .font(theme.input)
            .foregroundStyle(theme.text)
            .focused($fieldFocused)
            .autocorrectionDisabled()
            .frame(height: 24)
            .padding(.trailing, 12)
            // a quiet signature: the aaangelmartin wordmark, drawn from its own vector, never typed
            Signature()
                .frame(height: 11)
                .padding(.trailing, 20)
                .allowsHitTesting(false)
        }
        .frame(height: Self.barHeight)
    }

    private var placeholder: String { "Launch Claude in…" }

    private func hint(_ line: String) -> some View {
        Text(theme.say(line))
            .font(theme.label)
            .foregroundStyle(theme.textMuted)
            .padding(.leading, Self.barHeight)
            .frame(height: 40)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(height: 0.5)
    }

    // MARK: folders

    private var rowsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Folders", hint: "", theme: theme)
            FolderList(model: model, theme: theme)
                // a new list (typing, tab) is a new scroll view: it always starts at the top, same margins
                .id(model.listID)
                .transition(.identity)
        }
    }

    // MARK: permission notice

    private func noticeView(_ notice: MainModel.Notice) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(theme.icon)
                .frame(width: Self.barHeight)
            Group {
                switch notice {
                case .notAllowed: Text(theme.say("Claude Launcher needs permission to control Terminal."))
                case let .failed(message): Text(theme.say("Terminal did not respond: ") + message)
                case let .windowNotFound(name): Text(theme.say("Could not find the window of \(name)."))
                }
            }
            .font(theme.row)
            .foregroundStyle(theme.textRow)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if notice == .notAllowed {
                Button(theme.say("Open Settings")) { Permissions.openAutomationSettings() }
                    .buttonStyle(ClaudeButtonStyle(theme: theme))
            }
        }
        .padding(.vertical, 12)
        .padding(.trailing, 14)
    }
}

/// the folders under the bar: seven rows tall, then it scrolls, with a thin thumb of its own (no system
/// track) and soft edges where there is more to see.
private struct FolderList: View {
    @ObservedObject var model: MainModel
    let theme: AppTheme
    /// where the pointer was when this list appeared: a row under a pointer that has not moved is not
    /// picked, only one the pointer moves onto
    @State private var pointerAtStart = NSEvent.mouseLocation

    @State private var metrics = ScrollMetrics()
    @State private var thumbVisible = false
    @State private var hideThumb: Task<Void, Never>?
    @State private var pointerInside = false

    private static let padding: CGFloat = 6
    private static let fade: CGFloat = 18
    private static let topID = -1
    private static let endID = Int.max
    private var rowHeight: CGFloat { MainView.rowHeight }
    private var visibleHeight: CGFloat {
        CGFloat(min(model.rows.count, MainView.visibleRows)) * rowHeight + Self.padding * 2
    }
    private var overflows: Bool { model.rows.count > MainView.visibleRows }
    private var columns: (time: Bool, sessions: Bool) {
        let infos = model.rows.compactMap { model.info(for: $0) }
        return (infos.contains { $0.lastUsed != nil }, infos.contains { !$0.sessions.isEmpty })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: Self.padding).id(Self.topID)
                    ForEach(Array(model.rows.enumerated()), id: \.element) { index, row in
                        FolderRow(
                            row: row, prefix: model.typedParent, theme: theme,
                            isSelected: index == model.selected,
                            info: model.info(for: row),
                            columns: columns
                        )
                        .id(index)
                        .onContinuousHover { phase in
                            guard case .active = phase, NSEvent.mouseLocation != pointerAtStart else { return }
                            model.point(at: index)
                        }
                        .onTapGesture { model.open(row: row) }
                    }
                    Color.clear.frame(height: Self.padding).id(Self.endID)
                }
            }
            .scrollIndicators(.never)
            .modifier(TrackScroll(metrics: $metrics, onScroll: flashThumb))
            .frame(height: visibleHeight)
            .mask(edgeFade)
            .overlay(alignment: .topTrailing) { thumb }
            .onHover { inside in
                pointerInside = inside
                if inside { flashThumb() }
            }
            .onChange(of: model.selected) { old, selected in
                guard let selected, !model.selectedByPointer else { return }
                reveal(selected, movingDown: (old ?? -1) < selected, proxy: proxy)
            }
        }
    }

    /// scrolls only when the picked row is not fully clear of the soft edges, and then leaves the next
    /// row peeking past it, as a native list does
    private func reveal(_ index: Int, movingDown: Bool, proxy: ScrollViewProxy) {
        guard overflows else { return }
        let top = Self.padding + CGFloat(index) * rowHeight
        let clearTop = metrics.offset + (metrics.offset > 1 ? Self.fade : 0)
        let clearBottom = metrics.offset + metrics.container - Self.fade
        guard top < clearTop || top + rowHeight > clearBottom else { return }
        let below = top + rowHeight > clearBottom
        if below {
            proxy.scrollTo(index + 1 < model.rows.count ? index + 1 : Self.endID, anchor: .bottom)
        } else {
            proxy.scrollTo(index > 0 ? index - 1 : Self.topID, anchor: .top)
        }
        flashThumb()
    }

    // MARK: soft edges

    private var edgeFade: some View {
        let fade = Self.fade
        let top = overflows && metrics.offset > 1
        let bottom = overflows && metrics.offset < metrics.content - metrics.container - 1
        return VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(top ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(bottom ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
        }
        .animation(.easeOut(duration: 0.15), value: top)
        .animation(.easeOut(duration: 0.15), value: bottom)
    }

    // MARK: the thumb

    @ViewBuilder private var thumb: some View {
        if overflows, metrics.content > metrics.container, metrics.container > 0 {
            let inset: CGFloat = 6
            let track = metrics.container - inset * 2
            let height = max(28, track * metrics.container / metrics.content)
            let travel = track - height
            let progress = min(max(metrics.offset / (metrics.content - metrics.container), 0), 1)
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 5, height: height)
                .offset(x: -4, y: inset + travel * progress)
                .opacity(thumbVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: thumbVisible)
                .allowsHitTesting(false)
        }
    }

    /// show the thumb, then hide it a moment after the list stops moving (unless the pointer is on it)
    private func flashThumb() {
        guard overflows else { return }
        thumbVisible = true
        hideThumb?.cancel()
        hideThumb = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            if !pointerInside { thumbVisible = false }
        }
    }
}

struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var container: CGFloat = 0
}

/// reads where the list is scrolled (macOS 15 and later; earlier, no thumb and no fades)
private struct TrackScroll: ViewModifier {
    @Binding var metrics: ScrollMetrics
    let onScroll: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                ScrollMetrics(offset: geo.contentOffset.y + geo.contentInsets.top,
                              content: geo.contentSize.height, container: geo.containerSize.height)
            } action: { old, new in
                metrics = new
                if old.offset != new.offset, old.content == new.content { onScroll() }
            }
        } else {
            content
        }
    }
}

/// one folder: the part already typed dimmed, the folder's own name in full.
private struct FolderRow: View {
    let row: String
    let prefix: String
    let theme: AppTheme
    let isSelected: Bool
    /// its branch, when it was last used and its claude sessions, for a known project
    var info: ProjectInfo?
    /// which columns the list shows (any of its rows has them)
    var columns: (time: Bool, sessions: Bool) = (true, true)

    var body: some View {
        let (parent, name) = split
        HStack(spacing: 0) {
            // the icon sits in the starburst's column, the name lines up with what is typed
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? theme.text : theme.icon)
                .frame(width: MainView.barHeight - 16)
                .padding(.trailing, 8)
            (Text(parent).foregroundStyle(theme.textMuted)
                + Text(name.hasSuffix("/") ? String(name.dropLast()) : name) // the trailing slash is for tab, not for reading
                    .foregroundStyle(isSelected ? theme.text : theme.textRow))
                .font(theme.row)
                .lineLimit(1)
                .truncationMode(.head)
                .layoutPriority(1)
            Spacer(minLength: 12)
            if let info { meta(info) }
        }
        .padding(.trailing, 12)
        .frame(height: MainView.rowHeight)
        .background { if isSelected { LitRow(theme: theme) } }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// on the right, in columns that line up from row to row: the branch, how long ago it was used,
    /// and its sessions (click, or → when lit)
    private func meta(_ info: ProjectInfo) -> some View {
        HStack(spacing: 14) {
            if let branch = info.branch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9.5))
                    Text(branch).lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: 150, alignment: .trailing)
            }
            // a column only when some row of the list fills it, so nothing sits empty
            if columns.time {
                Text(info.lastUsed.map { Ago.long($0) } ?? "")
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }
            if columns.sessions {
                Text(info.sessions.isEmpty ? "" : info.sessions.count == 1 ? "1 session" : "\(info.sessions.count) sessions")
                    .monospacedDigit()
                    .frame(width: 74, alignment: .trailing)
            }
        }
        .font(theme.label)
        .foregroundStyle(theme.textMuted.opacity(0.8))
        .lineLimit(1)
    }

    /// "Developer/Priv8/" with "Developer/" typed: ("Developer/", "Priv8/"). recents have no typed
    /// part, so their own parent folders are dimmed instead.
    private var split: (String, String) {
        if !prefix.isEmpty, row.hasPrefix(prefix) { return (prefix, String(row.dropFirst(prefix.count))) }
        let trimmed = row.hasSuffix("/") ? String(row.dropLast()) : row
        guard let slash = trimmed.lastIndex(of: "/") else { return ("", row) }
        return (String(row[...slash]), String(row[row.index(after: slash)...]))
    }
}

private struct ClaudeButtonStyle: ButtonStyle {
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.buttonFont)
            .foregroundStyle(theme.buttonText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(theme.button.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// the aaangelmartin wordmark from its vector (the one aaangelmartin.com serves), white at a whisper
struct Signature: View {
    private static let image: NSImage? = {
        let bundled = Bundle.main.url(forResource: "aaangelmartin", withExtension: "svg")
        // running from the package (tests, previews): the file next to the sources
        let local = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/aaangelmartin.svg").standardized
        guard let url = bundled ?? (FileManager.default.fileExists(atPath: local.path) ? local : nil),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.white.opacity(0.28))
        }
    }
}

/// the starburst, from the path claude's quick entry draws.
struct ClaudeMark: View {
    let color: Color

    private static let image: NSImage? = {
        let bundled = Bundle.main.url(forResource: "claude", withExtension: "svg")
        // running from the package (tests, the readme's images): the file next to the sources
        let local = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/claude.svg").standardized
        guard let url = bundled ?? (FileManager.default.fileExists(atPath: local.path) ? local : nil),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().renderingMode(.template)
            } else {
                Image(systemName: "sparkle").resizable()
            }
        }
        .aspectRatio(contentMode: .fit)
        .foregroundStyle(color)
    }
}



/// a line of a list: an icon in the starburst's column, a title, its folder dimmed, something on the
/// right; lit by the keys or the pointer
private struct ListLine: View {
    @ObservedObject var model: MainModel
    let index: Int
    let icon: AnyView
    let title: String
    let folder: String?
    let trailing: AnyView
    let theme: AppTheme

    var body: some View {
        let on = index == model.selected
        HStack(spacing: 0) {
            icon
                .frame(width: MainView.barHeight - 16)
                .padding(.trailing, 8)
            Text(title)
                .font(theme.row)
                .foregroundStyle(on ? theme.text : theme.textRow)
                .lineLimit(1)
                .layoutPriority(1)
            if let folder {
                let shown = FolderPath.display(folder)
                Text(shown.isEmpty ? "~" : shown)
                    .font(theme.label)
                    .foregroundStyle(theme.textMuted.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.leading, 10)
            }
            Spacer(minLength: 12)
            trailing.font(theme.label).lineLimit(1)
        }
        .padding(.trailing, 12)
        .frame(height: MainView.rowHeight)
        .background { if on { LitRow(theme: theme) } }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .id(index)
        .onContinuousHover { phase in if case .active = phase { model.point(at: index) } }
        .onTapGesture { model.act(on: index) }
    }
}

/// a scrolling list that keeps the lit line in sight
private struct ScrollingList<Content: View>: View {
    @ObservedObject var model: MainModel
    let lines: Int
    /// room for a section label among the lines
    var labelled = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(.bottom, 6)
            }
            .scrollIndicators(.never)
            .frame(height: CGFloat(min(lines, 10)) * MainView.rowHeight + (labelled ? 28 : 0) + 6)
            .onChange(of: model.selected) { _, i in
                guard let i, !model.selectedByPointer else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(i) }
            }
        }
    }
}

/// a folder that does not exist yet, to start a new project in: its own section, a line like the
/// others. enter, the shortcut or ⌘N make it and start claude in it
private struct NewFolderLine: View {
    @ObservedObject var model: MainModel
    let index: Int
    let path: String
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "New project", hint: "", theme: theme)
            ListLine(model: model, index: index,
                     icon: AnyView(Image(systemName: "folder.badge.plus").font(.system(size: 13)).foregroundStyle(theme.icon)),
                     title: theme.say("Create folder"), folder: path,
                     trailing: AnyView(Text(theme.say("Create and start")).foregroundStyle(theme.textMuted.opacity(0.8))),
                     theme: theme)
        }
    }
}

/// the bottom bar, the same everywhere: on the left what the keys do here, following what is lit;
/// on the right the plan's use
private struct CommandBar: View {
    @ObservedObject var model: MainModel
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 22) {
                ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                    KeyHint(keys: [hint.key], label: hint.label, theme: theme).help(hint.help)
                }
            }
            .padding(.leading, 8)
            .layoutPriority(0)
            Spacer(minLength: 24)
            if let usage = model.usage {
                UsageLine(usage: usage, theme: theme).layoutPriority(1)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(height: 40)
        .animation(.easeOut(duration: 0.12), value: model.moment)
    }

    private struct Hint { let key: String; let label: String; let help: String }

    private var hints: [Hint] {
        let lit = model.selected
        let shortcut = OptionsSection.shortcutText
        switch model.moment {
        case .running:
            var list: [Hint] = []
            if !model.live.isEmpty {
                list.append(lit == nil
                    ? Hint(key: "↓", label: "Choose", help: "Highlight a running session")
                    : Hint(key: "↵", label: "Open", help: "Go to the session's window"))
            }
            list.append(Hint(key: "⌘↵", label: "New session", help: lit == nil
                ? "Start a new session in your home folder (or press \(shortcut))"
                : "Start a new session in that session's folder (or press \(shortcut))"))
            return list
        case .folders:
            let creating = lit != nil && lit == model.newFolderIndex
            var list = [creating
                ? Hint(key: "↵", label: "Create", help: "Create the folder and start Claude in it")
                : Hint(key: "↵", label: "Open", help: "Open the folder to start or resume a session")]
            if model.newFolder != nil {
                list.append(Hint(key: "⌘N", label: "New folder", help: "Create the folder typed and start Claude in it"))
            } else {
                list.append(Hint(key: "⌘↵", label: "New session", help: "Start a new session there at once (or press \(shortcut))"))
            }
            return list
        case .step:
            let items = model.stepItems
            let label: String = switch lit.flatMap({ items.indices.contains($0) ? items[$0] : nil }) {
            case .running: "Go to"
            case .past: "Resume"
            default: "Start"
            }
            return [Hint(key: "↵", label: label, help: "Start, go to or resume the highlighted line"),
                    Hint(key: "⌥↓", label: "Options", help: "Model, effort and permissions for the new session"),
                    Hint(key: "esc", label: "Back", help: "Back to the folders")]
        }
    }
}

/// what opens first: every claude code session running now, with its state as claude's code view
/// shows it. enter goes to one.
private struct RunningList: View {
    @ObservedObject var model: MainModel
    let theme: AppTheme

    var body: some View {
        ScrollingList(model: model, lines: model.live.count) {
            SectionLabel(title: "Running", hint: "", theme: theme)
            ForEach(Array(model.live.enumerated()), id: \.element.id) { i, s in
                ListLine(model: model, index: i, icon: AnyView(StateDot(state: s.state)), title: s.name, folder: s.cwd,
                         trailing: AnyView(HStack(spacing: 12) {
                             Text(StateWords.label(s.state)).foregroundStyle(StateWords.colour(s.state, theme))
                             Text(Ago.long(s.since)).monospacedDigit().foregroundStyle(theme.textMuted.opacity(0.8))
                                 .frame(width: 58, alignment: .trailing)
                         }), theme: theme)
            }
        }
    }
}

/// a folder's step: a new session (lit), the sessions running there, then its past ones to resume
private struct StepList: View {
    @ObservedObject var model: MainModel
    let theme: AppTheme

    var body: some View {
        let items = model.stepItems
        let folder = model.stepFolder ?? ""
        let shown = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 9.5, weight: .semibold))
                Text(shown.isEmpty ? "~" : shown).foregroundStyle(theme.textRow)
                if let branch = model.info(for: folder)?.branch {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9.5)).padding(.leading, 6)
                    Text(branch)
                }
                Spacer()
            }
            .font(theme.label)
            .foregroundStyle(theme.textMuted)
            .padding(.leading, 22)
            .padding(.trailing, 20)
            .frame(height: 32)
            .contentShape(Rectangle())
            .onTapGesture { model.closeStep() }

            ScrollingList(model: model, lines: items.count, labelled: items.count > 1) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    switch item {
                    case .new:
                        ListLine(model: model, index: i, icon: AnyView(Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textRow)),
                                 title: theme.say("New session"), folder: nil,
                                 trailing: AnyView(LaunchSummary(model: model, theme: theme, lit: model.selected == i)), theme: theme)
                        if items.count > 1 {
                            SectionLabel(title: "Sessions", hint: "", theme: theme)
                        }
                    case let .running(s):
                        ListLine(model: model, index: i, icon: AnyView(StateDot(state: s.state)), title: s.name, folder: nil,
                                 trailing: AnyView(Text(StateWords.label(s.state)).foregroundStyle(StateWords.colour(s.state, theme))), theme: theme)
                    case let .past(s):
                        ListLine(model: model, index: i, icon: AnyView(Image(systemName: "clock.arrow.circlepath").font(.system(size: 11.5)).foregroundStyle(theme.icon)),
                                 title: s.title, folder: nil,
                                 trailing: AnyView(Text(Ago.long(s.updated)).monospacedDigit().foregroundStyle(theme.textMuted.opacity(0.8))), theme: theme)
                    }
                }
            }
        }
    }
}

/// the words claude's code view filters sessions by, and their colours
enum StateWords {
    static func label(_ state: LiveSession.State) -> String {
        switch state {
        case .busy: "Working"
        case .waiting: "Needs input"
        case .idle: "Completed"
        }
    }

    /// needs input in claude code's warning yellow, working in the text colour, completed dimmed
    static func colour(_ state: LiveSession.State, _ theme: AppTheme) -> Color {
        switch state {
        case .busy: theme.textRow
        case .waiting: Color(CC.warning)
        case .idle: theme.textMuted.opacity(0.75)
        }
    }
}

/// a session's state with the icons of claude's code view: a raised hand for needs input, a turning
/// arc for working, a ticked circle for completed
private struct StateDot: View {
    let state: LiveSession.State

    var body: some View {
        Group {
            switch state {
            case .busy:
                TimelineView(.animation) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
                    Circle()
                        .trim(from: 0, to: 0.72)
                        .stroke(Color(hex: 0xD77757), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(turn * 360))
                }
            case .waiting:
                Image(systemName: "hand.raised").font(.system(size: 12.5)).foregroundStyle(Color(CC.warning))
            case .idle:
                Image(systemName: "checkmark.circle").font(.system(size: 12.5)).foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .frame(width: 18, height: 18)
    }
}


/// a section's name over its rows, lined up with their names, and what enter does there
struct SectionLabel: View {
    let title: String
    let hint: String
    let theme: AppTheme
    var trailing: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(theme.say(title))
            if !hint.isEmpty { Text(theme.say(hint)).foregroundStyle(theme.textMuted.opacity(0.55)) }
            Spacer()
            if let trailing { Text(theme.say(trailing)) }
        }
        .font(ClaudeFonts.sans(11, .medium))
        .foregroundStyle(theme.textMuted.opacity(0.85))
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .frame(height: 26, alignment: .bottom)
        .padding(.bottom, 2)
    }
}

/// how long ago, as short as a list wants it: now, 5m, 3h, 2d, 3w, 4mo
enum Ago {
    /// for a column of its own: "just now", "5m ago"
    static func long(_ date: Date, now: Date = Date()) -> String {
        let s = short(date, now: now)
        return s == "now" ? "just now" : s + " ago"
    }

    static func short(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(Int(s / 60))m"
        case ..<86_400: return "\(Int(s / 3600))h"
        case ..<(86_400 * 14): return "\(Int(s / 86_400))d"
        case ..<(86_400 * 60): return "\(Int(s / 604_800))w"
        default: return "\(Int(s / 2_592_000))mo"
        }
    }
}

/// the light behind the lit row, one shape that glides between rows when a namespace is given
struct LitRow: View {
    let theme: AppTheme
    @Environment(\.litNamespace) private var namespace

    var body: some View {
        if let namespace {
            RoundedRectangle(cornerRadius: 8).fill(theme.rowSelected).matchedGeometryEffect(id: "lit", in: namespace)
        } else {
            RoundedRectangle(cornerRadius: 8).fill(theme.rowSelected)
        }
    }
}

private struct LitNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var litNamespace: Namespace.ID? {
        get { self[LitNamespaceKey.self] }
        set { self[LitNamespaceKey.self] = newValue }
    }
}

extension Notification.Name {
    static let windowDidShow = Notification.Name("windowDidShow")
}
