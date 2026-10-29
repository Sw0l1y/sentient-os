//
//  SettingsComponents.swift
//  Sentient OS macOS
//
//  The legacy Settings vocabulary, rebuilt on the system's own form primitives (Section,
//  LabeledContent, Toggle, DisclosureGroup, StatusRow, InfoPopoverButton). Every type keeps its
//  init so callers in other areas keep compiling; inside Settings (`settingsFormStyle == true`,
//  set by SettingsView) they emit real grouped-Form Sections and rows, and outside a Form they draw
//  the same content in a GroupBox.
//  Doc: Documentation - Settings.md
//

import SwiftUI
import AppKit

/// True while rendering inside Settings' grouped Form (SettingsView sets it). Outside Settings it
/// stays false, so onboarding, gates and invitations get GroupBoxes instead of bare Sections.
private struct SettingsFormStyleKey: EnvironmentKey {
    static let defaultValue = false
}

/// Kept for source compatibility; nothing reads it any more.
private struct SettingsHeadingStyleKey: EnvironmentKey {
    static let defaultValue = false
}

/// Kept for source compatibility; nothing reads it any more.
private struct SettingsCompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsFormStyle: Bool {
        get { self[SettingsFormStyleKey.self] }
        set { self[SettingsFormStyleKey.self] = newValue }
    }

    var settingsHeadingStyle: Bool {
        get { self[SettingsHeadingStyleKey.self] }
        set { self[SettingsHeadingStyleKey.self] = newValue }
    }

    var settingsCompactLayout: Bool {
        get { self[SettingsCompactLayoutKey.self] }
        set { self[SettingsCompactLayoutKey.self] = newValue }
    }
}

enum SettingsStyle {
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let border = Color(nsColor: .separatorColor)
    static let control = Color(nsColor: .controlBackgroundColor)
}

/// A Settings pane: one centered grouped Form. The window title names the pane, so `title` is not
/// drawn; a non-empty `whisper` becomes the first Section's footer. `legacyLayout` is ignored.
struct SettingsPane<Content: View>: View {
    let title: String
    var whisper: String? = nil
    var legacyLayout = false
    @ViewBuilder var content: Content

    var body: some View {
        PaneForm {
            if let whisper, !whisper.isEmpty {
                Section {} footer: { Text(whisper) }
            }
            content
        }
        .environment(\.settingsFormStyle, true)
    }
}

/// A group of related settings. Inside a Form it is a `Section` (label as header, description as
/// footer); outside one it is a headline, a GroupBox and a footnote. `inset` and `destructive` are
/// accepted for compatibility: destructive buttons carry their own role.
struct SettingsGroup<Content: View, Trailing: View>: View {
    @Environment(\.settingsFormStyle) private var inForm
    let label: String
    let badge: String?
    let description: String?
    let inset: CGFloat
    let destructive: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    init(label: String, badge: String? = nil, description: String? = nil,
         inset: CGFloat = 20, destructive: Bool = false,
         @ViewBuilder content: () -> Content,
         @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.badge = badge
        self.description = description
        self.inset = inset
        self.destructive = destructive
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        if inForm {
            Section {
                content
            } header: {
                header
            } footer: {
                if let description { Text(description) }
            }
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                header
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                GroupBox {
                    VStack(alignment: .leading, spacing: Space.s) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            Text(label)
            if let badge {
                Text(badge).foregroundStyle(.secondary)
            }
            if Trailing.self != EmptyView.self {
                Spacer(minLength: Space.m)
                trailing
            }
        }
    }
}

extension SettingsGroup where Trailing == EmptyView {
    init(label: String, badge: String? = nil, description: String? = nil,
         inset: CGFloat = 20, destructive: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(label: label, badge: badge, description: description, inset: inset,
                  destructive: destructive, content: content, trailing: { EmptyView() })
    }
}

/// A secondary explanatory line.
struct SettingsProse: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A labeled control row. A subtitle is drawn by macOS as the label's secondary line.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
    }
}

/// A switch row with a secondary line.
struct SettingToggleLine: View {
    let title: String
    let sub: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
            Text(sub)
        }
        .toggleStyle(.switch)
    }
}

/// A standard push button: small inside a Form row, regular outside. `tint` is accepted and ignored.
struct SettingsPillButton: View {
    @Environment(\.settingsFormStyle) private var inForm
    let title: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(inForm ? .small : .regular)
    }
}

/// The standard bordered push button. `tint` is accepted and ignored (state belongs to a label or
/// a glyph, never a button color).
struct SettingsActionStyle: PrimitiveButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.bordered)
    }
}

