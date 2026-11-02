// IterativeRun+AppleMail.swift
// Account/generation frontiers, deferred-body retries and periodic reconciliation for Mail.
// Every classification is committed atomically with progress. Each failed attempt records why
// (AppleMailCheckpoint.Failure: a cause and a type/case code, never content); an email whose model
// or format failure repeats AppleMailCheckpoint.skipAfter times is skipped instead of retried
// forever, and bodies Mail has not downloaded wait on Mail without making the run incomplete.
// The pass ends by listing every queued and skipped email in the run's issues (AnalysisRunReport).
// Doc: Ingestion/Documentation - Ingestion Pipeline.md

import Foundation

private enum MailRunFailure: Error { case deadline, model, storage }

extension IterativeRun {
    /// Uses the run's single local engine; all disk work is on a utility task, away from UI work.
    func runMail(_ connector: AppleMailConnector, engine: Engine,
                 onProgress: @Sendable @escaping (RunProgress) -> Void) async -> RunProgress {
        var p = RunProgress()
        var generations = 0
        var modelFailures = 0
        let deadline = Date().addingTimeInterval(3600)
        var diagnosticPhase: Diagnostics.Phase = .snapshot
        // Skips decided by one on-device model are lifted when another model (or an updated file) runs.
        let model = AppleMailCheckpoint.modelIdentity(path: modelPath)
        var lastEngineCode: String?
        var sourceIssue: RunIssue?
        defer {
            if !Task.isCancelled, p.failed > 0 || p.extractionFailed > 0 {
                Diagnostics.report(.sourceReadDegraded, phase: .complete, reason: "mail_deferred", source: "apple_mail",
                                   counts: [.attempted: p.done, .failed: p.failed, .deferred: p.mailDeferred, .skipped: p.extractionFailed],
                                   flags: [.partial: p.mailIncomplete, .retriable: true])
            }
        }
        do {
            let snapshot = try await Task.detached(priority: .utility) {
                try AppleMailSnapshot(root: AppleMailSource.root(), selected: connector.accounts)
            }.value
            let available = Set(snapshot.accounts.map(\.id))
            guard connector.accounts.isSubset(of: available) else { throw AppleMailError.access }
            let accounts = connector.accounts.sorted()
            for (offset, account) in accounts.enumerated() {
                try Task.checkCancellation()
                let remaining = AppleMailConnector.maximumMessagesPerPass - p.done
                guard remaining > 0 else { p.mailIncomplete = true; break }
                // Share the pass across accounts so one large archive cannot starve another inbox.
                let accountBudget = max(1, remaining / (accounts.count - offset))
                let bucket = "appleMail:" + account
                let rows = snapshot.rows.filter { $0.account == account }
                var state = try await store.mailCheckpoint(bucket)
                    ?? AppleMailCheckpoint(generation: snapshot.generation, top: rows.first?.id ?? 0)
                var receipts = try await store.mailReceipts(bucket)
                let work = state.prepare(generation: snapshot.generation, rows: rows, now: Date(), limit: accountBudget, model: model)
                // Remove pending summaries of rows now excluded or absent. Receipts are survivors
                // only; deletion therefore leaves no rejected-message ledger. A row excluded only by
                // list/bulk/Promotions metadata keeps its receipt: only a school sender's mail is ever
                // kept from such a row (AppleMailSource.forcedJunk), and the daily reconcile re-reads
                // it, so a message that stops qualifying is removed then.
                let keepable = rows.filter { !$0.excluded || $0.bulkOnly }
                let eligible = Set(keepable.map(\.id))
                let eligibleKeys = Set(keepable.map { AppleMailSource.messageKey(salt: state.salt, row: $0) })
                let invalid = Set(receipts.values.filter {
                    $0.messageKey.map { !eligibleKeys.contains($0) }
                        ?? ($0.generation != snapshot.generation || !eligible.contains($0.rowID))
                }.map(\.identity))
                diagnosticPhase = .commit
                let start = await store.commitMail(bucketKey: bucket, state: state, remove: invalid)
                guard start == .saved else { p.diskFull = start == .diskFull; throw MailRunFailure.storage }
                for identity in invalid { receipts.removeValue(forKey: identity) }
                try await Task.detached(priority: .utility) { try snapshot.indexFiles(account: account) }.value
                let queued = state.queueCounts
                p.mailDeferred += queued.retrying; p.mailWaitingOnMail += queued.waitingOnMail; p.mailSkipped += queued.skipped
                p.total += work.count
                onProgress(p)
                for item in work {
                    try Task.checkCancellation()
                    if Date() >= deadline { throw MailRunFailure.deadline }
                    let row = item.row
                    var retry = false, draft: NoteDraft?, receipt: AppleMailReceiptValue?
                    var remove = Set<String>()
                    var decision: Triage.Outcome?
                    var seconds: Double?
                    var loadedBody = false
                    var failure: AppleMailCheckpoint.Failure?
                    var failureCounts = true
                    var domain: String?, bytes: Int?
                    if !row.excluded || row.previewJunk {
                        do {
                            diagnosticPhase = .extract
                            let message = try await Task.detached(priority: .utility) { try snapshot.body(row, includeJunkPreview: true) }.value
                            loadedBody = true
                            // Coarse labels for the report only: the sender's domain and the text size.
                            domain = SchoolSenders.senderDomain(message.headers["from"])
                            bytes = message.text.utf8.count
                            let forcedJunk = AppleMailSource.forcedJunk(row: row, headers: message.headers)
                            let identity = AppleMailSource.identity(salt: state.salt, row: row, message: message)
                            remove = Set(receipts.values.filter {
                                $0.generation == snapshot.generation && $0.rowID == row.id && $0.identity != identity
                            }.map(\.identity))
                            if forcedJunk { remove.insert(identity) }
                            let hash = AppleMailSource.contentDigest(message, sent: row.sent)
                            receipt = AppleMailReceiptValue(identity: identity, contentHash: hash,
                                generation: snapshot.generation, rowID: row.id,
                                messageKey: AppleMailSource.messageKey(salt: state.salt, row: row))
                            if forcedJunk || receipts[identity]?.contentHash != hash {
                                if generations >= 40 {
                                    do { try await engine.reload(); generations = 0 }
                                    catch { throw MailRunFailure.model }
                                }
                                // Raw routing headers, attachments and paths stay outside the model input.
                                let artifact = AppleMailSource.artifact(row: row, identity: identity, message: message)
                                let prompt = Triage.prompt(for: artifact, currentDate: Date())
                                var parsed: Triage.Outcome?
                                // One fresh attempt can recover transient formatting failures. Never guess
                                // missing privacy decisions or save a partially parsed response.
                                for attempt in 0..<2 {
                                    try Task.checkCancellation()
                                    diagnosticPhase = .generate
                                    let response = try await engine.generate(prompt: prompt + (attempt == 0 ? "" : Triage.mailRetryInstruction))
                                    generations += 1
                                    seconds = (seconds ?? 0) + response.totalTime
                                    switch Triage.mailReply(response.text) {
                                    case .success(let result): parsed = result
                                    case .failure(let reason):
                                        Log("Apple Mail reply deferred: \(reason.rawValue), attempt=\(attempt + 1), bytes=\(response.text.utf8.count)")
                                        if attempt == 1 {
                                            // Counted and listed by the run itself (the email's issue), so
                                            // the report does not also mark the whole run failed.
                                            Diagnostics.report(.modelOutputInvalid, phase: .parse, reason: "mail_reply", error: reason, source: "apple_mail", counts: [.bytes: response.text.utf8.count, .retries: 1],
                                                               affectsOperation: false)
                                            throw reason
                                        }
                                    }
                                    if parsed != nil { break }
                                }
                                guard let parsed else { throw Triage.ReplyFailure.invalidJSON }
                                // Metadata policy wins even if the model calls a promotion useful.
                                // Sensitive always wins over junk; only safe previews reach the card.
                                let outcome = forcedJunk && parsed.verdict != .sensitive
                                    ? Triage.Outcome(verdict: .junk, title: parsed.title, summary: parsed.summary, reason: .modelJunk)
                                    : parsed
                                decision = outcome
                                modelFailures = 0
                                if outcome.verdict == .survivor {
                                    draft = NoteDraft(kind: .appleMail, sourceID: identity, folder: "Apple Mail", itemDate: row.date,
                                        text: outcome.summary, title: outcome.title, reminderFlagged: false)
                                } else { remove.insert(identity); receipt = nil }
                            }
                        } catch AppleMailMIME.Failure.noText {
                            // A fully decoded empty body has nothing to classify. Download stubs
                            // have a separate unavailable error and stay in the deferred queue.
                            decision = Triage.Outcome(verdict: .junk, title: nil, summary: "", reason: .emptySummary)
                            remove = Set(receipts.values.filter { $0.generation == snapshot.generation && $0.rowID == row.id }.map(\.identity))
                        } catch AppleMailMIME.Failure.excluded {
                            // Header policy rejection stores neither headers nor an identity.
                            remove = Set(receipts.values.filter { $0.generation == snapshot.generation && $0.rowID == row.id }.map(\.identity))
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            if loadedBody {
                                Diagnostics.report(.sourceReadFailed, phase: diagnosticPhase, error: error, source: "apple_mail", flags: [.retriable: true], terminal: true,
                                                   affectsOperation: false)
                            }
                            retry = true; receipt = nil; draft = nil
                            var recorded = AppleMailCheckpoint.Failure.classify(error, loadedBody: loadedBody)
                            recorded.domain = domain; recorded.bytes = bytes
                            if loadedBody {
                                // Malformed JSON is a deferred classification, not a broken GPU.
                                // Repeated bad outputs must not starve all remaining message bodies.
                                if error is Triage.ReplyFailure {
                                    modelFailures = 0
                                } else {
                                    // Only the first engine failure in a streak says something about
                                    // this email; the ones after it may just be a stuck engine.
                                    failureCounts = modelFailures == 0
                                    modelFailures += 1
                                    lastEngineCode = recorded.code
                                }
                            }
                            // The type/case code only: never the error's text, which can quote content.
                            Log("Apple Mail \(loadedBody ? "analysis" : "body") deferred: \(recorded.cause.rawValue) \(recorded.code)")
                            failure = recorded
                        }
                    }
                    try Task.checkCancellation()
                    var next = state
                    next.finish(item, failure: failure, counts: failureCounts, model: model)
                    diagnosticPhase = .commit
                    let outcome = await store.commitMail(bucketKey: bucket, state: next, note: draft, receipt: receipt, remove: remove)
                    guard outcome == .saved else { p.diskFull = outcome == .diskFull; throw MailRunFailure.storage }
                    let before = state.queueCounts, after = next.queueCounts
                    p.mailDeferred += after.retrying - before.retrying
                    p.mailWaitingOnMail += after.waitingOnMail - before.waitingOnMail
                    p.mailSkipped += after.skipped - before.skipped
                    let skippedNow = next.isSkipped(row.id) && !state.isSkipped(row.id)
                    if let failure {
                        // Counted only when the email is tried again: a body Mail has not downloaded
                        // waits on Mail, and an email given up on is reported as skipped.
                        if skippedNow { p.mailSkippedNow += 1 }
                        else if loadedBody {
                            p.failed += 1
                            if failure.cause == .reply { p.parseFailures += 1 }
                        } else if failure.cause != .notDownloaded { p.extractionFailed += 1 }
                    }
                    state = next
                    for identity in remove { receipts.removeValue(forKey: identity) }
                    if let receipt { receipts[receipt.identity] = receipt }
                    // Display/counters only after a successful commit. Junk text stays in this ephemeral card.
                    // Keep the previous card intact if this attempt is cancelled or cannot be saved.
                    p.lastPath = "Apple Mail"; p.lastFilePath = nil; p.lastPrompt = nil
                    p.lastItemDate = row.date.timeIntervalSince1970 > 0 ? row.date : nil
                    p.lastTitle = nil; p.lastSummary = nil; p.lastVerdict = nil
                    p.lastSeconds = seconds; p.totalSeconds += seconds ?? 0
                    if let decision {
                        LifetimeStats.bump(decision.verdict)
                        switch decision.verdict {
                        case .survivor: p.survivors += 1; p.lastTitle = decision.title; p.lastSummary = decision.summary
                        case .junk: p.junk += 1; p.lastTitle = decision.title; p.lastSummary = decision.summary
                        case .sensitive: p.sensitive += 1
                        }
                        p.lastVerdict = decision.verdict
                        if decision.reason == .emptySummary {
                            p.lastTitle = "No message text"
                            p.lastSummary = "This email has no readable body text. Attachments are not analyzed."
                        }
                    } else if retry, let failure {
                        (p.lastTitle, p.lastSummary) = Self.mailCard(failure, skipped: skippedNow)
                    } else if receipt != nil {
                        p.lastTitle = "Already analyzed"
                        p.lastSummary = "No changes since the previous analysis."
                    } else {
                        p.junk += 1
                        p.lastVerdict = .junk
                        p.lastTitle = "Message skipped"
                        p.lastSummary = "Deleted messages and drafts are not analyzed."
                    }
                    p.done += 1
                    onProgress(p)
                    if modelFailures == 3 || modelFailures >= 6 {
                        do { try await engine.reload() }
                        catch { throw MailRunFailure.model }
                        // Leave remaining rows untouched if inference keeps failing after reload.
                        if modelFailures >= 6 { throw MailRunFailure.model }
                    }
                }
                state.completePass(rows: rows, now: Date())
                diagnosticPhase = .commit
                let end = await store.commitMail(bucketKey: bucket, state: state)
                guard end == .saved else { p.diskFull = end == .diskFull; throw MailRunFailure.storage }
                if state.backfillBefore != nil || rows.contains(where: { $0.id > state.highWater }) { p.mailIncomplete = true }
            }
            if p.mailIncomplete { sourceIssue = Self.mailSourceIssue(.moreHistory) }
            await finishMailIssues(connector, into: &p, sourceIssue: sourceIssue)
            AppleMailHealth.save(p, failed: false)
        } catch is CancellationError {
            p.mailIncomplete = true
            AppleMailHealth.save(p, incomplete: true, failed: false)
        }
        catch MailRunFailure.deadline {
            Diagnostics.report(.sourceReadDegraded, phase: diagnosticPhase, reason: "deadline", source: "apple_mail", flags: [.partial: true, .retriable: true])
            p.mailIncomplete = true
            await finishMailIssues(connector, into: &p, sourceIssue: Self.mailSourceIssue(.deadline))
            AppleMailHealth.save(p, incomplete: true, failed: false)
        } catch {
            Diagnostics.report(.sourceReadDegraded, phase: diagnosticPhase, error: error, source: "apple_mail", flags: [.partial: true, .retriable: true])
            p.failed += 1; p.mailIncomplete = true
            let issue: AppleMailHealth.Issue = error is MailRunFailure
                ? (error as? MailRunFailure == .storage ? .storage : .model) : .read
            let code: String
            switch issue {
            case .model: code = "MailRunFailure.model" + (lastEngineCode.map { "." + $0 } ?? "")
            case .storage: code = "MailRunFailure.storage"
            case .read: code = "mail.read." + AnalysisFailureCode.code(for: error)
            }
            await finishMailIssues(connector, into: &p, sourceIssue: Self.mailSourceIssue(issue, code: code))
            AppleMailHealth.save(p, incomplete: true, failed: true, issue: issue)
            Log("Apple Mail read incomplete: \(code)")
        }
        onProgress(p)
        return p
    }

