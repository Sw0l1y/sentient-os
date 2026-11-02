// AnalysisRunReport.swift
// The saved account of the last finished analysis: every source it covered and every item or
// source that did not finish, with a plain reason, the next step and what the user can do. It is
// saved beside ProcessingPlan's record (`processing.report`) so the Analysis page, Home and
// Copy Details still have the detail after a relaunch. Built by ProcessingCoordinator from the
// run's RunIssue list (RunProgress.swift).
// Privacy: structure only. Item labels are a kind, an extension, a size or a sender domain at most;
// never a name, subject, path, address or message text. Codes are error type/case paths.
// Foundation only (plus UTType for file kinds), so a standalone test can compile it.
// Doc: Documentation - Ingestion Pipeline.md

import Foundation
import UniformTypeIdentifiers

nonisolated struct AnalysisRunReport: Codable, Sendable, Equatable {
    static let key = "processing.report"
    /// Items skipped for good (a damaged file) stay listed this long after the run that skipped them.
    static let carryInterval: TimeInterval = 7 * 86_400
    /// The one name Apple Mail uses everywhere (issues, sources, notices).
    static let appleMail = "Apple Mail"

    var finishedAt: Date
    /// True when nothing is left to retry (ProcessingRun.Result.complete).
    var complete: Bool
    /// Every source the run covered, in display order.
    var sources: [String]
    var issues: [RunIssue]
    /// Diagnostic event keys that marked the run (technical; Copy Details only).
    var warnings: [String] = []
    var attempted = 0
    var kept = 0
    var junk = 0
    var failed = 0

    // MARK: Per source

    enum Tone: String, Sendable { case ok, warning, info }

    /// One row of the Analysis page's source list.
    struct SourceSummary: Identifiable, Equatable, Sendable {
        let name: String
        let issues: [RunIssue]
        var id: String { name }

        /// Issues that need another try (they keep a run from being complete).
        var retrying: [RunIssue] { issues.filter { $0.attention } }
        var waitingOnMail: [RunIssue] { issues.filter { !$0.attention && $0.next == .waitingOnMail } }
        var skipped: [RunIssue] { issues.filter { !$0.attention && $0.next == .skipped } }
        /// Anything else that is not attention (an item that continues next run on its own).
        var other: [RunIssue] { issues.filter { !$0.attention && $0.next != .waitingOnMail && $0.next != .skipped } }

        /// Warning while something needs another try or waits on the user (Mail downloads);
        /// information when the only issues are skipped items; OK when there are none.
        var tone: Tone {
            if !retrying.isEmpty || !waitingOnMail.isEmpty { return .warning }
            return issues.isEmpty ? .ok : .info
        }

        /// "Up to date", "12 emails need another try · 3 waiting on Mail · 15 skipped".
        var headline: String {
            guard !issues.isEmpty else { return "Up to date" }
            var parts: [String] = []
            let unit = issues.compactMap(\.unit).first ?? "item"
            // The unit is named once, on the first count: "12 emails need another try · 3 skipped".
            func counted(_ n: Int) -> String { parts.contains { $0.first?.isNumber == true } ? n.formatted() : RunIssue.count(n, unit) }
            let retryItems = retrying.filter { $0.unit != nil }.count
            let wholeSource = retrying.first { $0.unit == nil }
            if retryItems > 0 {
                parts.append("\(counted(retryItems)) need\(retryItems == 1 ? "s" : "") another try")
            }
            if let wholeSource { parts.append(wholeSource.headline) }
            if !waitingOnMail.isEmpty { parts.append("\(counted(waitingOnMail.count)) waiting on Mail") }
            if !skipped.isEmpty { parts.append("\(counted(skipped.count)) skipped") }
            if !other.isEmpty { parts.append(counted(other.count) + " continue next time") }
            guard !parts.isEmpty else { return "Up to date" }
            let line = parts.joined(separator: " · ")
            return line.prefix(1).uppercased() + line.dropFirst()
        }

        /// Issues in display order: needs another try, waiting on Mail, skipped, the rest.
        var ordered: [RunIssue] {
            let rank: (RunIssue) -> Int = { issue in
                issue.unit == nil ? 0 : issue.attention ? 1 : issue.next == .waitingOnMail ? 2 : issue.next == .skipped ? 3 : 4
            }
            return issues.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
        }

        /// Issues grouped by what happened, for a compact list: one group per problem, next step
        /// and remedy, with every item label it covers.
        var groups: [IssueGroup] {
            var order: [String] = [], members: [String: [RunIssue]] = [:]
            for issue in ordered {
                let key = [issue.problem, issue.next.rawValue, issue.nextNote ?? "", issue.remedy,
                           issue.attention ? "1" : "0"].joined(separator: "\u{0}")
                if members[key] == nil { order.append(key) }
                members[key, default: []].append(issue)
            }
            return order.map { IssueGroup(issues: members[$0] ?? []) }
        }
    }

    /// Issues that share a problem, next step and remedy.
    struct IssueGroup: Identifiable, Equatable, Sendable {
        let issues: [RunIssue]
        var id: String { issues.first?.id ?? "" }
        var first: RunIssue { issues[0] }
        /// "12 emails", "1 file", or nil for a whole-source issue.
        var countLabel: String? { first.unit.map { RunIssue.count(issues.count, $0) } }
        /// The group's next step: retries name the soonest pending one.
        func nextStep(now: Date = Date()) -> String {
            guard first.next == .retry, first.nextNote == nil else { return first.nextStep }
            let pending = issues.compactMap(\.retryAt).filter { $0 > now }
            guard pending.count == issues.count, let soonest = pending.min() else { return "Tried again during the next analysis" }
            return issues.count == 1 ? first.nextStep : "Tried again automatically, the first after " + RunIssue.dateLabel(soonest)
        }
        /// Item labels, at most `limit`, then "and N more".
        func itemLine(limit: Int = 4) -> String? {
            let labels = issues.compactMap(\.item)
            guard !labels.isEmpty else { return nil }
            let shown = labels.prefix(limit).joined(separator: "; ")
            return labels.count > limit ? shown + "; and \(labels.count - limit) more" : shown
        }
        /// Every distinct technical code, most frequent first.
        var codes: String {
            var counts: [String: Int] = [:]
            for issue in issues { counts[issue.code, default: 0] += 1 }
            return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
                .map { $0.value > 1 ? "\($0.key) ×\($0.value)" : $0.key }.joined(separator: ", ")
        }
    }

    var summaries: [SourceSummary] {
        var names = sources
        for issue in issues where !names.contains(issue.source) { names.append(issue.source) }
        return names.map { name in SourceSummary(name: name, issues: issues.filter { $0.source == name }) }
    }

    /// Sources that need another try, then those waiting on the user, in display order.
    var warningSummaries: [SourceSummary] { summaries.filter { $0.tone == .warning } }

    /// One short line per source that needs attention: "Apple Mail: 12 emails need another try".
    var attentionLines: [String] { warningSummaries.map { "\($0.name): " + Self.lowercasedFirst($0.headline) } }

    /// Lowers a headline's first letter for use after "Source: " (numbers stay as they are).
    static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first, !first.isNumber else { return text }
        return first.lowercased() + text.dropFirst()
    }

    // MARK: Building

    /// The report for a finished run. Apple Mail lists its whole queue (the run rebuilt it from its
    /// checkpoints); another source's items skipped for good stay listed for `carryInterval` after
    /// the run that skipped them. A whole-source failure the run recorded only as a
    /// `sourceReadFailures` message becomes an issue here.
    static func build(progress: RunProgress, sources: [String], complete: Bool,
                      previous: AnalysisRunReport?, now: Date = Date()) -> AnalysisRunReport {
        var issues = progress.issues.map { issue -> RunIssue in
            var issue = issue
            if issue.since == nil { issue.since = now }
            return issue
        }
        let wholeSources = Set(issues.filter { $0.unit == nil }.map(\.source))
        for name in progress.sourceReadFailures.keys.sorted() where !wholeSources.contains(name) {
            issues.append(.sourceUnread(name, message: progress.sourceReadFailures[name] ?? ""))
        }
        if let previous {
            let present = Set(issues.map(\.id))
            let reread = progress.mailChecked ? Set([appleMail]) : Set<String>()
            for old in previous.issues where old.next == .skipped && !present.contains(old.id) && !reread.contains(old.source) {
                guard let since = old.since, now.timeIntervalSince(since) < carryInterval else { continue }
                var carried = old
                carried.attention = false
                issues.append(carried)
            }
        }
        var names: [String] = []
        for name in sources + issues.map(\.source) where !names.contains(name) { names.append(name) }
        return AnalysisRunReport(finishedAt: now, complete: complete, sources: names, issues: issues,
                                 warnings: progress.warnings, attempted: progress.done, kept: progress.survivors,
                                 junk: progress.junk, failed: progress.failed)
    }

    /// Replace one source's issues (Apple Mail after Skip These or Retry Now).
    func replacingIssues(_ replacement: [RunIssue], for source: String) -> AnalysisRunReport {
        var copy = self
        copy.issues = issues.filter { $0.source != source } + replacement
        if !copy.sources.contains(source) { copy.sources.append(source) }
        return copy
    }

    // MARK: Copy Details

    /// A plain-text report for Copy Details: every source, every issue with its technical code,
    /// and the diagnostic keys. Structure only (see the file header).
    func plainText(appVersion: String? = nil) -> String {
        var lines = ["Sentient analysis report"]
        lines.append("Finished: " + RunIssue.dateLabel(finishedAt) + " · " + (complete ? "Complete" : "Needs attention"))
        if let appVersion { lines.append("App version: " + appVersion) }
        lines.append("Items analyzed: \(attempted.formatted()) · kept \(kept.formatted()) · junk \(junk.formatted()) · failed \(failed.formatted())")
        lines.append("")
        lines.append("Sources")
        for summary in summaries { lines.append("- \(summary.name): \(summary.headline)") }
        for summary in summaries where !summary.issues.isEmpty {
            lines.append("")
            lines.append(summary.name)
            for issue in summary.ordered {
                lines.append("- " + (issue.item ?? "Whole source"))
                lines.append("  Problem: " + issue.problem)
                lines.append("  Next step: " + issue.nextStep)
                lines.append("  What you can do: " + issue.remedy)
                lines.append("  Code: " + issue.code + (issue.tries.map { " · \($0) \($0 == 1 ? "try" : "tries")" } ?? ""))
            }
        }
        if !warnings.isEmpty {
            lines.append("")
            lines.append("Diagnostic events during this run (background checks do not mark it incomplete):")
            for warning in warnings { lines.append("- " + warning) }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Saving

    static func read(_ defaults: UserDefaults = .standard) -> AnalysisRunReport? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func save(_ report: AnalysisRunReport?, to defaults: UserDefaults = .standard) {
        guard let report else { defaults.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(report) { defaults.set(data, forKey: key) }
    }
}

// MARK: - Issue constructors shared by the run

nonisolated extension RunIssue {
    /// A whole source that was not read; its message is the advice the run already gives.
    static func sourceUnread(_ source: String, message: String) -> RunIssue {
        RunIssue(id: "source:" + source, source: source, unit: nil, item: nil,
                 problem: "This source wasn’t read during this analysis.", next: .nextRun,
                 remedy: message.isEmpty ? "Review it in Knowledge Sources, then retry." : message,
                 code: "sourceReadFailure", attention: true)
    }

    /// A source stopped at its time limit; the next analysis continues from its checkpoint.
    static func timeLimit(_ source: String, minutes: Int) -> RunIssue {
        RunIssue(id: "source:" + source, source: source, unit: nil, item: nil,
                 problem: "Reached its \(minutes)-minute limit for one analysis; more items remain.", next: .nextRun,
                 remedy: "Nothing to do. Completed items are saved and the next analysis continues.",
                 code: "source.hit_time_cap", attention: true)
    }

    /// A file the run could not read or analyze. Files are not retried: the folder checkpoint
    /// moves past them (IterativeRun), so the next step says what brings one back.
    static func skippedFile(source: String, path: String?, stage: FileStage, code: String) -> RunIssue {
        let problem: String
        switch stage {
        case .timeout: problem = "Reading this file took longer than 30 seconds."
        case .extract: problem = "The file couldn’t be read or turned into text."
        case .generate: problem = "The on-device model failed while analyzing it."
        case .reply: problem = "The on-device model’s answer couldn’t be used."
        }
        return RunIssue(id: "file:" + source + ":" + RunIssue.opaqueID(path ?? UUID().uuidString), source: source,
                        unit: "file", item: fileLabel(path: path), problem: problem, next: .skipped,
                        nextNote: "Not tried again", remedy: stage == .timeout || stage == .extract
                            ? "Check that the file opens. To analyze it again, move it out of the folder and back in."
                            : "To analyze it again, move it out of the folder and back in.",
                        code: code, attention: true)
    }

    enum FileStage: Sendable { case timeout, extract, generate, reply }

    /// "PDF document (.pdf) · 2.3 MB". Never the file name or folder.
    static func fileLabel(path: String?) -> String {
        guard let path else { return "File" }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        var label = ext.isEmpty ? "File" : (UTType(filenameExtension: ext)?.localizedDescription.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "File")
        if !ext.isEmpty { label += " (.\(ext))" }
        if let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue {
            label += " · " + RunIssue.size(size)
        }
        return label
    }

    /// A stable identifier that does not spell out a path: an FNV-1a hash.
    static func opaqueID(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }
}