/// A standard menu picker with the same border, height, and type as action buttons.
struct SettingsMenu<Selection: Hashable, Options: View>: View {
    let title: String
    let value: String
    @Binding var selection: Selection
    @ViewBuilder var options: Options

    var body: some View {
        Picker(title, selection: $selection) { options }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityValue(value)
            .accessibilityIdentifier("settings.menu." + title)
    }
}

/// Extra explanation behind a standard disclosure, collapsed by default.
struct SettingsDetails<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(title, isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: Space.s) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Wraps views onto as many rows as the width needs, like text. Kept for its outside callers.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? max(0, x - spacing) : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The instant explanation shown over a locked (knowledge-base-only) connector, which the Analysis
/// popover overlays on hover.
struct LockedChipTip: View {
    var body: some View {
        Text(CodexAuth.connectorLockedTip)
            .font(.callout)
            .padding(Space.m)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
            .fixedSize()
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

/// A small status dot. Kept for outside callers; status rows use StatusRow's tone glyphs.
struct HealthDot: View {
    /// The warning orange every status dot shares.
    static let warnAmber = Color.orange

    let color: Color

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.caption2)
            .foregroundStyle(color)
    }
}

/// Shared "warmth" for info tips: once one tip has opened, siblings open instantly for a short window.
@MainActor @Observable
final class TipWarmth {
    static let shared = TipWarmth()
    private var lastInteraction = Date.distantPast

    var isWarm: Bool { Date().timeIntervalSince(lastInteraction) < 0.5 }
    func touch() { lastInteraction = Date() }
}

/// ⓘ beside a row: the standard info popover button.
struct InfoTip: View {
    let text: String

    var body: some View {
        InfoPopoverButton(text)
    }
}

/// A status row with a verdict, its detail, an optional ⓘ and a fix button shown only while the
/// status is not OK. Renders as a StatusRow (a LabeledContent), which lays out in a Form or a stack.
struct StatusLine: View {
    enum Health { case ok, warn, bad }

    let title: String
    let health: Health
    let note: String                    // "granted" / "not granted" / "logged in"
    var tip: String? = nil              // the ⓘ explanation
    var fixTitle: String = "Fix…"
    var fix: (() -> Void)? = nil

    private var tone: StatusTone {
        switch health {
        case .ok:   return .ok
        case .warn: return .warning
        case .bad:  return .error
        }
    }

    /// Today's capitalisation rule: the note's first letter is upper-cased ("Installed · 1.2").
    private var formattedNote: String {
        note.prefix(1).uppercased() + note.dropFirst()
    }

    var body: some View {
        StatusRow(title, detail: formattedNote, tone: tone, info: tip) {
            if health != .ok, let fix {
                Button(fixTitle, action: fix)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

/// A multiline text editor that autosaves through its binding, with a placeholder while empty.
/// Inside a Form the row draws the field's background; outside it gets a hairline box.
struct SettingsTextBox: View {
    @Environment(\.settingsFormStyle) private var inForm
    let placeholder: String
    @Binding var text: String

    var body: some View {
        if inForm {
            editor
        } else {
            editor
                .padding(Space.s)
                .overlay(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                    .strokeBorder(.separator))
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.body)
            .frame(minHeight: 72)
            .scrollContentBackground(.hidden)
            .accessibilityLabel(placeholder)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// A separator. `color` and `opacity` are accepted and ignored.
struct SettingsHairline: View {
    var color: Color = .secondary
    var opacity: Double = 0.06

    var body: some View {
        Divider()
    }
}

#Preview("Settings components") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            SettingsPane(title: "Preview", whisper: "A pane whisper becomes the first footer.") {
                SettingsGroup(label: "Status", description: "Rows render as a grouped Section.") {
                    StatusLine(title: "Full Disk Access", health: .ok, note: "granted", tip: "Lets Sentient read Mail.")
                    StatusLine(title: "Screen Recording", health: .bad, note: "not granted", fixTitle: "Open Settings…") {}
                    SettingToggleLine(title: "Launch at Login", sub: "Opens quietly in the menu bar.", isOn: .constant(true))
                    SettingsRow(title: "Updates", subtitle: "Version 4.2") {
                        SettingsPillButton(title: "Check Now") {}
                    }
                    SettingsDetails(title: "What Is Shared?") { SettingsProse("Only what you choose.") }
                }
            }
            .frame(width: 560, height: 420)
            .environment(\.colorScheme, scheme)
        }
    }
}
