//
//  StatusRow.swift
//  Sentient OS macOS
//
//  One status row for Settings, Health, gates, the timing sheet and ComputerUseDoctor, so a gate
//  row and a Health row look identical (SPEC-00 3.8): StatusRow, StatusLabel, InfoPopoverButton.
//

import SwiftUI
import AppKit

/// A `LabeledContent` row: the label is a TileLabel (or a plain title and subtitle), the content is
/// the tone glyph, the accessory and an optional ⓘ.
struct StatusRow<Accessory: View>: View {
    private let title: String
    private let tile: TileSpec?
    private let detail: String?
    private let tone: StatusTone
    private let info: String?
    private let accessory: Accessory
    /// True when built by the `fixTitle:fix:` init, whose button gets `.bordered` `.small`.
    private var stylesFixButton = false

    init(_ title: String, tile: TileSpec? = nil, detail: String? = nil, tone: StatusTone,
         info: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.tile = tile
        self.detail = detail
        self.tone = tone
        self.info = info
        self.accessory = accessory()
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                ToneGlyph(tone: tone)
                if stylesFixButton {
                    accessory
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    accessory
                }
                if let info {
                    InfoPopoverButton(info, title: title)
                }
            }
        } label: {
            if let tile {
                TileLabel(title, subtitle: detail, tile: tile)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension StatusRow where Accessory == EmptyView {
    init(_ title: String, tile: TileSpec? = nil, detail: String? = nil, tone: StatusTone, info: String? = nil) {
        self.init(title, tile: tile, detail: detail, tone: tone, info: info) { EmptyView() }
    }
}

extension StatusRow where Accessory == Button<Text> {
    /// A row with one fix button (`.bordered`, `.controlSize(.small)`).
    init(_ title: String, tile: TileSpec? = nil, detail: String? = nil, tone: StatusTone, info: String? = nil,
         fixTitle: String, fix: @escaping () -> Void) {
        self.init(title, tile: tile, detail: detail, tone: tone, info: info) { Button(fixTitle, action: fix) }
        self.stylesFixButton = true
    }
}

/// The tone's glyph (or a small spinner for `.working`), labelled for VoiceOver.
private struct ToneGlyph: View {
    let tone: StatusTone

    var body: some View {
        if let symbol = tone.symbol {
            Image(systemName: symbol)
                .foregroundStyle(tone.color)
                .accessibilityLabel(tone.accessibilityLabel)
        } else {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(tone.accessibilityLabel)
        }
    }
}

/// A status in a line of text: the tone glyph and `.callout` text (primary for warning and error,
/// secondary otherwise).
struct StatusLabel: View {
    private let text: String
    private let tone: StatusTone
    private let systemImage: String?

    init(_ text: String, tone: StatusTone) {
        self.text = text
        self.tone = tone
        self.systemImage = nil
    }

    /// The tone's color with a different glyph (the Sensitive label's `lock.fill`).
    init(_ text: String, tone: StatusTone, systemImage: String) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(tone == .warning || tone == .error ? .primary : .secondary)
        } icon: {
            if let symbol = systemImage ?? tone.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(tone.color)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.callout)
    }
}

/// ⓘ: a borderless info button that opens a 320 pt popover with the explanation. The text is
/// selectable and inline Markdown is rendered, so links in it work.
struct InfoPopoverButton: View {
    private let text: String
    private let title: String?
    @State private var shown = false

    init(_ text: String, title: String? = nil) {
        self.text = text
        self.title = title
    }

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .help("More Info")
        .accessibilityLabel("More Info")
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Text(title)
                        .font(.headline)
                }
                Text(Self.rendered(text))
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(width: PageMetrics.popover)
        }
    }

    private static func rendered(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

#Preview("Status rows") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            Form {
                Section {
                    StatusRow("Full Disk Access", tile: .fullDiskAccess, detail: "Granted", tone: .ok,
                              info: "Lets Sentient read your [Mail](https://apple.com) and Messages.")
                    StatusRow("Screen Recording", tile: .screenRecording, tone: .error,
                              fixTitle: "Open Settings…") {}
                    StatusRow("Notifications", tile: .notifications, detail: "Off", tone: .warning)
                    StatusRow("Overnight Analysis", tone: .working)
                }
                Section {
                    StatusLabel("Kept", tone: .ok)
                    StatusLabel("Sensitive", tone: .error, systemImage: "lock.fill")
                    StatusLabel("Junk", tone: .off)
                }
            }
            .formStyle(.grouped)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 900, height: 360)
}
