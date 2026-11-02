// AppleMailConnector.swift
// Mail opt-in and source adapter. Progress is planned by AppleMailCheckpoint and committed by
// IterativeRun with CycleStore; no cursor lives in the reader. Doc: Ingestion/Documentation - Ingestion Pipeline.md

import Foundation

nonisolated enum AppleMailSelection {
    static let key = "sources.appleMail.accounts"
    static var accounts: Set<String> {
        // Retain saved choices, but do not count or analyze Mail on unsupported macOS versions.
        guard AppleMailSource.isSupported else { return [] }
        return Set((UserDefaults.standard.string(forKey: key) ?? "").split(separator: ",")
            .map(String.init).filter { UUID(uuidString: $0) != nil }.map { $0.uppercased() })
    }
}

struct AppleMailConnector: Connector {
    nonisolated static let maximumMessagesPerPass = 600
    // The 12 KB input plus prompt, retry instruction and 1K reply fit even at one piece/byte.
    nonisolated static let contextSize = 16_384
    nonisolated static let maximumInputBytes = 12_000
    let accounts: Set<String>
    var kind: SourceKind { .appleMail }
    var maxTokens: Int { Self.contextSize }
    // The generic ItemKey Double cannot represent arbitrary Mail rowids. Mail uses its Int64
    // checkpoint path in IterativeRun, never generic timestamp pointers.
    func buckets(since marks: [String: ItemKey]) throws -> [Bucket] { throw AppleMailError.unsupportedSchema }
    func load(_ item: Candidate) throws -> Artifact { throw AppleMailError.missingBody }
}

