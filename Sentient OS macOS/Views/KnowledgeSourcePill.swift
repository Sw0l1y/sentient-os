//
// KnowledgeSourcePill.swift
// One knowledge source as an Internet Accounts row: the real app icon or brand logo, the source's
// name and state, and one trailing control (a switch, "Set Up…"/"Manage…", a Remove button, or a
// lock). Shared by Settings and onboarding; it always sits inside a Form Section.
// A green check means selected for analysis, not verified access.
// Doc: Settings/Documentation - Settings.md
//

import SwiftUI
import AppKit

struct KnowledgeSourcePill: View {
    let label: String
    var detail: String? = nil
    var asset: String? = nil
    var systemImage = "puzzlepiece.extension"
    var iconPath: String? = nil
    var selected = false
    var featured = false                 // accepted; every row has the same weight now
    var locked = false
    var isAction = false
    var trailingSymbol: String? = nil
    let action: () -> Void
    /// The trailing control is a switch (folders, Apple Notes, SiYuan).
    var toggles = false
    /// A folder on this Mac: shows Finder's icon for it.
    var folderPath: String? = nil
    /// The source needs a look (reconnect, access, synced data): an orange triangle beside "Manage…".
    var needsAttention = false

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            TileLabel(label, subtitle: detail) {
                Self.icon(asset: asset, systemImage: systemImage, iconPath: iconPath, folderPath: folderPath, size: 20)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityStatus)
        .help(helpText)
    }

    // MARK: - Trailing control

    @ViewBuilder private var trailing: some View {
        if locked {
            HStack(spacing: Space.s) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Locked")
                InfoPopoverButton(CodexAuth.connectorLockedTip)
            }
        } else if isAction {
            Button(label, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else if let trailingSymbol {
            Button(action: action) {
                Image(systemName: trailingSymbol)
            }
            .buttonStyle(.borderless)
            .help("Remove \(label)")
            .accessibilityLabel("Remove \(label)")
        } else if toggles {
            Toggle(label, isOn: Binding(get: { selected }, set: { _ in action() }))
                .toggleStyle(.switch)
                .labelsHidden()
        } else {
            HStack(spacing: Space.s) {
                if needsAttention {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Needs attention")
                } else if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Selected")
                }
                Button(selected ? "Manage…" : "Set Up…", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var accessibilityStatus: String {
        if locked { return CodexAuth.connectorLockedTip }
        if isAction { return "" }
        return "\(selected ? "Selected for analysis" : "Not selected")\(detail.map { ", \($0)" } ?? "")"
    }

    private var helpText: String {
        if locked { return CodexAuth.connectorLockedTip }
        if isAction { return label }
        return selected ? "Selected for analysis and nightly updates." : "Choose how Sentient uses \(label)."
    }

    // MARK: - Icon

    /// The four Apple assets stand for installed apps, which show their real icons.
    private static let appleApps: [String: String] = [
        "AppleMailMark": "com.apple.mail",
        "AppleCalendarMark": "com.apple.iCal",
        "AppleNotesMark": "com.apple.Notes",
        "IMessageMark": "com.apple.MobileSMS",
    ]

    /// Exported app icons that already carry their own shape (no white plate behind them).
    private static let appIconAssets: Set<String> = ["WhatsAppMark", "SiYuanMark"]

    /// A source's icon at `size` (20 in rows, 40 in the access sheet's header), first match wins:
    /// a folder's Finder icon, a real Apple app icon, an exported app icon, a brand logo on a white
    /// plate, a connector's own icon file, else a gray symbol tile.
    @ViewBuilder static func icon(asset: String?, systemImage: String = "puzzlepiece.extension",
                                  iconPath: String? = nil, folderPath: String? = nil,
                                  size: CGFloat) -> some View {
        if let folderPath {
            AppIconImage(fileAt: folderPath, size: size)
        } else if let asset, let bundleID = appleApps[asset] {
            AppIconImage(bundleID: bundleID, size: size)
        } else if let asset, appIconAssets.contains(asset) {
            ConnectorLogo(asset: asset, size: size)
        } else if let asset {
            LogoTile(size: size) { ConnectorLogo(asset: asset, size: size * 0.7) }
        } else if let iconPath, let image = NSImage(contentsOfFile: iconPath) {
            LogoTile(size: size) { Image(nsImage: image).resizable().scaledToFit() }
                .accessibilityHidden(true)
        } else {
            IconTile(symbol: systemImage, color: .gray, size: size)
        }
    }
}

#Preview("Source rows") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            Form {
                Section("Email & Calendar") {
                    KnowledgeSourcePill(label: "Gmail", asset: "GmailMark", selected: true, action: {})
                    KnowledgeSourcePill(label: "Apple Mail", detail: "2 accounts", asset: "AppleMailMark", action: {})
                    KnowledgeSourcePill(label: "Google Calendar", detail: "Connection needs attention",
                                        asset: "GoogleCalendarMark", selected: true, action: {}, needsAttention: true)
                    KnowledgeSourcePill(label: "Outlook Calendar", asset: "OutlookMark", locked: true, action: {})
                }
                Section("Folders on This Mac") {
                    KnowledgeSourcePill(label: "Desktop", selected: true, action: {}, toggles: true,
                                        folderPath: NSHomeDirectory() + "/Desktop")
                    KnowledgeSourcePill(label: "Projects", selected: true, trailingSymbol: "xmark.circle.fill",
                                        action: {}, folderPath: NSHomeDirectory())
                }
            }
            .formStyle(.grouped)
            .frame(width: 520, height: 420)
            .environment(\.colorScheme, scheme)
        }
    }
}
