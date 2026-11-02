// AnalysisSourcesSection.swift
// The Analysis page's per-source list, drawn from the saved AnalysisRunReport: each source the
// last analysis covered, "Up to date" with a checkmark or a warning with counts. A source with
// issues expands (DisclosureGroup) into a list of what happened, grouped by problem, each with its
// next step and what the user can do, plus the actions that exist for it (Open Mail, Skip These,
// Retry Now). The footer's Copy Details puts the whole report on the pasteboard as plain text.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI
import AppKit

struct AnalysisSourcesSection: View {
    let report: AnalysisRunReport
    /// A run or a queue edit is in progress: the actions wait.
    let busy: Bool
    var onRetryNow: () -> Void
    var onSkipMail: () -> Void
    var onRetryMail: () -> Void

    /// Sources whose disclosure the user flipped from its default (warnings start open).
    @State private var flipped: Set<String> = []

    var body: some View {
        Section {
            ForEach(ordered) { summary in
                if summary.issues.isEmpty {
                    LabeledContent(summary.name) { StatusLabel(summary.headline, tone: .ok) }
                        .accessibilityIdentifier("analysis.source." + summary.name)
                } else {
                    DisclosureGroup(isExpanded: expanded(summary)) {
                        ForEach(summary.groups) { group in
                            AnalysisIssueGroupRow(group: group)
                        }
                        actions(for: summary)
                    } label: {
                        LabeledContent(summary.name) {
                            StatusLabel(summary.headline, tone: Self.tone(summary.tone))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .accessibilityIdentifier("analysis.source." + summary.name)
                }
            }
        } header: {
            Text("Sources")
        } footer: {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text("Last analysis finished \(RunIssue.dateLabel(report.finishedAt)).")
                Spacer(minLength: Space.s)
                CopyButton("Copy Details", value: report.plainText(appVersion: Self.appVersion))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("analysis.copyDetails")
            }
        }
    }

    /// Sources that need something first, then skipped-only, then up to date; otherwise run order.
    private var ordered: [AnalysisRunReport.SourceSummary] {
        let rank: (AnalysisRunReport.SourceSummary) -> Int = { $0.tone == .warning ? 0 : $0.tone == .info ? 1 : 2 }
        return report.summaries.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private func expanded(_ summary: AnalysisRunReport.SourceSummary) -> Binding<Bool> {
        Binding {
            (summary.tone == .warning) != flipped.contains(summary.name)
        } set: { open in
            if open != (summary.tone == .warning) { flipped.insert(summary.name) } else { flipped.remove(summary.name) }
        }
    }

    @ViewBuilder private func actions(for summary: AnalysisRunReport.SourceSummary) -> some View {
        let isMail = summary.name == AnalysisRunReport.appleMail
        let waiting = !summary.waitingOnMail.isEmpty
        let retryingItems = summary.retrying.contains { $0.unit != nil }
        let canRetry = !summary.retrying.isEmpty || (isMail && !summary.skipped.isEmpty)
        // A School feed the school stopped sharing is fixed in Knowledge Sources, not by retrying.
        let isSchool = summary.name == SchoolFeedSource.name && !summary.retrying.isEmpty
        if (isMail && (waiting || retryingItems)) || canRetry {
            HStack(spacing: Space.s) {
                Spacer(minLength: 0)
                if isSchool {
                    Button("Manage Schoology…") { MainNavigation.shared.show(.settings, settingsPane: .sources) }
                        .accessibilityIdentifier("analysis.manageSchoology")
                }
                if isMail && waiting {
                    Button("Open Mail") { Self.openMail() }
                        .accessibilityIdentifier("analysis.openMail")
                }
                if isMail && retryingItems {
                    Button("Skip These", action: onSkipMail)
                        .help("Stop retrying these emails until the on-device model updates or you choose Retry Now.")
                        .accessibilityIdentifier("analysis.skipMail")
                }
                if canRetry {
                    Button("Retry Now", action: isMail ? onRetryMail : onRetryNow)
                        .accessibilityIdentifier("analysis.retryNow")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(busy)
        }
    }

    static func tone(_ tone: AnalysisRunReport.Tone) -> StatusTone {
        switch tone {
        case .ok: .ok
        case .warning: .warning
        case .info: .info
        }
    }

    static func openMail() {
        guard let mail = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") else { return }
        NSWorkspace.shared.openApplication(at: mail, configuration: NSWorkspace.OpenConfiguration())
    }

    private static var appVersion: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return nil }
        return version + ((info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? "")
    }
}

/// One problem inside a source: what happened, the next step, what the user can do, and the items
/// it covers (kind, size and sender domain at most).
struct AnalysisIssueGroupRow: View {
    let group: AnalysisRunReport.IssueGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(group.first.problem)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                if let count = group.countLabel {
                    Text(count).foregroundStyle(.secondary).monospacedDigit().fixedSize()
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: 2) {
                GridRow {
                    Text("Next step").foregroundStyle(.secondary)
                    Text(group.nextStep()).fixedSize(horizontal: false, vertical: true)
                }
                GridRow {
                    Text("What you can do").foregroundStyle(.secondary)
                    Text(group.first.remedy).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)
            if let items = group.itemLine() {
                Text(items)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(group.codes)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Sources") {
    let issues = [
        AppleMailCheckpoint.issue(account: "A", rowID: 1, failure: .init(cause: .reply, code: "ReplyFailure.invalidJSON", count: 3, domain: "schoology.com", bytes: 4_200), skipped: true, due: nil),
        AppleMailCheckpoint.issue(account: "A", rowID: 2, failure: .init(cause: .notDownloaded, code: "AppleMailMIME.Failure.unavailable", count: 1), skipped: false, due: Date().addingTimeInterval(1800)),
        AppleMailCheckpoint.issue(account: "A", rowID: 3, failure: .init(cause: .engine, code: "LiteRTLMError.conversation.invalidResponse.nativeNull", count: 1, domain: "example.com", bytes: 12_000), skipped: false, due: Date().addingTimeInterval(300)),
    ]
    let report = AnalysisRunReport(finishedAt: Date(), complete: false,
                                   sources: ["Apple Mail", "Downloads", "Desktop", "Apple Notes"], issues: issues)
    PaneForm(maxWidth: PageMetrics.setupPage) {
        AnalysisSourcesSection(report: report, busy: false, onRetryNow: {}, onSkipMail: {}, onRetryMail: {})
    }
    .frame(width: 680, height: 640)
}
#endif
