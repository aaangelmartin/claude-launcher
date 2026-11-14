import AppKit
import Combine

/// the window's state, in three moments, each with one purpose:
/// - opened: the claude code sessions running now. enter goes to one.
/// - typing: folders. enter on one opens its step.
/// - a folder's step: "new session" (lit), the sessions running there, then its past ones, with the
///   launch options below. enter starts, goes to or resumes. esc goes back to the folders.
@MainActor
final class MainModel: ObservableObject {
    enum Notice: Equatable {
        /// macOS said no to controlling terminal
        case notAllowed
        case failed(String)
        /// a running session whose window could not be found
        case windowNotFound(String)
    }

    enum Key: Equatable {
        case up, down, left, right, enter, tab, escape, space
        case jumpDown, jumpUp // ⌘↓ ⌘↑
        case optionsDown, optionsUp // ⌥↓ ⌥↑: open and fold the options
        case openNew // ⌘↵: a new session at once
        case createFolder // ⌘N: make the folder typed and start claude in it
    }

    /// one line of a folder's step
    enum StepItem: Equatable {
        case new
        case running(LiveSession)
        case past(SessionInfo)
    }

    @Published var text = "" { didSet { if text != oldValue { textChanged() } } }
    /// the folders found for what is typed
    @Published private(set) var rows: [String] = []
    /// the folder whose step is shown, nil outside it
    @Published private(set) var stepFolder: String?
    /// the lit line of what is shown (running sessions, folders, or the step), nil on the field
    @Published var selected: Int?
    /// true when the pointer, not the keys, picked the row: the list then stays where it is
    private(set) var selectedByPointer = false
    @Published var notice: Notice?
    /// changes with every new set of rows, so the list view starts fresh (top, same margins)
    @Published private(set) var listID = UUID()

    /// the picked value of each launch option. every time the window opens they start again from
    /// claude's defaults, so a one-off choice never carries over to the next launch
    @Published private(set) var picks: [Int] = LaunchOptions.all.map { _ in 0 }
    /// the plan's session and weekly use, when claude code's sign-in can be read
    @Published var usage: Usage?
    private var usageFetchedAt: Date?
    /// the option the arrows are on (the options are open while it is set), nil on the field and list
    @Published private(set) var optionRow: Int?
    /// which way the last change went (-1 back, 1 forward), so a carousel slides the right way
    private(set) var lastDelta = 1
    var optionsOpen: Bool { optionRow != nil }
    /// the newest number of each model family, as the installed claude knows them
    @Published private(set) var modelVersions: [String: String] = ModelVersions.cached(for: ModelVersions.binary()) ?? [:]
    private var versionsBinary: String?

    /// every folder worth offering, with its sessions and branch (built in the background)
    @Published var projects: [String: ProjectInfo] = [:]
    private var projectsBuiltAt: Date?
    /// the newest recent when the projects were built: a folder opened since rebuilds them at once
    private var projectsNewestRecent: String?
    /// claude code sessions running now on this mac, read again while the window is open
    @Published var live: [LiveSession] = []
    /// asks the panel to bring a running session forward
    var onFocus: (LiveSession) -> Void = { _ in }
    /// whether the field's caret is at the end of what is typed (→ there opens the lit folder)
    var caretAtEnd: () -> Bool = { true }

    init() { refreshModelVersions() }

    /// asks the panel to open a folder (raw, as typed, with the flags) or to close
    var onOpen: (String, [String]) -> Void = { _, _ in }
    var onClose: () -> Void = {}

    /// the folder part of what is typed ("Developer/" in "Developer/Pr"), dimmed in the rows
    var typedParent: String {
        guard let slash = text.lastIndex(of: "/") else { return "" }
        return String(text[...slash])
    }

    /// what is shown under the field
    enum Moment { case running, folders, step }
    var moment: Moment {
        if stepFolder != nil { return .step }
        return text.trimmingCharacters(in: .whitespaces).isEmpty ? .running : .folders
    }

    func reset() {
        refreshLive()
        refreshModelVersions()
        refreshProjects()
        refreshUsage()
        picks = LaunchOptions.all.map { _ in 0 }
        notice = nil
        optionRow = nil
        stepFolder = nil
        text = ""
        refreshRows()
    }

    private func textChanged() {
        // typing always happens in the field: back to the folders, the arrows on the field
        optionRow = nil
        stepFolder = nil
        refreshRows()
    }

