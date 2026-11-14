@testable import ClaudeLauncher
import Foundation
import Testing

@Suite struct FolderPathTests {
    let home = "/Users/test"

    @Test func emptyOpensHome() {
        #expect(FolderPath.resolve("", home: home) == home)
        #expect(FolderPath.resolve("   ", home: home) == home)
        #expect(FolderPath.resolve("~", home: home) == home)
    }

    @Test func relativeIsUnderHome() {
        #expect(FolderPath.resolve("proyectos/mi-app", home: home) == "/Users/test/proyectos/mi-app")
        #expect(FolderPath.resolve("  proyectos/mi-app  ", home: home) == "/Users/test/proyectos/mi-app")
        #expect(FolderPath.resolve("~/proyectos", home: home) == "/Users/test/proyectos")
    }

    @Test func absoluteStaysAbsolute() {
        #expect(FolderPath.resolve("/Volumes/disco/obra", home: home) == "/Volumes/disco/obra")
    }

    @Test func displayIsRelativeInsideHome() {
        #expect(FolderPath.display("/Users/test/a/b", home: home) == "a/b")
        #expect(FolderPath.display("/Users/test", home: home) == "")
        #expect(FolderPath.display("/Volumes/x", home: home) == "/Volumes/x")
        #expect(FolderPath.display("/Users/testing", home: home) == "/Users/testing")
    }

    @Test func commandQuotesForTheShell() {
        #expect(FolderPath.shellQuoted("it's here") == #"'it'\''s here'"#)
        #expect(FolderPath.command(for: "/Volumes/Mi Disco") == "cd '/Volumes/Mi Disco' && claude")
        #expect(FolderPath.command(for: "/x", args: ["--model", "opus"]) == "cd '/x' && claude --model opus")
        #expect(FolderPath.shellWord("a b") == "'a b'")
    }
}

@Suite struct SuggestionsTests {
    let root: String = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-launcher-tests-\(UUID().uuidString)")
        for sub in ["proyectos/alfa", "proyectos/Beta", "proyectos/.oculta", "Documentos"] {
            try! FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("proyectos/archivo.txt").path, contents: Data())
        return dir.path
    }()

    @Test func matchesFoldersByPrefixIgnoringCase() {
        #expect(Suggestions.completions(for: "pro", home: root) == ["proyectos/"])
        #expect(Suggestions.completions(for: "proyectos/b", home: root) == ["proyectos/Beta/"])
    }

    @Test func listsOnlyVisibleFolders() {
        #expect(Suggestions.completions(for: "proyectos/", home: root) == ["proyectos/alfa/", "proyectos/Beta/"])
        #expect(Suggestions.completions(for: "proyectos/.", home: root) == ["proyectos/.oculta/"])
    }

    @Test func absolutePathsCompleteAbsolute() {
        #expect(Suggestions.completions(for: root + "/Doc", home: "/nowhere") == [root + "/Documentos/"])
    }

    @Test func nothingForEmptyOrMissing() {
        #expect(Suggestions.completions(for: "", home: root).isEmpty)
        #expect(Suggestions.completions(for: "no/existe/", home: root).isEmpty)
    }
}



@Suite struct LaunchOptionsTests {
    @Test func defaultsAddNothing() {
        #expect(LaunchOptions.args(for: [0, 0, 0]).isEmpty)
    }

    @Test func picksBecomeFlagsInOrder() {
        // opus, high effort, plan, continue
        #expect(LaunchOptions.args(for: [2, 3, 3]) == ["--model", "opus", "--effort", "high", "--permission-mode", "plan"])
        // max effort, bypass permissions
        #expect(LaunchOptions.args(for: [0, 5, 5]) == ["--effort", "max", "--permission-mode", "bypassPermissions"])
    }



}