    /// Lists every selected account's queued and skipped emails (read back from the saved
    /// checkpoints, so accounts this pass did not reach are included) plus the pass's whole-source
    /// issue, and sets the Mail counts from that same state.
    private func finishMailIssues(_ connector: AppleMailConnector, into p: inout RunProgress, sourceIssue: RunIssue?) async {
        var issues: [RunIssue] = []
        var retrying = 0, waiting = 0, skipped = 0
        for account in connector.accounts.sorted() {
            guard let state = try? await store.mailCheckpoint("appleMail:" + account) else { continue }
            issues += state.reportIssues(account: account)
            let counts = state.queueCounts
            retrying += counts.retrying; waiting += counts.waitingOnMail; skipped += counts.skipped
        }
        if let sourceIssue { issues.insert(sourceIssue, at: 0) }
        p.setIssues(issues, for: AnalysisRunReport.appleMail)
        p.mailDeferred = retrying; p.mailWaitingOnMail = waiting; p.mailSkipped = skipped
        p.mailChecked = true
    }

    enum MailSourceProblem { case moreHistory, deadline }

    static func mailSourceIssue(_ problem: MailSourceProblem) -> RunIssue {
        switch problem {
        case .moreHistory:
            return RunIssue(id: "source:" + AnalysisRunReport.appleMail, source: AnalysisRunReport.appleMail, unit: nil, item: nil,
                            problem: "Older mail is still being read, up to \(AppleMailConnector.maximumMessagesPerPass) emails per analysis.",
                            next: .nextRun, remedy: "Nothing to do. The next analysis continues where this one stopped.",
                            code: "mail.moreHistory", attention: true)
        case .deadline:
            return RunIssue(id: "source:" + AnalysisRunReport.appleMail, source: AnalysisRunReport.appleMail, unit: nil, item: nil,
                            problem: "Apple Mail reached its one-hour limit for one analysis; more mail remains.",
                            next: .nextRun, remedy: "Nothing to do. The next analysis continues where this one stopped.",
                            code: "mail.deadline", attention: true)
        }
    }

