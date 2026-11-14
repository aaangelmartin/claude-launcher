import KeyboardShortcuts
import SwiftUI

/// the window's shortcut as typed on its key caps, ⌥C unless another was picked in the setup
@MainActor
enum Shortcut {
    static var text: String { KeyboardShortcuts.getShortcut(for: .openClaude)?.description ?? "⌥C" }
}

/// a key in a small cap
struct KeyCap: View {
    let key: String
    let theme: AppTheme

    var body: some View {
        Text(key)
            .font(ClaudeFonts.sans(10.5, .medium))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// keys in small caps and what they do, quiet
struct KeyHint: View {
    let keys: [String]
    let label: String
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { KeyCap(key: $0, theme: theme) }
            Text(theme.say(label))
                .padding(.leading, 3)
                .font(theme.label)
                .foregroundStyle(theme.textMuted.opacity(0.85))
        }
        .lineLimit(1)
    }
}

/// the plan's use, as claude code's /usage gives it: the five-hour session and the week, quiet until
/// they near the limit (yellow from 80 %, red from 95 %). hover for when each resets.
struct UsageLine: View {
    let usage: Usage
    let theme: AppTheme

    /// the time until a window resets, short: "42m", "2h 14m", "3d 4h". without minutes (the week,
    /// where they matter little) hours stand alone: "10h"
    static func left(until date: Date, now: Date = Date(), minutes: Bool = true) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 && minutes ? "\(h)h \(m)m" : "\(h)h" }
        return "\(max(m, 1))m"
    }

    var body: some View {
        HStack(spacing: 22) {
            if let session = usage.session { window("5h", session, minutes: true) }
            if let week = usage.week { window("Week", week, minutes: false) }
        }
        .lineLimit(1)
        .fixedSize()
        .font(theme.label)
    }

    /// a name, a short meter filling with the use, and the percentage
    private func window(_ name: String, _ w: Usage.Window, minutes: Bool) -> some View {
        let colour: Color = w.percent >= 95 ? Color(CC.error) : w.percent >= 80 ? Color(CC.warning) : Color.white.opacity(0.55)
        return HStack(spacing: 5) {
            Text(theme.say(name)).foregroundStyle(theme.textMuted.opacity(0.8))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(colour).frame(width: max(4, 34 * min(w.percent, 100) / 100))
            }
            .animation(.easeOut(duration: 0.4), value: w.percent)
            .frame(width: 34, height: 5)
            Text("\(Int(w.percent.rounded()))%")
                .monospacedDigit()
                .foregroundStyle(w.percent >= 80 ? colour : theme.textSecondary)
            if let left = w.resetsAt.map({ Self.left(until: $0, minutes: minutes) }) {
                Text(left).monospacedDigit().foregroundStyle(theme.textMuted.opacity(0.7))
            }
        }
        .help(w.resetsAt.map { "Resets " + $0.formatted(.relative(presentation: .named)) } ?? "")
    }
}
