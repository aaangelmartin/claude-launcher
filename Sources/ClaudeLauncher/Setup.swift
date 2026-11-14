import AppKit
import Carbon
import Foundation
import Security
import ServiceManagement

/// what claude launcher needs, checked without asking for anything: claude code installed, permission to
/// control terminal, claude code signed in (for the plan's use), start at login, the claude app (for
/// its font).
enum Setup {
    enum State: Equatable {
        case ok(String)
        /// not there yet, with what to do
        case missing(String)
        /// fine either way; said for what it adds
        case optional(String)
        /// not known until the first use
        case later(String)
    }

    // MARK: claude code

    /// where claude is installed, symlinks resolved. the app starts without a shell PATH, so the usual
    /// places are tried in turn.
    static func binary() -> String? {
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        }
        return nil
    }

    static func claudeCode() -> State {
        guard let binary = binary() else {
            return .missing("Install Claude Code, then check again")
        }
        // the binary's folder is named after its version: …/versions/2.1.323
        let version = URL(fileURLWithPath: binary).lastPathComponent
        let looksLikeVersion = version.first?.isNumber == true
        return .ok(looksLikeVersion ? "Version \(version)" : "Installed")
    }

    // MARK: terminal

    /// whether macOS lets this app send apple events to terminal, asked without prompting
    static func terminal() -> State {
        switch automationStatus(ask: false) {
        case noErr: return .ok("Allowed")
        case OSStatus(errAEEventNotPermitted): return .missing("Allow it in System Settings")
        default: return .later("macOS asks the first time a session opens")
        }
    }

    /// asks macOS for the permission now (it shows its own prompt when terminal is running)
    static func askForTerminal() -> State {
        _ = automationStatus(ask: true)
        return terminal()
    }

    private static func automationStatus(ask: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let bundle = "com.apple.Terminal"
        let status = bundle.withCString { pointer -> OSStatus in
            OSStatus(AECreateDesc(DescType(typeApplicationBundleID), pointer, bundle.utf8.count, &target))
        }
        guard status == noErr else { return status }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
    }

    // MARK: claude code sign-in

    /// whether claude code keeps a sign-in in the keychain; only its presence is looked at, nothing
    /// is read, so macOS asks nothing here
    static func signIn() -> State {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess || status == errSecInteractionNotAllowed {
            return .ok("For your plan's use, macOS asks once to read it")
        }
        return .optional("Sign in with claude to see your plan's use")
    }

    // MARK: login item

    static var startsAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    static func setStartsAtLogin(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }

    // MARK: claude app

    static func claudeApp() -> State {
        FileManager.default.fileExists(atPath: "/Applications/Claude.app")
            ? .ok("Its font is used")
            : .optional("Without it, the system font is used")
    }
}