nonisolated struct AppleMailCheckpoint: Codable, Sendable {
    var version = 2
    var classificationVersion: Int? = AppleMailSource.classificationVersion
    var generation: String
    var salt = UUID().uuidString
    var highWater: Int64
    /// Inclusive row-ID ceiling for unfinished history. Version 1 lowered it per item;
    /// version 2 keeps it fixed while backfillFloor descends through email dates.
    var backfillBefore: Int64?
    var backfillFloor: Position? = nil
    var deferred: Set<Int64> = []
    /// Applies only to unreadable/unclassified rows. Successful or rejected classification
    /// removes the entry entirely; no sensitive or junk decision is retained.
    var retrySchedule: [String: Retry]? = nil
    struct Retry: Codable, Sendable { let attempts: Int; let due: Date }
    var retryAfter: Int64 = 0
    var reconcileBefore: Int64? = nil
    var reconciledAt: Date? = nil
    /// Why each queued row failed: a cause, a technical code and coarse labels (sender domain,
    /// decoded size) only, never subjects, names, addresses or text. Nil before reasons were recorded.
    var failures: [String: Failure]? = nil
    /// Rows the give-up rule (or the user's Skip These) took out of the queue, with the reason.
    /// They are not retried until the classification version or the on-device model changes, or
    /// the user chooses Retry Now. A classification-version change resets the whole checkpoint.
    var skipped: [String: Failure]? = nil
    /// The on-device model the skips were decided with (`modelIdentity`); another model lifts them.
    var skippedModel: String? = nil

    /// A row whose model or format failure repeats this many times in a row (same cause) leaves
    /// the queue. Bodies Mail has not downloaded never give up; they wait on Mail.
    static let skipAfter = 3

    struct Failure: Codable, Sendable, Equatable {
        enum Cause: String, Codable, Sendable {
            case notDownloaded   // Mail has not downloaded the body yet (a stub or partial file)
            case unreadable      // the Mail store could not be read (access, busy, filesystem)
            case format          // an unsupported or damaged message format
            case reply           // the on-device model returned an answer that could not be used
            case engine          // the on-device model failed while generating
            case unrecorded      // queued before reasons were recorded
            /// Another attempt cannot change these, so the give-up rule may skip them.
            var givesUp: Bool { self == .format || self == .reply || self == .engine }
        }
        var cause: Cause
        var code: String
        /// Consecutive failures with this cause.
        var count = 1
        var domain: String? = nil
        var bytes: Int? = nil
    }

    /// One queued or skipped row, for the analysis report.
    struct Entry: Sendable {
        let rowID: Int64
        let failure: Failure?
        let skipped: Bool
        let due: Date?
    }

    init(generation: String, top: Int64) {
        self.generation = generation; highWater = top; backfillBefore = top
    }

    enum Phase: Sendable { case discovery, backfill, retry, reconcile }
    struct Work: Sendable { let row: AppleMailRow; let phase: Phase }

    /// Email chronology is independent of download order. Keep the full Int64 tie-breaker
    /// so equal dates resume exactly, even for row IDs that a Double cannot represent.
    struct Position: Codable, Comparable, Sendable {
        let date: Date
        let rowID: Int64

        init(_ row: AppleMailRow) { date = row.date; rowID = row.id }

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.date, lhs.rowID) < (rhs.date, rhs.rowID)
        }
    }

    private func needsBackfill(_ row: AppleMailRow) -> Bool {
        guard let before = backfillBefore, row.id <= before else { return false }
        return backfillFloor.map { Position(row) < $0 } ?? true
    }

    /// Disjoint frontiers: new inserts cannot erase unfinished backfill. A rowid is meaningful
    /// only within one Envelope Index UUID. Rebuilds reset traversal while survivor identities live.
    mutating func prepare(generation: String, rows: [AppleMailRow], now: Date,
                          limit: Int = AppleMailConnector.maximumMessagesPerPass, model: String? = nil) -> [Work] {
        let top = rows.map(\.id).max() ?? 0
        if self.generation != generation || top < highWater || classificationVersion != AppleMailSource.classificationVersion {
            let savedSalt = salt
            self = AppleMailCheckpoint(generation: generation, top: top)
            salt = savedSalt
        }
        // An interrupted version-1 run already completed every row above its ceiling.
        // Sort only its remaining history by date, preserving discovery/retry progress.
        version = 2
        let existing = Set(rows.filter { !$0.excluded || $0.previewJunk }.map(\.id))
        deferred.formIntersection(existing)
        retrySchedule = retrySchedule?.filter { Int64($0.key).map(deferred.contains) == true }
        failures = failures?.filter { Int64($0.key).map(deferred.contains) == true }
        skipped = skipped?.filter { Int64($0.key).map(existing.contains) == true }
        if let model {
            // Another on-device model may analyze what this one could not: queue the skipped rows
            // again with fresh counts. Their labels stay for the report.
            if let previous = skippedModel, previous != model, let lifted = skipped, !lifted.isEmpty {
                if failures == nil { failures = [:] }
                for (key, var failure) in lifted {
                    guard let id = Int64(key) else { continue }
                    failure.count = 0
                    deferred.insert(id); failures?[key] = failure; retrySchedule?.removeValue(forKey: key)
                }
                skipped = [:]
            }
            skippedModel = skipped?.isEmpty == false ? (skippedModel ?? model) : nil
        }
        let budget = min(AppleMailConnector.maximumMessagesPerPass, max(0, limit))
        let fresh = rows.filter { $0.id > highWater }.sorted { $0.id < $1.id }
            .prefix(budget).map { Work(row: $0, phase: .discovery) }
        var work = Array(fresh)
        var occupied = Set(work.map { $0.row.id })
        let retries = rows.filter { deferred.contains($0.id) && !occupied.contains($0.id)
            && (retrySchedule?[String($0.id)]?.due ?? .distantPast) <= now }.sorted { $0.id < $1.id }
        let rotated = retries.filter { $0.id > retryAfter } + retries.filter { $0.id <= retryAfter }
        // Reserve a bounded retry turn before backfill so missing bodies do not wait for all history.
        work += rotated.prefix(min(100, budget - work.count)).map { Work(row: $0, phase: .retry) }
        occupied.formUnion(work.map { $0.row.id })
        if backfillBefore != nil {
            work += rows.filter { needsBackfill($0) && !occupied.contains($0.id) }
                .sorted { Position($0) > Position($1) }
                .prefix(budget - work.count).map { Work(row: $0, phase: .backfill) }
        }
        if backfillBefore == nil && (reconcileBefore != nil || now.timeIntervalSince(reconciledAt ?? .distantPast) >= 86400) {
            let used = Set(work.map { $0.row.id })
            let before = reconcileBefore ?? top
            work += rows.filter { $0.id <= before && !used.contains($0.id) && !deferred.contains($0.id) && !isSkipped($0.id) }.sorted { $0.id > $1.id }
                .prefix(budget - work.count).map { Work(row: $0, phase: .reconcile) }
        }
        return work
    }

    func isSkipped(_ id: Int64) -> Bool { skipped?[String(id)] != nil }

    /// Records one attempt. `failure` nil = classified or rejected: the row leaves the queue and
    /// every reason is forgotten. A failure with the same cause as the last one extends its count;
    /// at `skipAfter` a format, reply or engine failure moves the row to `skipped`. `counts` false
    /// records the reason without advancing the count (an engine failure that only followed another
    /// email's engine failure, which says nothing about this email).
    mutating func finish(_ work: Work, failure: Failure?, counts: Bool = true, now: Date = Date(), model: String? = nil) {
        let key = String(work.row.id)
        if var failure {
            let previous = failures?[key]
            let step = counts ? 1 : 0
            if let previous, previous.cause == failure.cause {
                failure.count = previous.count + step
            } else if previous == nil, failure.cause.givesUp, let attempts = retrySchedule?[key]?.attempts, attempts > 0 {
                // Queued before reasons were recorded: earlier attempts count, but never alone.
                failure.count = min(attempts, Self.skipAfter - 1) + step
            } else {
                failure.count = step
            }
            failure.domain = failure.domain ?? previous?.domain
            failure.bytes = failure.bytes ?? previous?.bytes
            if failure.cause.givesUp && failure.count >= Self.skipAfter {
                deferred.remove(work.row.id)
                retrySchedule?.removeValue(forKey: key)
                failures?.removeValue(forKey: key)
                if skipped == nil { skipped = [:] }
                skipped?[key] = failure
                if skippedModel == nil { skippedModel = model }
            } else {
                deferred.insert(work.row.id)
                let attempts = min(4, max(0, retrySchedule?[key]?.attempts ?? 0)) + 1
                let delays: [TimeInterval] = [300, 1800, 7200, 43200, 86400]
                if retrySchedule == nil { retrySchedule = [:] }
                retrySchedule?[key] = Retry(attempts: attempts, due: now.addingTimeInterval(delays[attempts - 1]))
                if failures == nil { failures = [:] }
                failures?[key] = failure
            }
        } else {
            deferred.remove(work.row.id)
            retrySchedule?.removeValue(forKey: key)
            failures?.removeValue(forKey: key)
            skipped?.removeValue(forKey: key)
        }
        switch work.phase {
        case .discovery: highWater = work.row.id
        case .backfill: backfillFloor = Position(work.row)
        case .retry: retryAfter = work.row.id
        case .reconcile: reconcileBefore = work.row.id - 1
        }
    }

    /// A retry without a recorded reason (kept for callers that only know retry or not).
    mutating func finish(_ work: Work, retry: Bool, now: Date = Date()) {
        finish(work, failure: retry ? Failure(cause: .unrecorded, code: "unrecorded") : nil, now: now)
    }

    /// Skip These: every queued row except those waiting on Mail leaves the queue now, keeping its
    /// reason. Returns how many moved.
    @discardableResult
    mutating func skipQueued(model: String?) -> Int {
        var moved = 0
        for id in deferred.sorted() {
            let key = String(id)
            let failure = failures?[key]
                ?? Failure(cause: .unrecorded, code: "unrecorded", count: retrySchedule?[key]?.attempts ?? 0)
            guard failure.cause != .notDownloaded else { continue }
            deferred.remove(id)
            retrySchedule?.removeValue(forKey: key)
            failures?.removeValue(forKey: key)
            if skipped == nil { skipped = [:] }
            skipped?[key] = failure
            moved += 1
        }
        if moved > 0, skippedModel == nil { skippedModel = model }
        return moved
    }

    /// Retry Now: skipped rows return to the queue and every queued row is due at once. A returned
    /// row keeps its count, so the same failure once more skips it again. Returns the queue size.
    @discardableResult
    mutating func retryNow() -> Int {
        if let lifted = skipped, !lifted.isEmpty {
            if failures == nil { failures = [:] }
            for (key, failure) in lifted {
                guard let id = Int64(key) else { continue }
                deferred.insert(id); failures?[key] = failure
            }
        }
        skipped = nil; skippedModel = nil
        retrySchedule = retrySchedule?.mapValues { Retry(attempts: $0.attempts, due: .distantPast) }
        return deferred.count
    }

    /// Queued rows split by what they wait for, plus the skipped count.
    var queueCounts: (retrying: Int, waitingOnMail: Int, skipped: Int) {
        let waiting = deferred.filter { failures?[String($0)]?.cause == .notDownloaded }.count
        return (deferred.count - waiting, waiting, skipped?.count ?? 0)
    }

    /// Every queued and skipped row with its reason, oldest row first.
    var entries: [Entry] {
        let queued = deferred.sorted().map {
            Entry(rowID: $0, failure: failures?[String($0)], skipped: false, due: retrySchedule?[String($0)]?.due)
        }
        let dropped = (skipped ?? [:]).compactMap { key, failure in
            Int64(key).map { Entry(rowID: $0, failure: failure, skipped: true, due: nil) }
        }.sorted { $0.rowID < $1.rowID }
        return queued + dropped
    }

    /// The on-device model file by name, size and modification time, so an updated model lifts
    /// earlier skips even at the same path. No path, no content.
    static func modelIdentity(path: String?) -> String? {
        guard let path, let values = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let size = (values[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (values[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(URL(fileURLWithPath: path).lastPathComponent):\(size):\(Int(modified))"
    }

    mutating func completePass(rows: [AppleMailRow], now: Date) {
        if backfillBefore != nil && !rows.contains(where: needsBackfill) {
            backfillBefore = nil; backfillFloor = nil
        }
        if let before = reconcileBefore, !rows.contains(where: { $0.id <= before && !deferred.contains($0.id) && !isSkipped($0.id) }) {
            reconcileBefore = nil; reconciledAt = now
        }
        if rows.isEmpty { backfillBefore = nil; backfillFloor = nil; reconciledAt = now }
    }
}

extension AppleMailCheckpoint.Failure {
    /// What a failed attempt means. A body that loaded and then failed is the model's (a reply it
    /// could not use, or an engine error); a body that did not load is waiting on Mail, damaged, or
    /// unreadable. The code is a type/case path (AnalysisFailureCode), never message content.
    static func classify(_ error: Error, loadedBody: Bool) -> Self {
        let code = AnalysisFailureCode.code(for: error)
        if loadedBody { return Self(cause: error is Triage.ReplyFailure ? .reply : .engine, code: code) }
        switch error {
        case AppleMailError.missingBody, AppleMailMIME.Failure.unavailable, AppleMailMIME.Failure.incompleteMessage,
             AppleMailMIME.Failure.missingBodyPart, AppleMailMIME.Failure.incompleteMultipart:
            return Self(cause: .notDownloaded, code: code)
        case AppleMailMIME.Failure.malformed, AppleMailMIME.Failure.unsupported,
             AppleMailMIME.Failure.invalidTransferEncoding, AppleMailMIME.Failure.invalidText:
            return Self(cause: .format, code: code)
        default:
            return Self(cause: .unreadable, code: code)
        }
    }
}

nonisolated extension AppleMailCheckpoint {
    /// This account's queue as report issues: one per queued or skipped email, labelled by sender
    /// domain and size at most (AnalysisRunReport's privacy rule). `account` only keys the ids.
    func reportIssues(account: String) -> [RunIssue] {
        entries.map { entry in
            let failure = entry.failure
                ?? Failure(cause: .unrecorded, code: "unrecorded", count: retrySchedule?[String(entry.rowID)]?.attempts ?? 0)
            return Self.issue(account: account, rowID: entry.rowID, failure: failure, skipped: entry.skipped, due: entry.due)
        }
    }

    static func issue(account: String, rowID: Int64, failure: Failure, skipped: Bool, due: Date?) -> RunIssue {
        var item = "Email"
        if let domain = failure.domain { item += " · " + domain }
        if let bytes = failure.bytes { item += " · " + RunIssue.size(bytes) }
        let problem: String
        switch failure.cause {
        case .notDownloaded: problem = "Mail hasn’t downloaded this message yet."
        case .unreadable: problem = "Sentient couldn’t read this message from Mail’s storage."
        case .format: problem = "The message uses an unsupported or damaged format."
        case .reply: problem = "The on-device model’s answer couldn’t be used."
        case .engine: problem = "The on-device model failed while analyzing it."
        case .unrecorded: problem = "It was queued for another try before Sentient recorded reasons."
        }
        let next: RunIssue.Next
        var nextNote: String?
        let remedy: String
        if skipped {
            next = .skipped
            nextNote = failure.cause == .reply || failure.cause == .engine
                ? "Skipped until the on-device model updates" : "Skipped until you choose Retry Now"
            remedy = "Nothing to do. Choose Retry Now to try it again."
        } else {
            switch failure.cause {
            case .notDownloaded:
                next = .waitingOnMail
                remedy = "Open Mail and let it finish downloading your mail. It’s analyzed after that."
            case .unreadable:
                next = .retry
                remedy = "Check that Sentient has Full Disk Access, then choose Retry Now."
            case .unrecorded:
                next = .retry
                remedy = "Nothing to do. The next try records why it failed."
            case .format, .reply, .engine:
                next = .retry
                remedy = "Nothing to do. After \(skipAfter) failures in a row it’s skipped, so analysis can finish."
            }
        }
        return RunIssue(id: "mail:\(account):\(rowID)", source: AnalysisRunReport.appleMail, unit: "email", item: item,
                        problem: problem, next: next, retryAt: next == .retry ? due : nil, nextNote: nextNote,
                        remedy: remedy, code: failure.code, attention: next == .retry,
                        tries: failure.count > 0 ? failure.count : nil)
    }
}