@Suite struct ModelVersionsTests {
    @Test func keepsTheNewestOfEachFamily() {
        let text = "x claude-opus-4-8 y claude-opus-5-5 claude-opus-5 claude-sonnet-4-5-20250929 claude-sonnet-5-5 claude-haiku-4-5-20251001 claude-fable-5-1 claude-fable-5-2 claude-fable-5 claude-3-5-sonnet"
        let v = ModelVersions.newest(in: Data(text.utf8))
        #expect(v.filter { !$0.key.hasPrefix("effort.") } == ["opus": "5.5", "sonnet": "5.5", "haiku": "4.5", "fable": "5.2"])
    }

    @Test func eachModelGetsTheEffortItsTableGives() {
        let text = #"{id:"claude-opus-5",x:1,default_effort:"high"},{id:"claude-opus-5-5",caps:["a"],default_effort:"medium"},{id:"claude-opus-5-5",default_effort:"medium"}"#
        let v = ModelVersions.newest(in: Data(text.utf8))
        #expect(v["opus"] == "5.5")
        #expect(v["effort.opus"] == "medium")
    }

    @Test func aWholeNumberHasNoDot() {
        #expect(ModelVersions.newest(in: Data("claude-opus-6 claude-opus-5-5".utf8)) == ["opus": "6"])
    }

    @Test func aDateIsNotAMinor() {
        #expect(ModelVersions.newest(in: Data("claude-opus-4-20250514".utf8)) == ["opus": "4"])
    }
}

@Suite struct InstalledClaudeTests {
    /// on a mac with claude installed, its own binary names a number for every family
    @Test func installedClaudeNamesEveryFamily() throws {
        guard let binary = ModelVersions.binary() else { return }
        let start = Date()
        let found = ModelVersions.scan(binary)
        print("model versions:", found, "in", Date().timeIntervalSince(start), "s")
        #expect(Set(found.keys.filter { !$0.hasPrefix("effort.") }) == Set(ModelVersions.families))
        #expect(found["effort.opus"] != nil)
    }
}

@Suite struct UsageTests {
    @Test func readsSessionAndWeek() {
        let json = #"{"five_hour":{"utilization":6.0,"resets_at":"2026-11-13T14:50:00.834874+00:00"},"seven_day":{"utilization":71.0,"resets_at":"2026-11-14T00:00:00+00:00"},"extra_usage":{"is_enabled":false}}"#
        let u = Usage.parse(Data(json.utf8))
        #expect(u?.session?.percent == 6)
        #expect(u?.week?.percent == 71)
        #expect(u?.session?.resetsAt != nil)
        #expect(u?.week?.resetsAt != nil)
    }

    @Test func timeLeftIsShort() {
        let now = Date()
        #expect(UsageLine.left(until: now.addingTimeInterval(42 * 60 + 5), now: now) == "42m")
        #expect(UsageLine.left(until: now.addingTimeInterval(2 * 3600 + 14 * 60 + 5), now: now) == "2h 14m")
        #expect(UsageLine.left(until: now.addingTimeInterval(3 * 86_400 + 4 * 3600 + 5), now: now) == "3d 4h")
    }

    @Test func nothingWhenThereAreNoWindows() {
        #expect(Usage.parse(Data(#"{"error":"x"}"#.utf8)) == nil)
    }
}


@MainActor
@Suite struct MarkedDefaultTests {
    @Test func openingStartsFromTheDefaults() {
        let m = MainModel()
        m.pick(3, of: LaunchOptions.effort)
        m.pick(2, of: LaunchOptions.permissions)
        m.reset()
        #expect(m.picks == [0, 0, 0])
    }

    @Test func pickingTheDefaultLevelAddsNoFlag() {
        let m = MainModel()
        m.pick(0, of: LaunchOptions.effort)
        let def = m.defaultValue(of: LaunchOptions.effort)
        #expect(m.shown(LaunchOptions.effort) == def)
        m.step(LaunchOptions.effort, by: 1)
        #expect(m.picks[LaunchOptions.effort] == def + 1)
        m.step(LaunchOptions.effort, by: -1)
        #expect(m.picks[LaunchOptions.effort] == 0)
    }