    static func mailSourceIssue(_ issue: AppleMailHealth.Issue, code: String) -> RunIssue {
        let problem: String, remedy: String
        switch issue {
        case .model:
            problem = "The on-device model stopped responding, so the rest of your mail wasn’t read this time."
            remedy = "Choose Retry Now. If it happens again, restart your Mac to reset its graphics processor."
        case .storage:
            problem = "Apple Mail analysis couldn’t save its progress."
            remedy = "Free up disk space, then choose Retry Now."
        case .read:
            problem = "Apple Mail couldn’t be read."
            remedy = "Check that Sentient has Full Disk Access and that Mail opens normally, then choose Retry Now."
        }
        return RunIssue(id: "source:" + AnalysisRunReport.appleMail, source: AnalysisRunReport.appleMail, unit: nil, item: nil,
                        problem: problem, next: .nextRun, remedy: remedy, code: code, attention: true)
    }

    /// The "just processed" card for an email that did not finish.
    static func mailCard(_ failure: AppleMailCheckpoint.Failure, skipped: Bool) -> (String, String) {
        if skipped {
            return ("Skipped", "This email failed the same way \(AppleMailCheckpoint.skipAfter) times, so analysis moves on without it. Retry Now on the Analysis page tries it again.")
        }
        switch failure.cause {
        case .notDownloaded:
            return ("Waiting on Mail", "Mail hasn’t downloaded this message yet. It’s analyzed after Mail downloads it.")
        case .unreadable:
            return ("Message unavailable", "This message couldn’t be read from Mail. Check Full Disk Access, then try again.")
        case .format:
            return ("Analysis deferred", "This message uses an unsupported or damaged format. It’s tried again later; the rest of your mail can still be analyzed.")
        case .reply:
            return ("Analysis deferred", "The on-device model returned an answer that couldn’t be used. This email is tried again later.")
        case .engine, .unrecorded:
            return ("Analysis deferred", "The on-device model couldn’t finish. This email is tried again later.")
        }
    }
}

