import KeyboardShortcuts
import LaaabsKit
import SwiftUI

/// one easing for everything that moves in the options, so opening, focus and values feel as one
enum Motion {
    /// an ease out that starts quick and lands soft (claude's own expo-ish curve)
    static let open = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.42)
    static let close = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.24)
    static let focus = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let value = Animation.spring(response: 0.32, dampingFraction: 0.8)
    /// each open row follows the one above it by this much
    static let stagger = 0.035
}

/// the launch options at the foot of the window, in order: model, effort, permissions, session.
/// folded: one line with each value painted as claude code paints it. open (↓ past the folders, ⌘↓,
/// or a click): a row per option, changed with ← →. the section has a known height either way, so the
/// card grows and shrinks smoothly; the summary steps aside and the rows come in one after another.
struct OptionsSection: View {
    @ObservedObject var model: MainModel
    let theme: AppTheme
    @Namespace private var focus

    static let foldedHeight: CGFloat = 40
    static let rowHeight: CGFloat = 40
    static let sliderHeight: CGFloat = 78
    static let modesHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 2
    static let padding: CGFloat = 8
    /// what a control may take: the card less the row's margins and the title column
    static let controlWidth: CGFloat = MainView.width - 16 - 12 - 88 - 14

    static func height(of option: LaunchOption) -> CGFloat {
        switch option.style {
        case .slider: sliderHeight
        case .modes: modesHeight
        case .segments: rowHeight
        }
    }

    static var openHeight: CGFloat {
        let rows = LaunchOptions.all.map(height(of:)).reduce(0, +)
        return rows + rowSpacing * CGFloat(LaunchOptions.all.count - 1) + padding * 2
    }

    var body: some View {
        let open = model.optionsOpen
        ZStack(alignment: .top) {
            if open {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(Array(LaunchOptions.all.enumerated()), id: \.offset) { index, option in
                        OptionRow(model: model, index: index, option: option, theme: theme, focus: focus)
                    }
                }
                .padding(.vertical, Self.padding)
                // the rows bring themselves in; going away they all fade at once
                .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else {
                summary
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -4)).animation(.easeOut(duration: 0.22).delay(0.1)),
                        removal: .opacity.combined(with: .offset(y: -6)).animation(.easeOut(duration: 0.12))
                    ))
            }
        }
        .frame(height: open ? Self.openHeight : Self.foldedHeight, alignment: .top)
        .clipped()
        .animation(open ? Motion.open : Motion.close, value: open)
        .animation(Motion.focus, value: model.optionRow)
        .animation(.easeOut(duration: 0.2), value: model.usage)
    }

    // MARK: folded

    /// the bottom bar: on the left what can be done (the launch values and ⌥↓ to change them, or over
    /// the running sessions the keys that act on them), on the right the plan's use
    /// folded: how a new or resumed session is launched, ⌥↓ (or a click) to change it. the keys and
    /// the plan's use live in the command bar under it
    private var summary: some View {
        HStack(spacing: 2) {
            KeyCap(key: "⌥↓", theme: theme)
                .padding(.leading, 8)
                .padding(.trailing, 2)
                .help("Change model, effort and permissions")
            launchValues
            Spacer(minLength: 8)
        }
        .font(theme.chip)
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(height: Self.foldedHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.openOptions() }
    }

    /// the window's shortcut as typed on its key caps, ⌥C unless another was picked
    static var shortcutText: String { KeyboardShortcuts.getShortcut(for: .openClaude)?.description ?? "⌥C" }

    private var launchValues: some View {
        HStack(spacing: 0) {
            item(LaunchOptions.model) {
                ModelName(label: model.display(model.choice(of: LaunchOptions.model), of: LaunchOptions.model), on: true, theme: theme)
            }
            item(LaunchOptions.effort) {
                let choice = model.choice(of: LaunchOptions.effort)
                PaintedText(text: choice.label, paint: choice.paint, font: theme.chip, bold: true)
            }
            item(LaunchOptions.permissions) {
                let choice = model.choice(of: LaunchOptions.permissions)
                HStack(spacing: 5) {
                    if let symbol = choice.symbol {
                        PaintedText(text: symbol, paint: choice.paint, font: .system(size: 10))
                    }
                    PaintedText(text: theme.say(choice.label), paint: choice.paint == .plain(CC.inactive) ? .plain(RGB(255, 255, 255)) : choice.paint, font: theme.chip, bold: true)
                }
            }
        }
    }

    private func item<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
            .onTapGesture { model.openOptions(at: index) }
    }
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

