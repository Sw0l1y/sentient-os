#!/usr/bin/env python3
"""Apple Mail give-up rule and the saved analysis report.
Compiles the production AppleMailCheckpoint (sliced from AppleMailConnector.swift by its declarations),
RunProgress.swift, AnalysisRunReport.swift and AnalysisFailureCode.swift with stubs for the Mail
reader types. Checks: three identical model/format failures skip an email; bodies Mail has not
downloaded wait forever without skipping; a different cause restarts the count; an engine failure
that only followed another email's failure does not count; legacy rows keep their earlier attempts;
a model change, Retry Now and Skip These; the report's per-source wording, carry-over, plain text
and privacy (no subject, address or path); nested error codes without payload text.
No Mail store, preferences or model is touched.
"""
from pathlib import Path
import platform
import re
import subprocess
import tempfile

APP = Path(__file__).resolve().parents[1] / 'Sentient OS macOS'


def member(source, signature):
    start = source.index(signature)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def line(source, pattern):
    match = re.search(pattern, source, re.M)
    assert match, pattern
    return match.group(0)


connector = (APP / 'Ingestion/Connectors/AppleMailConnector.swift').read_text()
mail_source = (APP / 'Sources/AppleMailSource.swift').read_text()
mime = (APP / 'Sources/AppleMailMIME.swift').read_text()
triage = (APP / 'Engine/Triage.swift').read_text()

SUPPORT = '''
import Foundation
enum Verdict: Sendable { case survivor, junk, sensitive }
nonisolated enum AppleMailSource { static let classificationVersion = 1 }
nonisolated enum AppleMailConnector { static let maximumMessagesPerPass = 600 }
nonisolated enum AppleMailMIME { %s }
nonisolated enum Triage { %s }
nonisolated %s
nonisolated enum Fixture {
    /// A model-library error shaped like LiteRTLMError (nested enum with a String payload).
    enum LiteRTLMError: Error { case conversation(ConversationError)
        enum ConversationError: Error { case invalidResponse(String), failedToStartStream(status: Int) } }
}
''' % (line(mime, r'^\s*enum Failure: Error \{[^}]*\}'),
       line(triage, r'^\s*enum ReplyFailure: String, Error \{[^}]*\}'),
       line(mail_source, r'^nonisolated enum AppleMailError: Error \{[^}]*\}').replace('nonisolated ', ''))

PRODUCTION = '\n'.join((
    'import Foundation',
    member(mail_source, 'nonisolated struct AppleMailRow'),
    member(connector, 'nonisolated struct AppleMailCheckpoint'),
    member(connector, 'extension AppleMailCheckpoint.Failure {'),
    member(connector, 'nonisolated extension AppleMailCheckpoint {'),
))