/// Structural health only; no message identifiers, subjects, paths or bodies in preferences.
nonisolated enum AppleMailHealth {
    static let key = "sources.appleMail.health"
    static let needsRetryKey = "sources.appleMail.needsRetry"
    enum Issue { case read, model, storage }

    static func save(_ p: RunProgress, incomplete: Bool? = nil, failed: Bool, issue: Issue = .read) {
        save(deferred: p.mailDeferred, waitingOnMail: p.mailWaitingOnMail, skipped: p.mailSkipped,
             incomplete: incomplete ?? p.mailIncomplete, failed: failed, issue: issue)
    }

    /// Keeps "not downloaded in Mail" (Open Mail) apart from "the model couldn't analyze it"
    /// (tried again, then skipped). Only a failure, unread history or emails still being retried
    /// make Mail need another try; waiting on Mail and skipped emails do not.
    static func save(deferred: Int, waitingOnMail: Int = 0, skipped: Int = 0, incomplete: Bool, failed: Bool, issue: Issue = .read) {
        UserDefaults.standard.set(text(deferred: deferred, waitingOnMail: waitingOnMail, skipped: skipped,
                                       incomplete: incomplete, failed: failed, issue: issue), forKey: key)
        let retry = failed || incomplete || deferred > 0
        UserDefaults.standard.set(retry, forKey: needsRetryKey)
        SourceHealth.recordReadOutcome(source: "apple_mail", outcome: retry ? "incomplete" : "ok")
    }

    static func text(deferred: Int, waitingOnMail: Int, skipped: Int, incomplete: Bool, failed: Bool, issue: Issue) -> String {
        func emails(_ n: Int) -> String { n == 1 ? "1 email" : "\(n.formatted()) emails" }
        var parts: [String] = []
        if failed {
            switch issue {
            case .read: parts.append("Apple Mail could not be read. Check Full Disk Access and open Mail, then try again.")
            case .model: parts.append("The on-device model stopped during Apple Mail analysis. Saved progress resumes next time.")
            case .storage: parts.append("Apple Mail analysis could not save progress. Check available disk space, then try again.")
            }
        }
        if deferred > 0 {
            parts.append("\(emails(deferred)) couldn’t be analyzed yet and \(deferred == 1 ? "is" : "are") tried again automatically.")
        }
        if waitingOnMail > 0 {
            parts.append("\(emails(waitingOnMail)) \(waitingOnMail == 1 ? "isn’t" : "aren’t") downloaded in Mail yet. Open Mail to finish downloading.")
        }
        if skipped > 0 {
            parts.append("\(emails(skipped)) \(skipped == 1 ? "was" : "were") skipped because the on-device model couldn’t analyze \(skipped == 1 ? "it" : "them").")
        }
        if !failed && incomplete { parts.append("Apple Mail has more history to read. Analysis resumes next time.") }
        if parts.isEmpty { return "Downloaded mail is up to date. Junk previews are not saved; attachments are not analyzed." }
        return parts.joined(separator: " ")
    }
}
