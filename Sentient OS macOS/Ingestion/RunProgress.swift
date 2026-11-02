// RunProgress.swift
// The complete analysis snapshot shared by local ingestion and remote source reads.
// Keeps source loading, summaries and retryable failures distinct from item verdicts.
// Doc: Documentation - Ingestion Pipeline.md

import Foundation

nonisolated struct RunProgress: Sendable {
    var total = 0
    var done = 0
    var survivors = 0
    var junk = 0
    var sensitive = 0
    var failed = 0
    var parseFailures = 0          // §7.13: junk that was actually a garbled/unparseable model reply
    var extractionFailed = 0       // §7.8/B10: item whose CONTENT extraction failed (corrupt file), not the engine
    var lastPath: String?
    var lastItemDate: Date?        // source date for the current item's preview footer
    var lastFilePath: String?      // absolute path (for the thumbnail)
    var lastPrompt: String?        // the EXACT prompt fed to the model for this item (dev prompt pane)
    var lastTitle: String?
    var lastSummary: String?
    var lastVerdict: Verdict?
    var lastSeconds: Double?
    var totalSeconds: Double = 0   // sum over successful generations (for avg)
    /// Remote reads report source state separately from per-item triage verdicts.
    nonisolated struct SourceRead: Sendable {
        enum Status: Sendable { case reading, summarized, quiet, failed }
        let name: String
        let status: Status

        var caption: String {
            switch status {
            case .reading: "READING SOURCE"
            case .summarized: "SUMMARY"
            case .quiet: "SOURCE CHECKED"
            case .failed: "NEEDS ATTENTION"
            }
        }
    }
    var sourceRead: SourceRead?
    var quietReads = 0
    var sourceReadFailures: [String: String] = [:]
    var successfulSources: Set<String> = []
    /// The run stopped early because the Mac's disk is full: either the free-space pre-flight
    /// refused to start, or a per-item commit reported `.diskFull` mid-run. Everything up to the
    /// halt is saved (marks are per-item atomic); nothing after it was read. The caller shows the
    /// disk-full screen / morning caution instead of running the cloud tail (which writes too).
    var diskFull = false
    /// Emails queued for another analysis attempt (the model or the message format failed, or an
    /// older queue entry whose reason was not recorded). These keep a run incomplete.
    var mailDeferred = 0
    var mailIncomplete = false
    /// Emails whose body Mail has not downloaded yet. They stay queued but never make a run
    /// incomplete: there is nothing to retry until Mail finishes the download.
    var mailWaitingOnMail = 0
    /// Emails the give-up rule took out of the queue (AppleMailCheckpoint.skipAfter identical failures).
    var mailSkipped = 0
    /// Emails the give-up rule skipped during this run. They failed here, but the run does not
    /// retry them, so they are not counted in `failed` and do not make the run incomplete.
    var mailSkippedNow = 0
    /// True once Apple Mail rebuilt its issue list from every account's checkpoint this run.
    var mailChecked = false
    /// Every item or source that did not finish, with a plain reason (AnalysisRunReport is built
    /// from these). Structure only: never names, subjects, paths or message text.
    var issues: [RunIssue] = []
    /// Diagnostic event keys that marked this run's operation failed (technical codes only).
    var warnings: [String] = []

    /// Replace one source's issues (Apple Mail rebuilds its list from its checkpoints).
    mutating func setIssues(_ replacement: [RunIssue], for source: String) {
        issues.removeAll { $0.source == source }
        issues += replacement
    }

    /// Add issues, replacing any with the same id (a later report of the same item wins).
    mutating func mergeIssues(_ more: [RunIssue]) {
        let ids = Set(more.map(\.id))
        issues.removeAll { ids.contains($0.id) }
        issues += more
    }

    /// One sentence naming every source that needs another try, or nil when nothing does.
    /// Unavailable sources keep their Knowledge Sources advice; item failures name the source and
    /// the count ("Apple Mail: 12 emails need another try.").
    var attentionNotice: String? {
        var parts: [String] = []
        // A source with its own whole-source issue (a time limit, Apple Mail) is named by that
        // issue's line instead of the Knowledge Sources advice.
        let explained = Set(issues.filter { $0.unit == nil }.map(\.source))
        let unread = sourceReadFailures.keys.sorted().filter { !explained.contains($0) }
        if !unread.isEmpty {
            parts.append("Review \(unread.prefix(3).joined(separator: ", ")) in Knowledge Sources, then retry or remove unavailable sources.")
        }
        for line in RunIssue.attentionLines(issues, excluding: Set(unread)).prefix(3) { parts.append(line + ".") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ") + " Completed work is saved."
    }

    /// A diagnostic event marked the run failed, but no source or item explains it: say so, with
    /// the event keys as the code, instead of leaving a generic "needs another try".
    mutating func explainWarnings() {
        guard sourceReadFailures.isEmpty, !issues.contains(where: { $0.attention }) else { return }
        let keys = warnings.prefix(3).joined(separator: ", ")
        mergeIssues([RunIssue(id: "source:Analysis", source: "Analysis", unit: nil, item: nil,
            problem: "A step of this analysis reported a problem, so it isn’t marked complete.", next: .nextRun,
            remedy: "Choose Retry Now. If it keeps happening, use Copy Details and send the report to the Sentient team.",
            code: keys.isEmpty ? "diagnostics" : "diagnostics: " + keys, attention: true)])
    }

    /// Source names that need another try, in display order (for the one-line status).
    var attentionSources: [String] {
        let unread = sourceReadFailures.keys.sorted()
        let items = RunIssue.attentionSources(issues).filter { !unread.contains($0) }
        return unread + items
    }

    /// Carry the complete card together. An update without a completed item keeps the prior card.
    mutating func updateLastItem(from progress: RunProgress) {
        guard progress.lastPath != nil else { return }
        lastPath = progress.lastPath; lastFilePath = progress.lastFilePath; lastPrompt = progress.lastPrompt
        lastItemDate = progress.lastItemDate
        lastTitle = progress.lastTitle; lastSummary = progress.lastSummary; lastVerdict = progress.lastVerdict
        lastSeconds = progress.lastSeconds; sourceRead = progress.sourceRead
    }
    mutating func beginSourceRead(name: String, label: String, prompt: String) {
        sourceRead = SourceRead(name: name, status: .reading)
        lastTitle = "Reading \(name)"
        lastSummary = "Finding and summarizing useful context."
        lastPath = label; lastPrompt = prompt
        lastItemDate = nil
        lastVerdict = nil; lastFilePath = nil; lastSeconds = nil
    }

    mutating func finishSourceRead(name: String, label: String, summary: String?, items: Int) {
        sourceReadFailures.removeValue(forKey: name)
        successfulSources.insert(name)
        // Committed windows arrive newest first. A quiet older window must not erase the
        // source's useful summary; beginSourceRead resets the card for the next source/run.
        if summary == nil, sourceRead?.name == name, sourceRead?.status == .summarized { return }
        sourceRead = SourceRead(name: name, status: summary == nil ? .quiet : .summarized)
        lastTitle = summary == nil ? "No new summary" : "\(name) summary"
        lastSummary = summary ?? "No summary to add from this sample."
        lastPath = label + (items > 0 ? " · \(items) item\(items == 1 ? "" : "s") checked" : "")
        lastVerdict = summary == nil ? nil : .survivor
        lastFilePath = nil; lastSeconds = nil
        lastItemDate = nil
    }

    mutating func failSourceRead(name: String, message: String, countFailure: Bool = true) {
        sourceRead = SourceRead(name: name, status: .failed)
        lastTitle = "\(name) needs another try"
        lastSummary = message; lastPath = name
        lastVerdict = nil; lastFilePath = nil; lastSeconds = nil; lastPrompt = nil
        lastItemDate = nil
        sourceReadFailures[name] = message
        successfulSources.remove(name)
        if countFailure { failed += 1 }
    }

    /// Preserve failures across pauses, clearing them only when that source succeeds on retry.
    mutating func mergeSourceResults(from previous: RunProgress) {
        sourceReadFailures = previous.sourceReadFailures.merging(sourceReadFailures) { _, current in current }
        for name in successfulSources { sourceReadFailures.removeValue(forKey: name) }
    }
}

/// One thing a run could not finish: an item (an email, a file, a note) or a whole source. It is
/// saved in AnalysisRunReport, listed on the Analysis page and copied by Copy Details, so it holds
/// structure only: the item label is a kind, an extension, a size or a sender domain at most,
/// never a name, subject, path, address or message text. The code is a type/case label.
nonisolated struct RunIssue: Codable, Sendable, Hashable, Identifiable {
    enum Next: String, Codable, Sendable {
        case retry          // tried again automatically (after `retryAt` when known)
        case nextRun        // the next analysis continues or retries it
        case skipped        // not tried again (the note says what lifts it)
        case waitingOnMail  // tried again once Mail has downloaded it
    }
    let id: String
    /// The source's display name ("Apple Mail", "Downloads", "iMessage").
    let source: String
    /// Singular noun used for counts ("email", "file"); nil for a whole-source issue.
    let unit: String?
    /// "Email · example.com · 14 KB", "PDF document (.pdf) · 2.3 MB"; nil for a whole-source issue.
    let item: String?
    let problem: String
    let next: Next
    var retryAt: Date?
    /// Replaces the standard next-step wording (a skipped file is not lifted by a model update).
    var nextNote: String?
    /// What the user can do about it, in a sentence.
    let remedy: String
    /// Technical code: an error type and case path ("ReplyFailure.invalidJSON").
    let code: String
    /// True when the issue keeps the run from being complete (it has to be tried again).
    var attention: Bool
    /// Failed attempts so far with this cause (Apple Mail's give-up count), when known.
    var tries: Int? = nil
    /// When a run first reported it (AnalysisRunReport carries skipped items for a while).
    var since: Date? = nil

    var nextStep: String {
        if let nextNote { return nextNote }
        switch next {
        case .retry:
            guard let retryAt, retryAt > Date() else { return "Tried again during the next analysis" }
            return "Tried again after " + Self.dateLabel(retryAt)
        case .nextRun: return "Continues during the next analysis"
        case .skipped: return "Skipped until the on-device model updates"
        case .waitingOnMail: return "Tried again once Mail downloads it"
        }
    }

    static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// "1 email" / "12 emails".
    static func count(_ n: Int, _ unit: String) -> String { "\(n.formatted()) \(unit)\(n == 1 ? "" : "s")" }

    /// Sources with issues that need another try, in first-seen order.
    static func attentionSources(_ issues: [RunIssue]) -> [String] {
        var seen = Set<String>(), order: [String] = []
        for issue in issues where issue.attention && seen.insert(issue.source).inserted { order.append(issue.source) }
        return order
    }

    /// "Apple Mail: 12 emails need attention" per source with attention issues; a source with
    /// only a whole-source issue gets that issue's short form ("Downloads: more to read next time").
    static func attentionLines(_ issues: [RunIssue], excluding: Set<String> = []) -> [String] {
        attentionSources(issues).filter { !excluding.contains($0) }.map { source in
            let items = issues.filter { $0.source == source && $0.attention && $0.unit != nil }
            guard let unit = items.first?.unit else {
                let whole = issues.first { $0.source == source && $0.attention && $0.unit == nil }
                return whole.map { "\(source): \($0.headline)" } ?? "\(source) needs another try"
            }
            return "\(source): \(count(items.count, unit)) need\(items.count == 1 ? "s" : "") attention"
        }
    }

    /// A whole-source issue's short form, for headlines and status lines.
    var headline: String {
        if code == "source.hit_time_cap" || code.hasPrefix("mail.moreHistory") || code.hasPrefix("mail.deadline") {
            return "more to read next time"
        }
        if code.hasPrefix("MailRunFailure.model") { return "the on-device model stopped" }
        if code.hasPrefix("MailRunFailure.storage") { return "progress couldn’t be saved" }
        if code.hasPrefix("mail.read") { return "couldn’t be read" }
        if code.hasPrefix("diagnostics") { return "a step reported a problem" }
        // The School feed (IterativeRun+School): codes carry statuses only, never the link.
        if code.hasPrefix("school.feed.unreachable") || code.hasPrefix("school.feed.server") { return "couldn’t be reached" }
        if code.hasPrefix("school.feed.tooLarge") { return "too large to read" }
        if code.hasPrefix("school.feed.storage") { return "couldn’t be saved" }
        if code.hasPrefix("school.feed.") { return "needs a new link" }
        return next == .nextRun ? "not read this time" : "needs another try"
    }
}

/// Diagnostics.Operation adopts this so a run can copy the event keys that marked it failed into
/// its report (Diagnostics.swift). Fixtures without it simply report no warnings.
nonisolated protocol RunWarningSource: AnyObject {
    var failureKeys: [String] { get }
}

extension RunProgress {
    static func warningKeys(_ operation: AnyObject?) -> [String] {
        (operation as? any RunWarningSource)?.failureKeys ?? []
    }
}
