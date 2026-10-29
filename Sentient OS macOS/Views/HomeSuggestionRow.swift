//
//  HomeSuggestionRow.swift
//  Sentient OS macOS
//
//  One suggestion in Today's briefing, drawn the way Mail draws a message in its list: a leading
//  icon (the real app the task runs in, the service's logo, or a tile), a provenance line, the
//  title, a two-line preview and a detail line (due date, sources, verification), with Reminders'
//  hover ✕ and one trailing action. The sealed gift is an unread row with an "Open" button.
//  Clicking the row opens the letter sheet (HomeLetterSheet). SPEC-D1 S8, S9.
//
//  Also here: `HomeSuggestionTile` (the leading icon, shared with the letter sheet header) and
//  `HomeInsetGroup` (the rounded inset container every Today block sits in).
//

import SwiftUI
import AppKit

// MARK: - The row

struct HomeSuggestionRow: View {
    let briefing: Briefing
    let action: PreparedAction?
    let phase: BriefingPhase
    var liveLines: [String] = []
    var fireDimmed = false
    let onOpen: () -> Void              // row click / "Open Letter" → the letter sheet
    let onOffer: () -> Void
    let onOpenEnvelope: () -> Void      // sealed gift "Open"
    var onStop: (() -> Void)? = nil
    var onOpenConversation: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var titleLineLimit = 2              // last, so callers may omit them (only BriefingCard sets them)
    var previewLineLimit = 2

    @State private var hovered = false
    @Environment(\.sidekickHoveredCardID) private var hoverOverride
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    private var isHovered: Bool { hovered || hoverOverride == briefing.id }
    /// The sealed gift opens through the envelope path (unseal, then the letter); every other row opens its letter.
    private func openAction() { phase == .sealed ? onOpenEnvelope() : onOpen() }
    private var reducedMotion: Bool { motionOverride ?? systemReducedMotion }
    private static let tileSize: CGFloat = 30

    var body: some View {
        Group {
            if phase == .sealed { sealedRow } else { standardRow }
        }
        .padding(.vertical, Space.m)
        .padding(.horizontal, Space.l)
        .contentShape(Rectangle())
        .onTapGesture(perform: openAction)      // child buttons win hit-testing, as on the old card
        .contextMenu {
            if phase == .sealed {
                Button("Open", action: onOpenEnvelope)
            } else {
                Button("Open Letter", action: onOpen)
                if briefing.draft != nil { Button("Copy Draft", action: copyDraft) }
            }
            if let onDismiss {
                Divider()
                Button("Dismiss", action: onDismiss)
            }
        }
        .accessibilityActions {
            if phase == .sealed {
                Button("Open", action: onOpenEnvelope)
            } else {
                Button("Open Letter", action: onOpen)
            }
            if let onDismiss { Button("Dismiss", action: onDismiss) }
        }
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { hovered = $0 }
        .animation(Motion.gated(Motion.standard, reduceMotion: reducedMotion), value: phase)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proactive.row.\(briefing.id)")
    }

    // MARK: Offer / working / done