/// a model's name with its number a step quieter: "Opus 5.5"
private struct ModelName: View {
    let label: String
    let on: Bool
    let theme: AppTheme

    var body: some View {
        if let space = label.lastIndex(of: " "), label[label.index(after: space)...].first?.isNumber == true {
            (Text(label[..<space]).foregroundStyle(on ? theme.text : theme.textSecondary)
                + Text(" " + label[label.index(after: space)...]).foregroundStyle(on ? theme.textSecondary : theme.textMuted))
        } else {
            Text(label).foregroundStyle(on ? theme.text : theme.textSecondary)
        }
    }
}

/// the small word that marks the value claude starts with
private struct DefaultMark: View {
    let theme: AppTheme
    var body: some View {
        Text(theme.say("default"))
            .font(ClaudeFonts.sans(9.5, .medium))
            .foregroundStyle(theme.textMuted.opacity(0.85))
    }
}

/// one option, open: its name in a column, its control after it; lit while the arrows are on it. the
/// light is one shape that glides from row to row. when the options open, each row drops in a moment
/// after the one above.
private struct OptionRow: View {
    @ObservedObject var model: MainModel
    let index: Int
    let option: LaunchOption
    let theme: AppTheme
    let focus: Namespace.ID
    @State private var shown = false

    var body: some View {
        let focused = model.optionRow == index
        HStack(spacing: 0) {
            Text(theme.say(option.title))
                .font(theme.chip)
                .foregroundStyle(focused ? theme.text : theme.textSecondary)
                .frame(width: 88, alignment: .leading)
                .padding(.leading, 12)
            control
            Spacer(minLength: 0)
        }
        .frame(height: OptionsSection.height(of: option))
        .background {
            if focused {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.ghostHover)
                    .matchedGeometryEffect(id: "focus", in: focus)
            }
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { model.openOptions(at: index) }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : -10)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86).delay(0.04 + Double(index) * Motion.stagger)) { shown = true }
        }
    }

    /// the values offered: all of them, or all but the first when the default is marked instead
    private var offered: Range<Int> { (option.defaultIsMarked ? 1 : 0)..<option.choices.count }

    @ViewBuilder private var control: some View {
        let first = offered.lowerBound
        let current = model.shown(index) - first
        let marked = option.defaultIsMarked ? model.defaultValue(of: index) - first : nil
        let choose: (Int) -> Void = { value in
            model.openOptions(at: index)
            model.pickShown(value + first, of: index)
        }
        switch option.style {
        case .segments:
            Segments(labels: offered.map { theme.say(model.display(option.choices[$0], of: index)) },
                     icons: offered.map { option.choices[$0].icon },
                     picked: current, marked: marked, theme: theme, pick: choose)
        case .slider:
            EffortSlider(levels: Array(option.choices[offered]), picked: current, marked: marked ?? 0, theme: theme, pick: choose)
        case .modes:
            ModePicker(modes: Array(option.choices[offered]), picked: current, marked: marked, theme: theme, pick: choose)
        }
    }
}

// MARK: controls

/// every value side by side, sharing the width evenly; the picked one raised on a pill that slides,
/// the default one marked under its name.
private struct Segments: View {
    let labels: [String]
    let icons: [String?]
    let picked: Int
    let marked: Int?
    let theme: AppTheme
    let pick: (Int) -> Void
    @Namespace private var thumb

    private var segmentWidth: CGFloat { (OptionsSection.controlWidth - 4) / CGFloat(labels.count) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let on = index == picked
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let icon = icons[index] {
                        Image(systemName: icon).font(.system(size: 10.5, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? theme.text : theme.textSecondary)
                    }
                    ModelName(label: label, on: on, theme: theme)
                        .font(theme.chip)
                        .fontWeight(on ? .medium : .regular)
                    if index == marked { DefaultMark(theme: theme) }
                }
                .lineLimit(1)
                .frame(width: segmentWidth, height: 24)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.11))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { pick(index) }
            }
        }
        .padding(2)
        .background(theme.controlTrack, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairlineBorder, lineWidth: 0.5))
        .animation(Motion.value, value: picked)
    }
}

