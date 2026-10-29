//
// ConnectorSheetChrome.swift
// The Internet Accounts add-account sheet frame every connector sheet shares: a centered logo
// header, a bottom button bar, the logo choice, and a checklist row. Chrome only: each sheet
// still writes its own branches and decides which buttons it passes in.
// Doc: Documentation - Views - Home, Processing & Shared UI.md
//

import SwiftUI

/// The add-account sheet header (Internet Accounts): a 40 pt logo, a .title2.bold() title and one
/// .body .secondary line, centered.
struct ConnectorSheetHeader<Logo: View>: View {
    private let title: String
    private let message: String?
    private let logo: Logo

    init(_ title: String, message: String? = nil, @ViewBuilder logo: () -> Logo) {
        self.title = title
        self.message = message
        self.logo = logo()
    }

    var body: some View {
        VStack(spacing: Space.m) {
            logo.frame(width: 40, height: 40)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.s)
    }
}

/// The 40 pt logo that a connector sheet's header shows.
///  - An Apple app asset (ConnectorLogo.appleAppBundleID(for:) != nil): ConnectorLogo(asset:, size: 40),
///    which draws the real app icon and is never put on a tile.
///  - Any other asset: LogoTile(size: 40) { ConnectorLogo(asset:, size: 28) }.
///  - nil: IconTile(TileSpec.method(.mcp), size: 40).
struct ConnectorSheetLogo: View {
    private let asset: String?
    private let size: CGFloat

    init(asset: String?, size: CGFloat = 40) {
        self.asset = asset
        self.size = size
    }

    var body: some View {
        Group {
            if let asset, ConnectorLogo.appleAppBundleID(for: asset) != nil {
                ConnectorLogo(asset: asset, size: size)
            } else if let asset {
                LogoTile(size: size) { ConnectorLogo(asset: asset, size: size * 0.7) }
            } else {
                IconTile(TileSpec.method(.mcp), size: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The bottom button bar: leading secondary actions, a Spacer, then the trailing Cancel and primary buttons.
struct ConnectorSheetFooter<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.s) {
            leading
            Spacer(minLength: Space.m)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Space.l)
    }
}

extension ConnectorSheetFooter where Leading == EmptyView {
    init(@ViewBuilder trailing: () -> Trailing) {
        self.init(leading: { EmptyView() }, trailing: trailing)
    }
}

/// One checklist row: an optional icon, a title, an optional state subtitle and a trailing accent
/// checkmark. The whole row toggles.
struct ConnectorCheckRow<Icon: View>: View {
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool
    private let icon: Icon

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
        self.icon = icon()
    }

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Space.m) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.s)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(isOn ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityValue(isOn ? "Selected" : "Not Selected")
    }
}

extension ConnectorCheckRow where Icon == EmptyView {
    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.init(title, subtitle: subtitle, isOn: isOn) { EmptyView() }
    }
}

// MARK: - Previews (light and dark side by side)

private struct ConnectorChromePreviewPair<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                content()
                    .frame(maxWidth: .infinity)
                    .background(.background)
                    .environment(\.colorScheme, scheme)
            }
        }
    }
}

#Preview("Sheet header") {
    ConnectorChromePreviewPair {
        ConnectorSheetHeader("Connect Notion", message: "Sign in to Notion in your browser, and then come back to Sentient.") {
            ConnectorSheetLogo(asset: "NotionMark")
        }
    }
    .frame(width: 900)
}

#Preview("Sheet logos") {
    ConnectorChromePreviewPair {
        HStack(spacing: Space.l) {
            ConnectorSheetLogo(asset: "AppleMailMark")
            ConnectorSheetLogo(asset: "GmailMark")
            ConnectorSheetLogo(asset: "WhatsAppMark")
            ConnectorSheetLogo(asset: nil)
        }
        .padding(Space.xl)
    }
    .frame(width: 640)
}

#Preview("Sheet footer") {
    ConnectorChromePreviewPair {
        ConnectorSheetFooter {
            Text("2 selected").font(.callout).foregroundStyle(.secondary)
        } trailing: {
            Button("Cancel", role: .cancel) {}.keyboardShortcut(.cancelAction)
            Button("Done") {}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }
    .frame(width: 900)
}

#Preview("Check rows") {
    ConnectorChromePreviewPair {
        Form {
            Section("Accounts") {
                ConnectorCheckRow("Work", isOn: .constant(true)) { IconTile(.emailAndCalendar) }
                ConnectorCheckRow("Personal", subtitle: "DM · 12 messages", isOn: .constant(false)) {
                    IconTile(.emailAndCalendar)
                }
                ConnectorCheckRow("Family", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
    }
    .frame(width: 900, height: 260)
}
