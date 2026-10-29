//
//  SetupAssistantPage.swift
//  Sentient OS macOS
//
//  The Setup Assistant page (SPEC-00 3.10): a centered column with a 64 pt tile, a large title, a
//  message and the content, and a footer pinned to the bottom (Back at the left, the primary
//  action at the right). Used by onboarding steps, gates, the computer-use upgrade, the uninstall
//  sheet and ComputerUseDoctor; not by sidebar pages. The page draws no background.
//

import SwiftUI

struct SetupAssistantPage<Content: View, Footer: View>: View {
    private let tile: TileSpec?
    private let title: String
    private let message: String?
    private let width: CGFloat
    private let content: Content
    private let footer: Footer
    private var hasFooter = true

    init(tile: TileSpec?, title: String, message: String? = nil, width: CGFloat = PageMetrics.setupPage,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.tile = tile
        self.title = title
        self.message = message
        self.width = width
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let tile {
                    IconTile(tile, size: 64)
                        .padding(.bottom, 16)
                }
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24)
            }
            .frame(maxWidth: width)
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasFooter {
                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
        }
    }
}

extension SetupAssistantPage where Footer == EmptyView {
    init(tile: TileSpec?, title: String, message: String? = nil, width: CGFloat = PageMetrics.setupPage,
         @ViewBuilder content: () -> Content) {
        self.init(tile: tile, title: title, message: message, width: width, content: content) { EmptyView() }
        self.hasFooter = false
    }
}

/// Back (`.bordered` `.large`) when `back` is set, then `leading` (a footnote such as "Read More ·
/// Configure…" or "3 of 3 minimum chosen"), then the primary button (`.borderedProminent`
/// `.large`, the default action, disabled unless `primaryEnabled`).
struct SetupAssistantFooter<Leading: View>: View {
    private let primaryTitle: String
    private let primaryEnabled: Bool
    private let primaryID: String?
    private let backTitle: String
    private let back: (() -> Void)?
    private let leading: Leading
    private let primary: () -> Void

    init(primaryTitle: String, primaryEnabled: Bool = true, primaryID: String? = nil,
         backTitle: String = "Back", back: (() -> Void)? = nil,
         @ViewBuilder leading: () -> Leading, primary: @escaping () -> Void) {
        self.primaryTitle = primaryTitle
        self.primaryEnabled = primaryEnabled
        self.primaryID = primaryID
        self.backTitle = backTitle
        self.back = back
        self.leading = leading()
        self.primary = primary
    }

    var body: some View {
        HStack(spacing: 12) {
            if let back {
                Button(backTitle, action: back)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            leading
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let button = Button(primaryTitle, action: primary)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!primaryEnabled)
        if let primaryID {
            button.accessibilityIdentifier(primaryID)
        } else {
            button
        }
    }
}

extension SetupAssistantFooter where Leading == EmptyView {
    init(primaryTitle: String, primaryEnabled: Bool = true, primaryID: String? = nil,
         backTitle: String = "Back", back: (() -> Void)? = nil, primary: @escaping () -> Void) {
        self.init(primaryTitle: primaryTitle, primaryEnabled: primaryEnabled, primaryID: primaryID,
                  backTitle: backTitle, back: back, leading: { EmptyView() }, primary: primary)
    }
}

#Preview("Setup Assistant page") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            SetupAssistantPage(tile: .setupChooseAI, title: "Choose Your AI",
                               message: "Sentient uses the AI you already pay for.") {
                Text("Content goes here, leading-aligned at full column width.")
            } footer: {
                SetupAssistantFooter(primaryTitle: "Continue", back: {}) {
                    Text("1 of 3 chosen")
                } primary: {}
            }
            .frame(width: 640, height: 480)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
}