    func refreshRows() {
        listID = UUID()
        selectedByPointer = false
        // nothing is lit until an arrow or the pointer lights it
        selected = nil
        let typed = text.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty {
            rows = []
        } else if typed.contains("/") || typed.hasPrefix("~") {
            // a path being typed: its subfolders, as a shell completes them
            rows = Suggestions.completions(for: text)
        } else {
            rows = fuzzyRows(typed)
        }
        // while searching, the best match is lit, so enter or the shortcut again takes it at once.
        // not when a folder's own subfolders are listed ("Developer/"): then it is that folder
        if !rows.isEmpty, !(typed.hasSuffix("/") && FolderPath.isDirectory(FolderPath.resolve(typed))) {
            selected = 0
        } else if rows.isEmpty, newFolder != nil {
            // nothing matches: the new folder is what is meant
            selected = 0
        }
    }

    // MARK: a new folder

    /// where a bare name becomes a folder: ~/Developer when there is one, else the home folder
    var newFolderParent: String = {
        let developer = FolderPath.home + "/Developer"
        return FolderPath.isDirectory(developer) ? developer : FolderPath.home
    }()

    /// the folder that would be created for what is typed, absolute, when it does not exist yet: a
    /// bare name under the parent, a path as typed. nil when it exists, or is no usable name
    var newFolder: String? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, !typed.hasSuffix("/"), !typed.contains(":") else { return nil }
        let path: String
        if typed.contains("/") || typed.hasPrefix("~") {
            path = ProjectIndex.trimmed(FolderPath.resolve(typed))
        } else {
            guard typed != ".", typed != ".." else { return nil }
            path = newFolderParent + "/" + typed
        }
        return FileManager.default.fileExists(atPath: path) ? nil : path
    }

    /// the new folder's line comes after the folders found
    var newFolderIndex: Int? { newFolder == nil ? nil : rows.count }

    /// make the new folder and start claude in it: a new project has no sessions to resume, so no step
    func createAndStart() {
        guard let path = newFolder else { NSSound.beep(); return }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            notice = .failed("could not create \(FolderPath.display(path)): \(error.localizedDescription)")
            return
        }
        onOpen(FolderPath.display(path), LaunchOptions.args(for: picks))
    }

    // MARK: what is listed

    /// how many lines can be lit now
    var count: Int {
        switch moment {
        case .running: live.count
        case .folders: rows.count + (newFolder == nil ? 0 : 1)
        case .step: stepItems.count
        }
    }

    func refreshLive() {
        let now = LiveSessions.all()
        if now != live { live = now }
        if let i = selected, i >= count { selected = count == 0 ? nil : count - 1 }
    }

    /// a folder's step: a new session, the sessions running in it, then its past ones, newest first
    var stepItems: [StepItem] {
        guard let folder = stepFolder else { return [] }
        let path = ProjectIndex.trimmed(FolderPath.resolve(folder))
        let running = live.filter { ProjectIndex.trimmed($0.cwd) == path }
        let ids = Set(running.map(\.sessionId))
        let past = (projects[path]?.sessions ?? []).filter { !ids.contains($0.id) }
        return [.new] + running.map(StepItem.running) + past.map(StepItem.past)
    }

    /// open a folder's step, "new session" lit
    func openStep(_ folder: String) {
        optionRow = nil
        stepFolder = folder
        selectedByPointer = false
        selected = 0
    }

    func closeStep() {
        stepFolder = nil
        optionRow = nil
        refreshRows()
    }

    /// enter on a line, wherever it is
    func act(on index: Int) {
        switch moment {
        case .running:
            if live.indices.contains(index) { onFocus(live[index]) }
        case .folders:
            if rows.indices.contains(index) { openStep(rows[index]) } else if index == newFolderIndex { createAndStart() }
        case .step:
            let items = stepItems
            guard let folder = stepFolder, items.indices.contains(index) else { return }
            switch items[index] {
            case .new: onOpen(folder, LaunchOptions.args(for: picks))
            case let .running(s): onFocus(s)
            case let .past(s): onOpen(folder, LaunchOptions.args(for: picks) + ["--resume", s.id])
            }
        }
    }

    /// ⌘↵: a new session at once, in the step's folder, the lit session's or folder's, or what is typed
    func openNew() {
        switch moment {
        case .step:
            if let folder = stepFolder { onOpen(folder, LaunchOptions.args(for: picks)) }
        case .running:
            let folder = selected.flatMap { live.indices.contains($0) ? FolderPath.display(live[$0].cwd) : nil } ?? ""
            onOpen(folder, LaunchOptions.args(for: picks))
        case .folders:
            // the new folder when it is lit; else the lit folder, or what is typed when it is one, or home
            if let selected, selected == newFolderIndex { createAndStart(); return }
            onOpen(folderTarget ?? "", LaunchOptions.args(for: picks))
        }
    }

    /// the shortcut pressed with the window open: a new session now, in the folder open or lit, or
    /// in the home folder
    func hotkeyAgain() { openNew() }

    /// what is typed, when it is a folder itself
    var typedFolder: String? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        return FolderPath.isDirectory(FolderPath.resolve(typed)) ? typed : nil
    }

    /// the folder enter would open while typing: the lit one, or what is typed when it is a folder
    private var folderTarget: String? {
        if let selected, rows.indices.contains(selected) { return rows[selected] }
        let typed = text.trimmingCharacters(in: .whitespaces)
        return FolderPath.isDirectory(FolderPath.resolve(typed)) ? typed : nil
    }

    // MARK: projects

    /// rebuilds the projects at most every two minutes, off the main thread
    func refreshProjects() {
        let newest = Recents.all.first
        if let at = projectsBuiltAt, Date().timeIntervalSince(at) < 120, newest == projectsNewestRecent { return }
        projectsBuiltAt = Date()
        projectsNewestRecent = newest
        let recents = Recents.dates
        Task.detached(priority: .userInitiated) {
            let built = ProjectIndex.build(recents: recents)
            await MainActor.run {
                self.projects = built
                if self.optionRow == nil, self.selected == nil, self.stepFolder == nil { self.refreshRows() }
            }
        }
    }

    /// what a row is, when it is a known project
    func info(for row: String) -> ProjectInfo? {
        projects[ProjectIndex.trimmed(FolderPath.resolve(row))]
    }

    /// a name typed, not a path: the home folder's own folders and every known project, matched
    /// fuzzily (letters in order, anywhere), the best first and the recently used a little ahead
    private func fuzzyRows(_ typed: String) -> [String] {
        var candidates: [String: Date?] = [:]
        for row in Suggestions.completions(for: "", allIn: FolderPath.home) { candidates[row] = .some(nil) }
        // every row ends in "/" so tab goes on into it
        for p in projects.values { candidates[FolderPath.display(p.path) + "/"] = p.lastUsed }
        let now = Date()
        let scored: [(String, Int)] = candidates.compactMap { row, used in
            guard let s = Fuzzy.score(typed, row) else { return nil }
            let days = used.flatMap { $0 }.map { now.timeIntervalSince($0) / 86_400 } ?? 1_000
            let recency = days < 1 ? 14 : days < 7 ? 9 : days < 30 ? 4 : 0
            return (row, s + recency)
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.localizedStandardCompare($1.0) == .orderedAscending }
            .prefix(60)
            .map(\.0)
    }

    /// the pointer moved onto a line
    func point(at index: Int) {
        guard index < count, selected != index else { return }
        selectedByPointer = true
        selected = index
    }

    // MARK: launch options

    /// reads the model numbers again when claude has been updated since they were last read; the
    /// binary is large, so that happens off the main thread and the labels follow when it is done
    func refreshModelVersions() {
        guard let binary = ModelVersions.binary(), binary != versionsBinary else { return }
        versionsBinary = binary
        if let cached = ModelVersions.cached(for: binary) {
            if cached != modelVersions { modelVersions = cached }
            return
        }
        Task.detached(priority: .utility) {
            let found = ModelVersions.scan(binary)
            guard !found.isEmpty else { return }
            await MainActor.run {
                ModelVersions.save(found, for: binary)
                self.modelVersions = found
            }
        }
    }

    /// asks for the plan's use again, at most once a minute
    func refreshUsage() {
        // only the installed app reads the keychain (tests and previews would make macOS ask)
        guard Bundle.main.bundleIdentifier == "com.aaangelmartin.claude-launcher" else { return }
        if let at = usageFetchedAt, Date().timeIntervalSince(at) < 60 { return }
        usageFetchedAt = Date()
        Task.detached(priority: .utility) {
            let found = await Usage.fetch()
            await MainActor.run { self.usage = found }
        }
    }

    /// a value as shown: models with their number ("Opus 5.5"), the rest as they are
    func display(_ choice: Choice, of option: Int) -> String {
        guard option == LaunchOptions.model, let alias = choice.args.last,
              let number = modelVersions[alias] else { return choice.label }
        return choice.label + " " + number
    }

    /// the value an option stands at, as shown: for an option whose default is marked rather than
    /// offered, the value its default amounts to
    func shown(_ option: Int) -> Int {
        let pick = picks[option]
        return pick == 0 && LaunchOptions.all[option].defaultIsMarked ? defaultValue(of: option) : pick
    }

    func choice(of option: Int) -> Choice { LaunchOptions.all[option].choices[shown(option)] }

    /// the value claude starts with when this option adds no flag: the settings' model (opus when they
    /// name none), the effort that model ships with, the settings' permission mode (manual when none)
    func defaultValue(of option: Int) -> Int {
        let o = LaunchOptions.all[option]
        guard o.defaultIsMarked else { return 0 }
        func index(_ label: String?) -> Int? { label.flatMap { l in o.choices.firstIndex { $0.label == l } } }
        switch option {
        case LaunchOptions.model:
            return index(LaunchOptions.settingsDefault(of: option)) ?? index("Opus") ?? 1
        case LaunchOptions.effort:
            let family = choice(of: LaunchOptions.model).args.last ?? "opus"
            return index(modelVersions["effort." + family]) ?? index("medium") ?? 1
        default:
            return index(LaunchOptions.settingsDefault(of: option)) ?? 1
        }
    }

    /// pick a value as shown: picking the default value stores "no flag", so it keeps following claude
    func pickShown(_ value: Int, of option: Int) {
        let o = LaunchOptions.all[option]
        pick(o.defaultIsMarked && value == defaultValue(of: option) ? 0 : value, of: option)
    }

    /// ← → on an option: the value before or after, stopping at the ends
    func step(_ option: Int, by delta: Int) {
        let o = LaunchOptions.all[option]
        let first = o.defaultIsMarked ? 1 : 0
        pickShown(min(max(shown(option) + delta, first), o.choices.count - 1), of: option)
    }

    func pick(_ value: Int, of option: Int) {
        guard LaunchOptions.all[option].choices.indices.contains(value), picks[option] != value else { return }
        lastDelta = value > shown(option) ? 1 : -1
        picks[option] = value
    }

    /// open the options on one of them (a click on the summary line, ⌘↓)
    func openOptions(at row: Int = 0) { optionRow = row }
    func closeOptions() { optionRow = nil }

    // MARK: keys

    /// one key, wherever the arrows are. false: not ours, the field gets it (←→ move the caret there,
    /// space types a space).
    func handle(_ key: Key) -> Bool {
        if key == .createFolder {
            if newFolder != nil { createAndStart() } else { NSSound.beep() }
            return true
        }
        // the launch options belong to a folder's new session
        if key == .optionsDown { if moment == .step { optionRow = optionRow ?? 0 }; return true }
        if key == .optionsUp { optionRow = nil; return true }
        if let optionRow { return handleOptions(key, optionRow) }
        switch key {
        case .down:
            // the last line is the end
            guard count > 0 else { return true }
            selectedByPointer = false
            selected = min((selected ?? -1) + 1, count - 1)
        case .up:
            // at the top already: stay there, never wrap round to the bottom
            guard let s = selected else { return true }
            selectedByPointer = false
            selected = s == 0 ? nil : s - 1
        case .jumpDown: if count > 0 { selectedByPointer = false; selected = count - 1 }
        case .jumpUp: selected = nil
        case .escape:
            // back out one step at a time: the folder's step, what is typed, then the window
            if moment == .step { closeStep() } else if !text.isEmpty { text = "" } else { close() }
        case .enter: submit()
        case .openNew: openNew()
        case .tab:
            // with nothing lit, tab lights the first line; on a folder while typing it completes it
            if selected == nil {
                if count > 0 { selectedByPointer = false; selected = 0 }
            } else {
                complete()
            }
        case .right:
            // → at the end of the text opens the lit folder's step; elsewhere it moves the caret
            guard moment == .folders, caretAtEnd(), let s = selected, rows.indices.contains(s) else { return false }
            openStep(rows[s])
        case .left:
            guard moment == .step else { return false }
            closeStep()
        case .space: return false // spaces belong to the field
        case .optionsDown, .optionsUp, .createFolder: break
        }
        return true
    }

    /// the options are open: ↑ ↓ go from one to the next, ← → change the value, esc folds them away
    private func handleOptions(_ key: Key, _ row: Int) -> Bool {
        let last = LaunchOptions.all.count - 1
        switch key {
        case .up: optionRow = row == 0 ? nil : row - 1
        case .down: optionRow = min(last, row + 1)
        case .tab: optionRow = row == last ? 0 : row + 1
        case .jumpUp, .escape: optionRow = nil
        case .jumpDown: optionRow = last
        case .left: step(row, by: -1)
        case .right: step(row, by: 1)
        case .enter: if selected != nil { submit() } else { openNew() }
        case .openNew: openNew()
        case .space, .optionsDown, .optionsUp, .createFolder: break
        }
        return true
    }

    /// tab while typing: the lit folder goes into the field and its subfolders are listed
    func complete() {
        guard moment == .folders, let selected, rows.indices.contains(selected) else { return }
        text = rows[selected]
    }

    /// enter: act on the lit line; while typing with nothing lit, open the step of what is typed
    /// when it is a folder
    func submit() {
        if let selected { act(on: selected); return }
        if moment == .folders, let folder = folderTarget { openStep(folder); return }
        NSSound.beep()
    }

    func open(row: String) { openStep(row) }
    func close() { onClose() }
}