TESTS = r'''
import Foundation
@main struct Tests {
    @MainActor static var count = 0
    @MainActor static func check(_ value: Bool, _ label: String) { precondition(value, label); count += 1 }
    typealias C = AppleMailCheckpoint
    typealias F = AppleMailCheckpoint.Failure
    static func row(_ id: Int64) -> AppleMailRow {
        AppleMailRow(id: id, account: "A", messageID: "<\(id)@fixture>", date: Date(timeIntervalSince1970: Double(id) * 60),
                     excluded: false, sent: false)
    }
    static func work(_ id: Int64) -> C.Work { C.Work(row: row(id), phase: .retry) }

    @MainActor static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = (1...10).map { row(Int64($0)) }
        var state = C(generation: "g", top: 10)
        _ = state.prepare(generation: "g", rows: rows, now: now, model: "model-a:1:1")
        check(C.skipAfter == 3, "the give-up rule is three identical failures")

        // 1. Three identical model failures skip an email instead of retrying it forever.
        for attempt in 1...3 {
            state.finish(work(1), failure: F(cause: .reply, code: "ReplyFailure.invalidJSON", domain: "example.com", bytes: 4_000),
                         now: now, model: "model-a:1:1")
            if attempt < 3 { check(state.deferred.contains(1) && !state.isSkipped(1), "failure \(attempt) stays queued") }
        }
        check(!state.deferred.contains(1) && state.isSkipped(1) && state.retrySchedule?["1"] == nil,
              "third identical reply failure moves the email to skipped")
        check(state.skipped?["1"]?.code == "ReplyFailure.invalidJSON" && state.skipped?["1"]?.count == 3,
              "the skip keeps its reason and count")
        check(state.queueCounts.retrying == 0 && state.queueCounts.skipped == 1, "a skipped email is not counted as deferred")

        // 2. A body Mail has not downloaded never gives up; it waits on Mail.
        for _ in 1...6 { state.finish(work(2), failure: F(cause: .notDownloaded, code: "AppleMailMIME.Failure.unavailable"), now: now) }
        check(state.deferred.contains(2) && !state.isSkipped(2) && state.queueCounts.waitingOnMail == 1,
              "six download failures still wait on Mail")

        // 3. A different cause restarts the count.
        state.finish(work(3), failure: F(cause: .reply, code: "ReplyFailure.emptyTitle"), now: now)
        state.finish(work(3), failure: F(cause: .engine, code: "LiteRTLMError.conversation"), now: now)
        state.finish(work(3), failure: F(cause: .reply, code: "ReplyFailure.emptyTitle"), now: now)
        check(state.deferred.contains(3) && !state.isSkipped(3) && state.failures?["3"]?.count == 1,
              "alternating causes are not three identical failures")

        // 4. An engine failure that only followed another email's failure does not count.
        state.finish(work(4), failure: F(cause: .engine, code: "LiteRTLMError.conversation"), now: now)
        for _ in 1...4 { state.finish(work(4), failure: F(cause: .engine, code: "LiteRTLMError.conversation"), counts: false, now: now) }
        check(state.deferred.contains(4) && state.failures?["4"]?.count == 1, "uncounted engine failures do not skip")

        // 5. Rows queued before reasons were recorded keep their attempts, but never skip alone.
        state.deferred.formUnion([5, 6])
        state.retrySchedule?["5"] = C.Retry(attempts: 5, due: now)
        state.retrySchedule?["6"] = C.Retry(attempts: 1, due: now)
        check(state.queueCounts.retrying == 4, "legacy rows without a reason count as retrying")
        state.finish(work(5), failure: F(cause: .engine, code: "LiteRTLMError.conversation"), now: now)
        state.finish(work(6), failure: F(cause: .engine, code: "LiteRTLMError.conversation"), now: now)
        check(state.isSkipped(5) && !state.isSkipped(6) && state.failures?["6"]?.count == 2,
              "a legacy row at the old cap skips on its next model failure; one with one attempt does not")

        // 6. Success forgets every reason.
        state.finish(work(3), failure: nil, now: now)
        check(!state.deferred.contains(3) && state.failures?["3"] == nil, "a classified email leaves the queue")

        // 7. The same model keeps skips; reconcile never re-reads them; another model lifts them.
        state.reconciledAt = .distantPast; state.backfillBefore = nil
        var same = state
        let planned = same.prepare(generation: "g", rows: rows, now: now.addingTimeInterval(90_000), model: "model-a:1:1")
        check(same.isSkipped(1) && !planned.contains { $0.row.id == 1 || $0.row.id == 5 }, "skipped rows are not planned again")
        var updated = state
        let lifted = updated.prepare(generation: "g", rows: rows, now: now, model: "model-b:2:2")
        check(!updated.isSkipped(1) && updated.deferred.contains(1) && updated.failures?["1"]?.count == 0
              && lifted.contains { $0.row.id == 1 }, "a new on-device model queues skipped emails again with fresh counts")
        var version = state
        version.classificationVersion = 0
        _ = version.prepare(generation: "g", rows: rows, now: now, model: "model-a:1:1")
        check(version.skipped == nil && version.deferred.isEmpty, "a classification version change clears skips")

        // 8. Skip These and Retry Now.
        var user = state
        let moved = user.skipQueued(model: "model-a:1:1")
        check(moved == 2 && user.deferred == [2] && user.isSkipped(4) && user.isSkipped(6),
              "Skip These skips every retrying email but leaves the one waiting on Mail")
        let queued = user.retryNow()
        check(queued == 5 && user.skipped == nil && user.deferred.contains(1)
              && (user.retrySchedule?.values.allSatisfy { $0.due == .distantPast } ?? true),
              "Retry Now queues every skipped email again, due at once")
        user.finish(work(1), failure: F(cause: .reply, code: "ReplyFailure.invalidJSON"), now: now)
        check(user.isSkipped(1), "after Retry Now the same failure skips again at once")

        // 9. Saved checkpoints: reasons survive a round trip and an old checkpoint still decodes.
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(C.self, from: data)
        check(decoded.skipped?["1"]?.domain == "example.com" && decoded.failures?["2"]?.cause == .notDownloaded,
              "reasons survive a relaunch")
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["failures", "skipped", "skippedModel"] { legacy.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(C.self, from: JSONSerialization.data(withJSONObject: legacy))
        check(old.failures == nil && old.skipped == nil && old.deferred == state.deferred, "a checkpoint saved before reasons decodes")

        // 10. Error classification and codes (type and case path, never payload text).
        check(F.classify(AppleMailMIME.Failure.unavailable, loadedBody: false).cause == .notDownloaded
              && F.classify(AppleMailError.missingBody, loadedBody: false).cause == .notDownloaded
              && F.classify(AppleMailMIME.Failure.malformed, loadedBody: false).cause == .format
              && F.classify(AppleMailError.busy, loadedBody: false).cause == .unreadable
              && F.classify(Triage.ReplyFailure.invalidJSON, loadedBody: true).cause == .reply
              && F.classify(Fixture.LiteRTLMError.conversation(.invalidResponse("x")), loadedBody: true).cause == .engine,
              "failures map to waiting on Mail, format, unreadable, reply and engine")
        let library = AnalysisFailureCode.code(for: Fixture.LiteRTLMError.conversation(.invalidResponse("Native sendMessage returned null.")))
        let secret = AnalysisFailureCode.code(for: Fixture.LiteRTLMError.conversation(.invalidResponse("Subject: Dinner with Alice")))
        let status = AnalysisFailureCode.code(for: Fixture.LiteRTLMError.conversation(.failedToStartStream(status: 13)))
        check(library == "LiteRTLMError.conversation.invalidResponse.nativeNull", "the nested engine case is recorded: \(library)")
        check(secret == "LiteRTLMError.conversation.invalidResponse" && !secret.contains("Alice"), "payload text never reaches a code")
        check(status.hasSuffix("failedToStartStream.status=13"), "small status numbers are kept: \(status)")
        check(AnalysisFailureCode.code(for: Triage.ReplyFailure.emptyTitle) == "ReplyFailure.emptyTitle", "reply failures name their kind")

        // 11. Report issues per email: coarse labels, next step, what to do.
        let issues = state.reportIssues(account: "ACCOUNT")
        let skipped = issues.first { $0.id == "mail:ACCOUNT:1" }!
        let waiting = issues.first { $0.id == "mail:ACCOUNT:2" }!
        check(skipped.item == "Email · example.com · 4 KB" && skipped.next == .skipped && !skipped.attention
              && skipped.nextStep == "Skipped until the on-device model updates", "a skipped email says why and what lifts it")
        check(waiting.next == .waitingOnMail && !waiting.attention && waiting.remedy.contains("Open Mail"),
              "an email Mail has not downloaded says Open Mail")
        check(issues.filter(\.attention).count == 2 && issues.allSatisfy { $0.source == "Apple Mail" && $0.unit == "email" },
              "only emails still being retried need attention")

        // 12. The saved report.
        var p = RunProgress()
        p.issues = issues
        p.mailChecked = true; p.done = 40; p.failed = 2
        p.mergeIssues([.skippedFile(source: "Downloads", path: "/tmp/Alice Smith tax return.pdf", stage: .extract,
                                    code: "CocoaError.code256")])
        p.warnings = ["files:resource_read:files::"]
        let report = AnalysisRunReport.build(progress: p, sources: ["Apple Mail", "Downloads", "Desktop"],
                                             complete: false, previous: nil, now: now)
        let mail = report.summaries.first { $0.name == "Apple Mail" }!
        let desktop = report.summaries.first { $0.name == "Desktop" }!
        check(desktop.headline == "Up to date" && desktop.tone == .ok, "a source without issues is up to date")
        check(mail.tone == .warning && mail.headline == "2 emails need another try · 1 waiting on Mail · 2 skipped",
              "Mail's headline splits retrying, waiting on Mail and skipped: \(mail.headline)")
        check(report.attentionLines.first == "Apple Mail: 2 emails need another try · 1 waiting on Mail · 2 skipped",
              "Home's line names the source")
        check(p.attentionNotice?.hasPrefix("Apple Mail: 2 emails need attention.") == true
              && p.attentionNotice?.contains("Downloads: 1 file needs attention.") == true, "the notice names each source")
        let text = report.plainText(appVersion: "1.0 (1)")
        check(text.contains("ReplyFailure.invalidJSON") && text.contains("Email · example.com · 4 KB")
              && text.contains("files:resource_read") && text.contains("PDF document (.pdf)"), "Copy Details carries codes and labels")
        check(!text.contains("Alice") && !text.contains("/tmp") && !text.contains("ACCOUNT") && !text.contains("@fixture"),
              "Copy Details never carries a name, path, account or message id")
        let saved = try JSONDecoder().decode(AnalysisRunReport.self, from: JSONEncoder().encode(report))
        check(saved == report, "the report survives a relaunch")

        // 13. Carry-over: a skipped file stays listed for a week; Mail is rebuilt, never carried.
        var next = RunProgress(); next.mailChecked = true
        let later = AnalysisRunReport.build(progress: next, sources: ["Apple Mail", "Downloads"], complete: true,
                                            previous: report, now: now.addingTimeInterval(86_400))
        let downloads = later.summaries.first { $0.name == "Downloads" }!
        check(downloads.issues.count == 1 && !downloads.issues[0].attention && downloads.tone == .info
              && downloads.headline == "1 file skipped", "a skipped file stays listed, no longer needing attention")
        check(later.summaries.first { $0.name == "Apple Mail" }!.issues.isEmpty, "Mail lists only its current queue")
        let week = AnalysisRunReport.build(progress: next, sources: ["Downloads"], complete: true,
                                           previous: later, now: now.addingTimeInterval(8 * 86_400))
        check(week.issues.isEmpty, "a skipped file drops off after a week")

        // 14. Whole-source issues and diagnostics with nothing else to show.
        var cap = RunProgress()
        cap.sourceReadFailures["Files"] = "More items remain."
        cap.mergeIssues([.timeLimit("Files", minutes: 60)])
        check(cap.attentionNotice == "Files: more to read next time. Completed work is saved.", "a time limit is not called a failure")
        var quiet = RunProgress(); quiet.warnings = ["fda:probe:denied::"]
        quiet.explainWarnings()
        check(quiet.attentionSources == ["Analysis"] && quiet.issues[0].code.contains("fda:probe"),
              "a diagnostic with no named source still says what fired")
        print("PASS \(count) Apple Mail give-up and analysis report checks")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='sentient-mail-give-up-') as directory:
    path = Path(directory)
    (path / 'Support.swift').write_text(SUPPORT)
    (path / 'Production.swift').write_text(PRODUCTION)
    (path / 'Tests.swift').write_text(TESTS)
    binary = path / 'test'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-target', f'{platform.machine()}-apple-macos15.0',
                    str(path / 'Support.swift'), str(path / 'Production.swift'), str(path / 'Tests.swift'),
                    str(APP / 'Ingestion/RunProgress.swift'), str(APP / 'Ingestion/AnalysisRunReport.swift'),
                    str(APP / 'Ingestion/AnalysisFailureCode.swift'), '-o', str(binary)], check=True, timeout=120)
    subprocess.run([str(binary)], check=True, timeout=30)