/// claude's effort slider: the five levels, "faster" to "smarter", filled in the level's colour up to
/// the ball, which carries a dot of that colour and glows in it, follows the pointer while dragged
/// and settles on the nearest level. there is no "auto": the level the model starts with is marked
/// "default" under the track, and the ball sits there until another level is picked.
private struct EffortSlider: View {
    let levels: [Choice]
    let picked: Int
    let marked: Int
    let theme: AppTheme
    let pick: (Int) -> Void

    @State private var dragX: CGFloat?
    @State private var hovering = false

    private let width = OptionsSection.controlWidth
    private let ball: CGFloat = 16
    private let track: CGFloat = 5
    private var inset: CGFloat { ball / 2 }
    private var stops: Int { levels.count }
    private func x(_ stop: Int) -> CGFloat { inset + CGFloat(stop) / CGFloat(stops - 1) * (width - inset * 2) }
    private func nearest(_ x: CGFloat) -> Int {
        min(max(Int(((x - inset) / (width - inset * 2) * CGFloat(stops - 1)).rounded()), 0), stops - 1)
    }

    var body: some View {
        let choice = levels[picked]
        let ballX = dragX ?? x(picked)
        VStack(spacing: 5) {
            HStack {
                Text(theme.say("Faster"))
                Spacer()
                Text(theme.say("Smarter"))
            }
            .font(theme.label)
            .foregroundStyle(theme.textMuted)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: track)
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                // the colours stay put along the track; the fill only uncovers them
                EffortSlider.fill(choice.paint)
                    .frame(width: width, height: track)
                    .mask(alignment: .leading) { Capsule().frame(width: max(ballX, track), height: track) }
                ForEach(0..<stops, id: \.self) { s in
                    Capsule()
                        .fill(x(s) <= ballX + 0.5 ? Color.black.opacity(0.22) : Color.white.opacity(0.28))
                        .frame(width: 2, height: 9)
                        .offset(x: x(s) - 1)
                        .opacity(s == 0 || s == stops - 1 || abs(x(s) - ballX) < ball / 2 ? 0 : 1)
                }
                theBall(colour: EffortSlider.color(choice.paint))
                    .offset(x: ballX - inset)
            }
            .frame(width: width, height: 22)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let at = min(max(value.location.x, inset), width - inset)
                dragX = at
                pick(nearest(at))
            }.onEnded { _ in
                dragX = nil
            })

            ZStack {
                ForEach(0..<stops, id: \.self) { s in
                    label(s)
                        .fixedSize()
                        .frame(width: width, alignment: s == 0 ? .leading : s == stops - 1 ? .trailing : .center)
                        .offset(x: s == 0 || s == stops - 1 ? 0 : x(s) - width / 2)
                        .allowsHitTesting(false)
                }
                // each label takes the clicks of its share of the width
                HStack(spacing: 0) {
                    ForEach(0..<stops, id: \.self) { s in
                        Color.clear.contentShape(Rectangle()).onTapGesture { pick(s) }
                    }
                }
            }
            .frame(width: width, height: 15)
        }
        .frame(width: width)
        .animation(dragX == nil ? Motion.value : .interactiveSpring(response: 0.1, dampingFraction: 0.9), value: ballX)
        .animation(Motion.value, value: picked)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    /// white with a dot of the level's colour and a glow of it
    private func theBall(colour: Color) -> some View {
        ZStack {
            Circle().fill(Color(hex: 0xF5F4EF))
            Circle().fill(colour).frame(width: 6, height: 6)
        }
        .frame(width: ball, height: ball)
        .shadow(color: colour.opacity(0.55), radius: dragX == nil ? 5 : 8)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        .scaleEffect(dragX != nil ? 1.15 : hovering ? 1.06 : 1)
    }

    /// a level's name, centred on its stop: the picked one bold in its colour. the default one has
    /// "default" beside it, outside the name's own width so the name stays on its stop.
    private func label(_ s: Int) -> some View {
        let c = levels[s]
        return Group {
            if s == picked {
                PaintedText(text: c.label, paint: c.paint, font: theme.label, bold: true)
            } else {
                Text(c.label).font(theme.label).foregroundStyle(theme.textMuted.opacity(0.7))
            }
        }
        // a zero-wide frame on the name's edge, the word hanging out of it: the name keeps its place
        .overlay(alignment: s == stops - 1 ? .leading : .trailing) {
            if s == marked {
                DefaultMark(theme: theme)
                    .fixedSize()
                    .frame(width: 0, alignment: s == stops - 1 ? .trailing : .leading)
                    .offset(x: s == stops - 1 ? -4 : 4, y: 0.5)
            }
        }
    }

    static func color(_ paint: Paint?) -> Color {
        switch paint {
        case .rainbow: Color(CC.rainbow[5])
        case let .shimmer(base, _): Color(base)
        case let .plain(rgb): Color(rgb)
        case nil: .white
        }
    }

    @ViewBuilder static func fill(_ paint: Paint?) -> some View {
        switch paint {
        case .rainbow:
            LinearGradient(colors: CC.rainbow.map(Color.init), startPoint: .leading, endPoint: .trailing)
        case let .shimmer(base, highlight):
            LinearGradient(colors: [Color(base).opacity(0.7), Color(base), Color(highlight)], startPoint: .leading, endPoint: .trailing)
        case let .plain(rgb):
            LinearGradient(colors: [Color(rgb).opacity(0.55), Color(rgb)], startPoint: .leading, endPoint: .trailing)
        case nil:
            Color.white.opacity(0.5)
        }
    }
}