    private var standardRow: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                HomeSuggestionTile(briefing: briefing, action: action, size: Self.tileSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(briefing.kicker)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(briefing.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(titleLineLimit)
                    Text(briefing.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(previewLineLimit)
                    detailLine
                }
                Spacer(minLength: Space.s)
                trailing
            }
            phaseStrip
                .padding(.leading, Self.tileSize + Space.m)
        }
    }

    /// Due date, source count, verification and the review flag: the facts the old card never showed.
    @ViewBuilder private var detailLine: some View {
        if let action, hasDetail(action) {
            HStack(spacing: Space.s) {
                if let due = dueText(action) {
                    Text("Due \(due)")
                        .foregroundStyle(action.urgency == .high ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                if !action.sources.isEmpty {
                    Text(action.sources.count == 1 ? "1 source" : "\(action.sources.count) sources")
                        .monospacedDigit()
                }
                if isVerified(action) {
                    Label("Verified", systemImage: "checkmark.shield")
                }
                if !action.reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Check before sending", systemImage: "exclamationmark.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.top, 2)
        }
    }

    private func dueText(_ action: PreparedAction) -> String? {
        guard let due = action.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines), !due.isEmpty else { return nil }
        return due
    }
    private func isVerified(_ action: PreparedAction) -> Bool {
        (action.status == .confirmed || action.status == .updated)
            && !action.verification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func hasDetail(_ action: PreparedAction) -> Bool {
        dueText(action) != nil || !action.sources.isEmpty || isVerified(action)
            || !action.reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The phase's one trailing button, then the hover ✕ under it.
    private var trailing: some View {
        VStack(alignment: .trailing, spacing: Space.s) {
            switch phase {
            case .offer:
                if let offer = briefing.offer {
                    Button(offer, action: onOffer)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(fireDimmed)
                        .help(fireDimmed ? "Sidekick is working on another task" : offer)
                        .accessibilityIdentifier("proactive.offer.\(briefing.id)")
                }
            case .working:
                if let onStop {
                    Button("Stop", action: onStop)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("proactive.stop.\(briefing.id)")
                }
            case .sealed, .done:
                EmptyView()
            }
            dismissButton
        }
    }

    @ViewBuilder private var dismissButton: some View {
        if let onDismiss, isHovered {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(dismissHelp)
            .accessibilityLabel("Dismiss suggestion")
            .accessibilityIdentifier("proactive.dismiss.\(briefing.id)")
        }
    }

    private var dismissHelp: String {
        if case .working = phase { return "Dismiss this card. The task will continue in Sidekick." }
        return "Dismiss this suggestion"
    }

    /// Under the text column while working (progress, the newest line, View in Chat, Details) or done.
    @ViewBuilder private var phaseStrip: some View {
        switch phase {
        case .working(let visible):
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Working…").foregroundStyle(.secondary)
                    if let line = currentLine(visible) {
                        Text(line)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    viewInChatButton
                }
                .font(.caption)
                if onOpenConversation == nil {
                    // Demo decks and showcases: their work has nowhere else to be read.
                    DisclosureGroup("Details") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(detailLines(visible).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, Space.xs)
                    }
                    .font(.caption)
                }
            }
        case .done:
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(briefing.doneTitle).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .font(.subheadline.weight(.semibold))
                if !briefing.doneBody.isEmpty {
                    Text(briefing.doneBody)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                viewInChatButton
            }
        case .sealed, .offer:
            EmptyView()
        }
    }

    @ViewBuilder private var viewInChatButton: some View {
        if let onOpenConversation {
            Button("View in Chat", action: onOpenConversation)
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityIdentifier("proactive.openChat.\(briefing.id)")
        }
    }

    private func currentLine(_ visible: Int) -> String? {
        if let last = liveLines.last { return last }
        guard !briefing.workLog.isEmpty else { return nil }
        return briefing.workLog[min(max(visible, 0), briefing.workLog.count - 1)]
    }

    private func detailLines(_ visible: Int) -> [String] {
        liveLines.isEmpty ? Array(briefing.workLog.prefix(max(visible, 0))) : Array(liveLines.suffix(5))
    }

    private func copyDraft() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(action?.preparedContent ?? briefing.draft ?? "", forType: .string)
    }

    // MARK: Sealed gift (Mail's unread row)

    private var sealedRow: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Circle().fill(.tint)
                .frame(width: 8, height: 8)
                .frame(width: 12, alignment: .leading)       // the unread gutter
                .accessibilityLabel("Unread")
            IconTile(.giftLetter, size: Self.tileSize)
            VStack(alignment: .leading, spacing: 2) {
                Text("A Gift from Your Sentient")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(recipientLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: Space.s) {
                Button("Open", action: onOpenEnvelope)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("proactive.offer.\(briefing.id)")
                dismissButton
            }
        }
    }

    /// The briefing's override first ("You" on demo decks), then the Mac account's first name.
    private var recipientLine: String {
        if let name = briefing.envelopeName { return "For \(name)" }
        return HomeView.macFirstName.isEmpty ? "For you" : "For \(HomeView.macFirstName)"
    }
}

// MARK: - The leading tile

/// The leading icon of a suggestion: the real app icon, a service logo on a LogoTile, or a TileSpec tile.
struct HomeSuggestionTile: View {
    let briefing: Briefing
    let action: PreparedAction?
    let size: CGFloat

