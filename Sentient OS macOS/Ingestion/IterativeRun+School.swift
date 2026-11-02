// IterativeRun+School.swift
// Reads the School feed (Schoology) once per analysis and publishes it as a replaceable
// snapshot, like Apple Calendar: the saved snapshot, the cycle store's School notes (for the
// knowledge base and the proactive cycle) and the vault's School folder are all replaced, so
// finished and expired assignments drop off. No on-device model is involved, so this runs before
// the engine loads and a model problem never blocks it.
// Failures never stop the rest of the analysis. A school that stopped sharing (401/404, a sign-in
// page) needs a new link; a network or server problem keeps the previous snapshot (and, while it
// is under a week old, its notes) and is retried on the next analysis. Each is a whole-source
// RunIssue, so the Analysis page, Home and Copy Details say what happened and what to do.
// Doc: Documentation - Ingestion Pipeline.md

import Foundation

extension IterativeRun {
    func runSchool(_ connector: SchoolFeedConnector,
                   onProgress: @Sendable @escaping (RunProgress) -> Void) async -> RunProgress {
        var p = RunProgress()
        let name = SchoolFeedSource.name
        p.beginSourceRead(name: name, label: name, prompt: "The School feed is read directly. No model prompt is used.")
        onProgress(p)
        do {
            guard let link = try SchoolFeedSource.readLink() else { throw SchoolFeedSource.ReadError.missingLink }
            let snapshot = try await SchoolFeedSource.read(link: link)
            try Task.checkCancellation()
            do { try SchoolFeedSource.saveSnapshot(snapshot) } catch { throw SchoolFeedSource.ReadError.storage }
            let saved = await commitSchoolNotes(snapshot)
            guard saved == .saved else {
                p.diskFull = saved == .diskFull
                throw SchoolFeedSource.ReadError.storage
            }
            SchoolFeedSource.recordSuccess(snapshot)
            SchoolFeedSource.publishToVault(snapshot)
            let count = snapshot.assignments.count, classes = snapshot.courses.count
            p.finishSourceRead(name: name, label: name,
                               summary: count == 0 ? nil : "\(RunIssue.count(count, "assignment")) across \(classes == 1 ? "1 class" : "\(classes) classes"), from the past week through the next \(SchoolSnapshot.futureDays) days.",
                               items: count)
            if count == 0 {
                p.quietReads += 1
                p.lastTitle = "No assignments due"
                p.lastSummary = "Nothing is due in your Schoology calendar from the past week through the next \(SchoolSnapshot.futureDays) days."
            }
            Log("SchoolFeed: read complete, items=\(count), classes=\(classes)")
        } catch {
            if error is CancellationError || Task.isCancelled {
                p.failSourceRead(name: name, message: "Analysis stopped before Schoology was read. Your last assignment list is kept.",
                                 countFailure: false)
            } else {
                let issue = SchoolFeedSource.issue(for: error)
                let code = Self.schoolCode(error)
                SchoolFeedSource.recordIssue(issue)
                // A passing network problem keeps the last week-fresh snapshot visible to the
                // proactive cycle, with each item's status recomputed for today.
                if !issue.needsAttention, let previous = SchoolFeedSource.savedSnapshot(),
                   Date().timeIntervalSince(previous.capturedAt) < 7 * 86_400, !Task.isCancelled {
                    _ = await commitSchoolNotes(previous)
                }
                p.failSourceRead(name: name, message: SchoolFeedSource.issueMessage(issue.rawValue) ?? "Schoology couldn’t be read.",
                                 countFailure: false)
                p.mergeIssues([Self.schoolIssue(issue, code: code)])
                Log("SchoolFeed: read not finished (\(code)); the previous snapshot is kept")
            }
        }
        onProgress(p)
        return p
    }

    /// Replace the cycle store's School notes with this snapshot's (a coverage note plus each item
    /// due from a week ago through the next two weeks).
    private func commitSchoolNotes(_ snapshot: SchoolSnapshot) async -> CycleStore.CommitOutcome {
        let drafts = SchoolCycleNotes.notes(snapshot, sourceName: SchoolFeedSource.name, now: Date()).map {
            NoteDraft(kind: .schoolFeed, sourceID: $0.sourceID, folder: $0.folder, itemDate: $0.itemDate,
                      text: $0.text, title: $0.title, reminderFlagged: false)
        }
        return await store.commitSchoolSnapshot(drafts, capturedAt: snapshot.capturedAt)
    }

    /// A technical code with no link in it: "school.feed.revoked.404", "school.feed.missingLink".
    static func schoolCode(_ error: Error) -> String {
        switch error {
        case let failure as SchoolFeedFetch.Failure: failure.code
        case SchoolFeedSource.ReadError.missingLink: "school.feed.missingLink"
        case SchoolFeedSource.ReadError.keychain(let status): "school.feed.keychain.\(status)"
        case SchoolFeedSource.ReadError.storage: "school.feed.storage"
        default: "school.feed.storage." + String(describing: type(of: error))
        }
    }

    /// The run's whole-source issue for a School read that did not finish.
    static func schoolIssue(_ issue: SchoolFeedSource.Issue, code: String) -> RunIssue {
        let source = SchoolFeedSource.name
        let kept = "Checked again during the next analysis. Your last assignment list is kept"
        let problem: String, remedy: String, note: String?
        switch issue {
        case .revoked:
            problem = "Schoology stopped sharing your calendar, so your assignments weren’t updated."
            remedy = "In Schoology, open Settings, then Account Settings, and turn on Share Your Schoology Calendar. Paste the new iCal link in Knowledge Sources › Schoology › Manage…."
            note = kept
        case .missingLink:
            problem = "Your Schoology link isn’t in the Keychain."
            remedy = "Paste the iCal link again in Knowledge Sources › Schoology."
            note = kept
        case .unreachable:
            problem = "Sentient couldn’t reach Schoology."
            remedy = "Nothing to do. If it keeps happening, check your internet connection."
            note = kept
        case .server:
            problem = "Schoology had a problem sending your calendar."
            remedy = "Nothing to do. Schoology is usually back within a few hours."
            note = kept
        case .tooLarge:
            problem = "Your Schoology calendar is larger than 8 MB, so it wasn’t read."
            remedy = "Use Copy Details and send the report to the Sentient team."
            note = kept
        case .storage:
            problem = "Your assignments couldn’t be saved."
            remedy = "Check available disk space, then analyze again."
            note = nil
        }
        return RunIssue(id: "source:" + source, source: source, unit: nil, item: nil, problem: problem,
                        next: .nextRun, nextNote: note, remedy: remedy, code: code, attention: true)
    }
}