/// the permission modes as claude's code view names them, side by side in one control, each as wide
/// as its name. the picked one sits on a pill tinted in its colour (claude code's colours) that
/// slides from mode to mode; the one the settings choose is marked "default". what a mode does shows
/// on hover.
private struct ModePicker: View {
    let modes: [Choice]
    let picked: Int
    let marked: Int?
    let theme: AppTheme
    let pick: (Int) -> Void
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.offset) { i, c in
                segment(c, on: i == picked, isDefault: i == marked)
                    .contentShape(Rectangle())
                    .onTapGesture { pick(i) }
                    .help(c.detail ?? c.label)
            }
        }
        .padding(2)
        .frame(width: OptionsSection.controlWidth)
        .background(theme.controlTrack, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairlineBorder, lineWidth: 0.5))
        .animation(Motion.value, value: picked)
    }

    private func segment(_ c: Choice, on: Bool, isDefault: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(theme.say(c.label))
                .font(theme.chip)
                .fontWeight(on ? .semibold : .regular)
                .foregroundStyle(on ? color(c) : theme.textSecondary)
            if isDefault { DefaultMark(theme: theme) }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background {
            if on {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPlain(c) ? Color.white.opacity(0.11) : color(c).opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isPlain(c) ? Color.white.opacity(0.08) : color(c).opacity(0.35), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                    .matchedGeometryEffect(id: "thumb", in: thumb)
            }
        }
    }

    private func color(_ c: Choice) -> Color {
        if case let .plain(rgb) = c.paint, rgb != CC.inactive { return Color(rgb) }
        return theme.text
    }

    private func isPlain(_ c: Choice) -> Bool {
        if case let .plain(rgb) = c.paint { return rgb == CC.inactive }
        return true
    }
}

// MARK: painted text

/// text painted as claude code paints it: one colour, a shimmer (a lighter letter running through,
/// its neighbours bold) or the rainbow moving letter by letter, both stepping every 100 ms as the
/// terminal does.
struct PaintedText: View {
    let text: String
    let paint: Paint?
    let font: Font
    var bold = false

    var body: some View {
        switch paint {
        case let .plain(rgb):
            Text(text).font(font).bold(bold).foregroundStyle(Color(rgb))
        case nil:
            Text(text).font(font).bold(bold)
        case let .shimmer(base, highlight):
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let letters = Array(text)
                let tick = Int(context.date.timeIntervalSinceReferenceDate * 10)
                let at = tick % (letters.count + 4)
                letters.enumerated().reduce(Text("")) { line, item in
                    let (i, ch) = item
                    let lit = i == at
                    let near = i == at - 1 || i == at + 1
                    return line + Text(String(ch))
                        .foregroundColor(Color(lit ? highlight : base))
                        .fontWeight(bold || lit || near ? .bold : .regular)
                }
                .font(font)
            }
        case .rainbow:
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate * 10)
                Array(text).enumerated().reduce(Text("")) { line, item in
                    let (i, ch) = item
                    return line + Text(String(ch)).foregroundColor(Color(CC.rainbow[(i + tick) % CC.rainbow.count]))
                }
                .font(font)
                .bold()
            }
        }
    }
}

extension Color {
    init(_ rgb: RGB) { self.init(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255) }
}