    var body: some View {
        if briefing.kind == .welcome {
            IconTile(.giftLetter, size: size)
        } else if let action {
            methodTile(action)
        } else {
            IconTile(.demoSuggestion, size: size)
        }
    }

    @ViewBuilder private func methodTile(_ action: PreparedAction) -> some View {
        switch action.method {
        case .computer:
            if let bundleID = Self.appBundleIDs[Self.key(action.target)] {
                AppIconImage(bundleID: bundleID, size: size, fallback: .method(.computer))
            } else {
                IconTile(.method(.computer), size: size)
            }
        case .gmail:
            LogoTile(size: size) { ConnectorLogo(asset: "GmailMark", size: size * 0.7) }
        case .calendar:
            LogoTile(size: size) { ConnectorLogo(asset: "GoogleCalendarMark", size: size * 0.7) }
        case .mcp:
            if let slug = action.methodTarget, let asset = Self.connectorLogos[Self.key(slug)] {
                LogoTile(size: size) { ConnectorLogo(asset: asset, size: size * 0.7) }
            } else {
                IconTile(.method(.mcp), size: size)
            }
        case .research:
            IconTile(.method(.research), size: size)
        }
    }

    private static func key(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Computer-use targets that are Mac apps: shown with their real icon.
    private static let appBundleIDs: [String: String] = [
        "messages": "com.apple.MobileSMS",
        "mail": "com.apple.mail",
        "calendar": "com.apple.iCal",
        "notes": "com.apple.Notes",
        "whatsapp": "net.whatsapp.WhatsApp",
        "safari": "com.apple.Safari",
        "finder": "com.apple.finder",
    ]

    /// Mirrors ConnectorsSection's `logoAsset` (Views/Settings/ConnectorsSection.swift, WP7). A new
    /// connector logo must be added in both places until a shared accessor exists (SPEC-D1 6.2).
    private static let connectorLogos: [String: String] = [
        "google-drive": "GoogleDriveMark",
        "slack": "SlackMark",
        "notion": "NotionMark",
        "granola": "GranolaMark",
        "outlook-mail": "OutlookMark",
        "outlook-calendar": "OutlookMark",
    ]
}

// MARK: - The inset group

/// The rounded inset container every Today block uses. It adds no inner padding: rows pad
/// themselves; callers separate rows with inset Dividers.
struct HomeInsetGroup<Content: View>: View {
    var header: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    @Environment(\.pixelLength) private var pixelLength

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
        VStack(alignment: .leading, spacing: Space.s) {
            if let header {
                Text(header)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, Space.xs)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: pixelLength))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.xs)
            }
        }
    }
}

// MARK: - Previews

#Preview("Rows") {
    let action = PreparedAction(
        title: "Reply to Priya about Thursday",
        method: .computer, target: "Messages", urgency: .high, dueDate: "Thursday",
        status: .confirmed, verification: "Checked your iMessage thread with Priya.",
        cardSummary: "Priya asked if you’re free Thursday. You are, so I drafted a yes to send from Messages.",
        preparedContent: "Hey Priya! Thursday works great, see you at 2.",
        executionRecipe: "Open Messages, the chat with Priya, send the message above.",
        buttonText: "Send It for You?", detailLabel: "read the draft",
        sources: ["iMessage · Priya"], reviewNote: "")
    return HomeInsetGroup(header: "Today") {
        HomeSuggestionRow(briefing: Briefing(from: action), action: action, phase: .offer,
                          onOpen: {}, onOffer: {}, onOpenEnvelope: {}, onDismiss: {})
        Divider().padding(.leading, 30 + Space.m + Space.l)
        HomeSuggestionRow(briefing: Briefing.jesaiDemo[3], action: nil, phase: .working(2),
                          onOpen: {}, onOffer: {}, onOpenEnvelope: {}, onStop: {})
        Divider().padding(.leading, 30 + Space.m + Space.l)
        HomeSuggestionRow(briefing: Briefing.jesaiDemo[5], action: nil, phase: .sealed,
                          onOpen: {}, onOffer: {}, onOpenEnvelope: {})
    }
    .padding()
    .frame(width: 680)
}