    @Test func stepsNeverReachTheHiddenDefault() {
        let m = MainModel()
        m.pick(1, of: LaunchOptions.effort)
        m.step(LaunchOptions.effort, by: -1)
        #expect(m.shown(LaunchOptions.effort) == 1)
    }
}

@Suite struct ProjectsTests {
    @Test func fuzzyFindsLettersInOrderAndPrefersTheName() {
        #expect(Fuzzy.score("abr", "Developer/abrir-claude/") != nil)
        #expect(Fuzzy.score("xyz", "Developer/abrir-claude/") == nil)
        let name = Fuzzy.score("abr", "Developer/abrir-claude/")!
        let buried = Fuzzy.score("abr", "Desktop/a-big-repo/")!
        #expect(name > buried)
        #expect(Fuzzy.score("ac", "Developer/abrir-claude/")! > Fuzzy.score("ac", "Developer/backup/")!)
    }

    @Test func aSessionTakesItsTitleFolderAndFirstWords() {
        let head = #"""
        {"type":"mode","mode":"normal"}
        {"type":"user","isMeta":true,"cwd":"/Users/x/p","message":{"content":"<command-name>/x</command-name>"}}
        {"type":"user","cwd":"/Users/x/p","message":{"content":[{"type":"text","text":"Fix the   login\nbug <pasted_content id=\"1\">secret</pasted_content>"}]}}
        """#
        let r = ProjectIndex.parse(head: Data(head.utf8), tail: Data(), id: "abc", updated: Date())
        #expect(r?.0 == "/Users/x/p")
        #expect(r?.1.title == "Fix the login bug")
        let tail = #"{"type":"ai-title","aiTitle":"Login bug fix"}"#
        let titled = ProjectIndex.parse(head: Data(head.utf8), tail: Data(tail.utf8), id: "abc", updated: Date())
        #expect(titled?.1.title == "Login bug fix")
    }

    @Test func agoIsShort() {
        let now = Date()
        #expect(Ago.short(now.addingTimeInterval(-30), now: now) == "now")
        #expect(Ago.short(now.addingTimeInterval(-300), now: now) == "5m")
        #expect(Ago.short(now.addingTimeInterval(-7200), now: now) == "2h")
        #expect(Ago.short(now.addingTimeInterval(-86_400 * 3), now: now) == "3d")
    }
}

@Suite struct LiveSessionTests {
    @Test func readsClaudesSessionRecord() {
        let json = #"{"pid":29482,"sessionId":"e2","cwd":"/Users/x/laaabs","name":"Brain & Ranking","status":"waiting","waitingFor":"permission","statusUpdatedAt":1793993626577}"#
        let s = LiveSessions.parse(Data(json.utf8))
        #expect(s?.name == "Brain & Ranking")
        #expect(s?.state == .waiting)
        #expect(s?.waitingFor == "permission")
    }

    @Test func spareProcessesAreNotSessions() {
        #expect(LiveSessions.parse(Data(#"{"pid":1,"sessionId":"a","cwd":"/","spare":true}"#.utf8)) == nil)
    }
}


@MainActor
@Suite struct FlowTests {
    private func model(sessions: [SessionInfo] = [], live: [LiveSession] = []) -> MainModel {
        let m = MainModel()
        let home = FolderPath.home
        m.projects = [home + "/Developer": ProjectInfo(path: home + "/Developer", lastUsed: Date(), sessions: sessions)]
        m.live = live
        return m
    }

    @Test func opensOnEveryRunningSession() {
        let live = (0..<9).map { LiveSession(pid: Int32($0 + 1), sessionId: "\($0)", cwd: "/tmp", name: "s\($0)", state: .idle, waitingFor: nil, since: Date()) }
        let m = model(live: live)
        #expect(m.moment == .running)
        #expect(m.count == 9)
        var focused: LiveSession?
        m.onFocus = { focused = $0 }
        _ = m.handle(.down)
        _ = m.handle(.enter)
        #expect(focused?.sessionId == "0")
    }

    @Test func typingListsFoldersAndEnterOpensTheStepWithNewLit() {
        let m = model(sessions: [SessionInfo(id: "p", title: "Old work", updated: Date())])
        m.text = "Developer"
        #expect(m.moment == .folders)
        _ = m.handle(.enter)
        #expect(m.moment == .step)
        #expect(m.selected == 0)
        #expect(m.stepItems.count == 2)
        #expect(m.stepItems.first == .new)
    }

    @Test func enterTwiceStartsANewSession() {
        let m = model()
        var opened: (String, [String])?
        m.onOpen = { opened = ($0, $1) }
        m.text = "Developer"
        _ = m.handle(.enter)
        _ = m.handle(.enter)
        #expect(opened?.0.hasPrefix("Developer") == true)
        #expect(opened?.1 == [])
    }

    @Test func searchingLightsTheBestMatchSoTheShortcutOpensIt() {
        let m = model()
        var opened: String?
        m.onOpen = { raw, _ in opened = raw }
        m.text = "Develop"
        #expect(m.selected == 0)
        m.hotkeyAgain()
        #expect(opened?.hasPrefix("Developer") == true)
    }

    @Test func aPastSessionResumes() {
        let m = model(sessions: [SessionInfo(id: "p", title: "Old work", updated: Date())])
        var opened: [String]?
        m.onOpen = { _, a in opened = a }
        m.text = "Developer"
        _ = m.handle(.enter)
        _ = m.handle(.down)
        _ = m.handle(.enter)
        #expect(opened == ["--resume", "p"])
    }

    @Test func escapeBacksOutOneStepAtATime() {
        let m = model()
        var closed = false
        m.onClose = { closed = true }
        m.text = "Developer"
        _ = m.handle(.enter)
        _ = m.handle(.escape)
        #expect(m.moment == .folders)
        _ = m.handle(.escape)
        #expect(m.text.isEmpty)
        #expect(!closed)
        _ = m.handle(.escape)
        #expect(closed)
    }

    @Test func tabLightsTheFirstLine() {
        let m = model(live: [LiveSession(pid: 1, sessionId: "a", cwd: "/tmp", name: "one", state: .busy, waitingFor: nil, since: Date())])
        _ = m.handle(.tab)
        #expect(m.selected == 0)
    }

    @Test func theShortcutAgainStartsInTheLitFolderOrHome() {
        let m = model()
        var opened: String?
        m.onOpen = { raw, _ in opened = raw }
        m.hotkeyAgain()
        #expect(opened == "")
        m.text = "Developer"
        _ = m.handle(.enter)
        m.hotkeyAgain()
        #expect(opened?.hasPrefix("Developer") == true)
    }

    @Test func upAtTheTopStaysThere() {
        let m = model()
        m.text = "Dev"
        _ = m.handle(.up)
        #expect(m.selected == nil)
    }
}

@MainActor
@Suite struct NewFolderTests {
    @Test func aNameThatIsNoFolderOffersOneLitWhenNothingMatches() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("claude-launcher-new-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        let m = MainModel()
        m.newFolderParent = parent
        m.text = "zz-brand-new-project-\(UUID().uuidString.prefix(6))"
        #expect(m.newFolder == parent + "/" + m.text)
        if m.rows.isEmpty { #expect(m.selected == 0) }
    }

    @Test func enterOnItCreatesTheFolderAndStartsThere() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("claude-launcher-new-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        let m = MainModel()
        m.newFolderParent = parent
        var opened: (String, [String])?
        m.onOpen = { opened = ($0, $1) }
        m.text = "zz-brand-new-project-\(UUID().uuidString.prefix(6))"
        let path = try #require(m.newFolder)
        m.act(on: try #require(m.newFolderIndex))
        #expect(FolderPath.isDirectory(path))
        #expect(opened?.0 == FolderPath.display(path))
        #expect(opened?.1 == [])
    }

    @Test func anExistingFolderOffersNothing() {
        let m = MainModel()
        m.text = "~/"
        #expect(m.newFolder == nil)
        m.text = FileManager.default.temporaryDirectory.path
        #expect(m.newFolder == nil)
    }
}
