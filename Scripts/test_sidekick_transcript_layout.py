#!/usr/bin/env python3
"""Compile the actual transcript presentation helper and store models.

Pure Foundation fixtures only: no app, providers, UI, user data, or copied layout logic.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "Sentient OS macOS"
FIXTURE = r'''
import Foundation

typealias Layout = SidekickTranscriptLayout
typealias Store = SidekickConversationStore
typealias Event = SidekickConversationEvent

@main struct TranscriptLayoutChecks {
    static var checks = 0
    static var failures: [String] = []
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        if !condition() { failures.append(label); print("FAIL: " + label) }
    }
    static func normalized(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 5,
                     calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    static func main() {
        let began = Date(timeIntervalSinceReferenceDate: 765432100)
        var sequence: Int64 = 0
        func record(_ id: String, task: UUID, kind: Event.Kind, seconds: Double = 0,
                    text: String? = nil, outcome: Event.Outcome? = nil,
                    messageKind: Event.MessageKind? = nil) -> Store.Record {
            sequence += 1
            return .init(sequence: sequence, event: Event(id: id, taskID: task, kind: kind,
                text: text ?? id, createdAt: began.addingTimeInterval(seconds), messageKind: messageKind,
                outcome: outcome,
                activity: kind == .activity ? .init(toolID: id, name: "fixture.search", status: .completed) : nil,
                choices: kind == .question ? ["First", "Second"] : nil))
        }
        let work = UUID(), clarification = UUID(), noAnswer = UUID(), stopped = UUID(), failed = UUID(), interrupted = UUID()
        let raw = [
            record("internal-start", task: work, kind: .taskStarted),
            record("request", task: work, kind: .userMessage, text: "Question **café 👩🏽‍💻**"),
            record("internal-tool", task: work, kind: .activity, seconds: 1),
            record("internal-checkpoint", task: work, kind: .checkpoint, seconds: 2),
            record("progress-first", task: work, kind: .assistantMessage, seconds: 3, messageKind: .update),
            record("progress-second", task: work, kind: .assistantMessage, seconds: 4, messageKind: .update),
            record("work-question", task: work, kind: .question, seconds: 5),
            record("work-user-answer", task: work, kind: .answer, seconds: 6),
            record("final-answer", task: work, kind: .assistantMessage, seconds: 7, text: "The actual answer\n\n1. First\n2. Second", messageKind: .answer),
            record("hidden-done", task: work, kind: .taskFinished, seconds: 8, outcome: .success),
            record("clarification-request", task: clarification, kind: .userMessage, seconds: 9),
            record("first-question", task: clarification, kind: .question, seconds: 10),
            record("first-choice", task: clarification, kind: .answer, seconds: 11),
            record("second-question", task: clarification, kind: .question, seconds: 12),
            record("second-choice", task: clarification, kind: .answer, seconds: 13),
            record("hidden-clarification-done", task: clarification, kind: .taskFinished, seconds: 14, outcome: .success),
            record("no-answer-request", task: noAnswer, kind: .userMessage, seconds: 15),
            record("no-answer-terminal", task: noAnswer, kind: .taskFinished, seconds: 16, outcome: .success),
            record("stopped-request", task: stopped, kind: .userMessage, seconds: 17),
            record("stopped-terminal", task: stopped, kind: .taskFinished, seconds: 18, text: "[Stopped by user]", outcome: .stopped),
            record("failed-request", task: failed, kind: .userMessage, seconds: 19),
            record("failed-terminal", task: failed, kind: .taskFinished, seconds: 20, outcome: .failed),
            record("interrupted-request", task: interrupted, kind: .userMessage, seconds: 21),
            record("interrupted-checkpoint", task: interrupted, kind: .checkpoint, seconds: 22),
            record("interrupted-terminal", task: interrupted, kind: .taskFinished, seconds: 23, outcome: .interrupted)
        ]
        let rows = Layout.rows(raw)
        let expectedIDs = ["request", "progress-first", "progress-second", "work-question", "work-user-answer", "final-answer",
            "clarification-request", "first-question", "first-choice", "second-question", "second-choice",
            "no-answer-request", "no-answer-terminal", "stopped-request", "stopped-terminal", "failed-request", "failed-terminal",
            "interrupted-request", "interrupted-terminal"]
        check(rows.map(\.id) == expectedIDs, "visible IDs/order changed or internal/duplicate terminal rows remain")
        check(rows.map(\.record) == raw.filter { expectedIDs.contains($0.event.id) }, "visible message contents or metadata changed")
        for task in [work, clarification, noAnswer, stopped, failed, interrupted] {
            check(rows.filter { $0.record.event.taskID == task && $0.showsWork }.count == 1, "task has missing/repeated work header: \(task)")
        }
        check(rows.first { $0.id == "progress-first" }?.showsWork == true && rows.first { $0.id == "final-answer" }?.showsWork == false,
              "work header is not attached once to the first response")
        check(rows.first { $0.id == "first-question" }?.showsWork == true, "question-first task lacks work summary")
        check(rows.first?.timeBreak == began && rows.dropFirst().allSatisfy { $0.timeBreak == nil }, "continuous exchanges gained repeated date separators")
        check(Layout.destination("hidden-done", records: raw) == "progress-first", "hidden terminal navigation did not target visible task response")
        check(Layout.destination("hidden-clarification-done", records: raw) == "first-question", "hidden terminal navigation lost question-first task")
        check(Layout.destination("stopped-terminal", records: raw) == "stopped-terminal", "standalone terminal navigation was incorrectly remapped")
        check(Layout.destination("final-answer", records: raw) == "final-answer", "ordinary message navigation changed")
        check(Layout.destination("unknown-id", records: raw) == "unknown-id", "unknown navigation guessed an unrelated response")
        check(Layout.rows([]).isEmpty, "empty transcript created synthetic chrome")

        // The Ask bar's card is a waiting question's one place: the transcript leaves that row out.
        let asking = UUID(), askingTask = UUID(), words = "Protect the afternoon or keep it open?"
        let recorded = record("question:" + asking.uuidString, task: askingTask, kind: .question, text: "It failed.\n\n" + words)
        check(Layout.pendingQuestion(raw + [recorded], id: asking) == recorded.event.id, "run-recorded pending question still drawn beside its card")
        check(Layout.pendingQuestion(raw + [recorded, record("later-question", task: askingTask, kind: .question)], id: asking) == recorded.event.id,
              "run-recorded question not found by its id")
        check(Layout.pendingQuestion(raw + [recorded], id: nil) == nil, "no card, yet a question was hidden")
        // Only the card's own row leaves: a question it is not (older, dismissed, or paged out of
        // view while the card's row is) stays in history, even with the same words.
        let sameWords = record("older-question", task: askingTask, kind: .question, text: words)
        check(Layout.pendingQuestion(raw + [sameWords], id: asking) == nil, "a different row with the card's words was hidden")
        check(Layout.pendingQuestion(raw + [sameWords, recorded], id: UUID()) == nil, "another card's question hid this one")

        // Search excerpts: word boundaries, ellipses wherever the message goes on, one line of spaces.
        let plan = "Your afternoon has room for one focused session.\n\n1. Finish the calendar research.\n• Compare the two open windows."
        check(Layout.excerpt(plan, query: "calendar research") == "…has room for one focused session. 1. Finish the calendar research. • Compare the two open windows.",
              "excerpt keeps line breaks")
        check(Layout.excerpt(plan, query: "compare") == "…session. 1. Finish the calendar research. • Compare the two open windows.",
              "excerpt starts mid-word (“…sed session”) or matches case-sensitively")
        check(Layout.excerpt(plan, query: "afternoon") == "Your afternoon has room for one focused session. 1. Finish the calendar research. • Compare the two open windows.",
              "early match gained a leading ellipsis")
        let long = Layout.excerpt(String(repeating: "alpha beta ", count: 40), query: "", length: 30)
        check(long == "alpha beta alpha beta alpha…", "excerpt cut mid-word or lost its trailing ellipsis")
        check(Layout.excerpt("no match here", query: "absent") == "no match here", "missing match changed short text")
        check(Layout.progressNote("I'll check your calendar.\n→ sentient_native.get_app_state") == "I'll check your calendar.",
              "human progress survives while raw tool label stays in activity")
        check(Layout.progressNote("Thinking through your task") == nil, "generic thinking uses the friendly live placeholder")
        check(Layout.progressNote("→ sentient_recovery.describe_task_usage\nSTATUS: DONE") == nil,
              "tool bookkeeping and terminal sentinels do not become progress notes")
        check(Layout.progressNote("one\ntwo\nthree") == "two\nthree", "progress remains bounded to recent lines")
        check(Layout.progressNote(String(repeating: "x", count: 2000))?.count == 800,
              "large progress lines remain bounded")

        let incomplete = Layout.rows([record("pending-request", task: UUID(), kind: .userMessage)])
        check(incomplete.count == 1 && !incomplete[0].showsWork, "unanswered request fabricated a completed response/header")

        // A long response is ongoing work, not a user returning after an inactivity gap.
        let timingTask = UUID()
        let timed = Layout.rows([
            record("time-request", task: timingTask, kind: .userMessage, seconds: 0),
            record("slow-response", task: timingTask, kind: .assistantMessage, seconds: 7200),
            record("exact-thirty", task: UUID(), kind: .userMessage, seconds: 9000),
            record("more-than-thirty", task: UUID(), kind: .userMessage, seconds: 10800.001),
            record("later-question", task: UUID(), kind: .question, seconds: 18000),
            record("exact-answer", task: UUID(), kind: .answer, seconds: 19800),
            record("late-answer", task: UUID(), kind: .answer, seconds: 21600.001)
        ])
        check(timed.filter { $0.timeBreak != nil }.map(\.id) == ["time-request", "more-than-thirty", "late-answer"],
              "30-minute separators are not strict or split model responses/questions")
        check(timed.first { $0.id == "slow-response" }?.timeBreak == nil, "long-running response manufactured a return separator")
        let hiddenTiming = Layout.rows([
            record("visible-before-hidden", task: UUID(), kind: .userMessage, seconds: 0),
            record("hidden-tool-time", task: UUID(), kind: .activity, seconds: 3000),
            record("hidden-checkpoint-time", task: UUID(), kind: .checkpoint, seconds: 3500),
            record("visible-return", task: UUID(), kind: .userMessage, seconds: 3600)
        ])
        check(hiddenTiming.last?.timeBreak == began.addingTimeInterval(3600), "internal tool/checkpoint text reset the visible conversation clock")

        let durations: [(Double, String)] = [(0,"<1s"), (0.999,"<1s"), (1,"1s"), (1.999,"1s"), (59.999,"59s"),
            (60,"1m"), (61,"1m 1s"), (3599,"59m 59s"), (3600,"1h"), (3601,"1h"), (3660,"1h 1m"), (86400,"24h")]
        for (value, label) in durations { check(Layout.duration(value) == label, "duration boundary \(value) formatted incorrectly") }
        for invalid in [-1.0, -.leastNonzeroMagnitude, .nan, .infinity, -.infinity] {
            check(Layout.duration(invalid) == nil, "invalid duration fabricated a time")
        }
        let capped = Layout.duration(.greatestFiniteMagnitude)
        check(capped != nil && capped!.count < 32 && !capped!.contains("inf"), "huge finite duration overflowed or became unreadable")
        func state(_ outcome: Event.Outcome?, startedAt: Date? = began, activity: Bool = false,
                   seconds: Double = 61, status: String = "Fixture outcome") -> Store.TranscriptTaskState {
            let task = UUID()
            let finish = outcome.map { record("label-end-\(task)", task: task, kind: .taskFinished,
                seconds: seconds, text: status, outcome: $0) }
            return .init(taskID: task, firstSequence: 1, startedAt: startedAt, hasActivity: activity, finished: finish)
        }
        check(Layout.workLabel(state: state(.success, activity: true), running: false, waiting: false) == "Worked for 1m 1s", "real tool work label lost measured duration")
        check(Layout.workLabel(state: state(.success), running: false, waiting: false) == "Responded in 1m 1s", "text-only response incorrectly claims tool work")
        check(Layout.workLabel(state: state(.failed), running: false, waiting: false) == "Couldn’t finish · 1m 1s", "failed task claimed success")
        check(Layout.workLabel(state: state(.interrupted), running: false, waiting: false) == "Interrupted · 1m 1s", "interrupted task claimed completion")
        check(Layout.workLabel(state: state(.stopped, status: "[Stopped by user]"), running: false, waiting: false) == "Stopped by you · 1m 1s", "explicit app-recorded user stop lacks truthful stopped label")
        let unknownStop = Layout.workLabel(state: state(.stopped, status: "Stopped before completion"), running: false, waiting: false)
        check(unknownStop.hasPrefix("Stopped") && !unknownStop.localizedCaseInsensitiveContains("by you"), "non-user/unknown stop falsely claims the user stopped it")
        check(Layout.workLabel(state: state(.stopped, status: "  STOPPED BY USER\n"), running: false, waiting: false) == "Stopped by you · 1m 1s", "normalized explicit stop marker was not recognized")
        check(Layout.workLabel(state: state(.stopped, startedAt: nil, status: "Stopped before completion"), running: false, waiting: false) == "Stopped", "unknown legacy stop fabricated user intent or elapsed time")
        check(Layout.workLabel(state: state(.success, startedAt: nil, activity: true), running: false, waiting: false) == "Activity", "legacy task without start fabricated work duration")
        check(Layout.workLabel(state: state(.success, startedAt: nil), running: false, waiting: false) == "Completed", "legacy text response fabricated duration")
        check(Layout.workLabel(state: state(.failed, startedAt: nil), running: false, waiting: false) == "Couldn’t finish", "failed legacy task fabricated duration")
        check(Layout.workLabel(state: state(.success, seconds: -10), running: false, waiting: false) == "Completed", "negative clock interval was presented as elapsed time")
        check(Layout.workLabel(state: state(nil), running: true, waiting: false, now: began.addingTimeInterval(12)) == "Working · 12s", "live elapsed work is not based on actual start")
        check(Layout.workLabel(state: state(nil), running: true, waiting: true, now: began.addingTimeInterval(12)) == "Waiting for your answer · 12s", "waiting state disguised as active task work")
        check(Layout.workLabel(state: nil, running: true, waiting: false, now: began) == "Working…", "unknown live start fabricated elapsed time")
        check(Layout.workLabel(state: state(nil), running: false, waiting: false, now: began.addingTimeInterval(500)) == "Activity", "inactive unterminated task fabricated running duration")

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = date(2026, 10, 17, 12, 34, calendar: calendar)
        let today = date(2026, 10, 17, calendar: calendar)
        check(normalized(Layout.timeBreakLabel(today, now: now, calendar: calendar)) == "9:05 AM", "same-day separator ignores supplied locale/timezone")
        check(normalized(Layout.hoverDate(today, now: now, calendar: calendar)) == "9:05 AM", "same-day hover time is not compact")
        let yesterday = date(2026, 10, 16, calendar: calendar)
        check(Layout.timeBreakLabel(yesterday, now: now, calendar: calendar) == "Yesterday", "yesterday separator was not calendar-relative")
        check(normalized(Layout.hoverDate(yesterday, now: now, calendar: calendar)) == "Yesterday, 9:05 AM", "yesterday hover date lost exact time")
        let weekdays = [2:"Thursday", 3:"Wednesday", 4:"Tuesday", 5:"Monday", 6:"Sunday"]
        for days in 2...6 {
            let previous = date(2026, 10, 17 - days, calendar: calendar)
            check(Layout.timeBreakLabel(previous, now: now, calendar: calendar) == "\(days) days ago", "2–6 day separator wrong")
            let hover = normalized(Layout.hoverDate(previous, now: now, calendar: calendar))
            check(hover.contains(weekdays[days]!) && hover.contains("9:05 AM") && !hover.contains("2026"), "recent hover date lacks weekday/time or adds unnecessary year")
        }
        let sevenDays = date(2026, 10, 10, calendar: calendar)
        check(normalized(Layout.timeBreakLabel(sevenDays, now: now, calendar: calendar)) == "October 10", "seven-day boundary retained relative days label")
        let previousMonth = date(2026, 9, 12, 17, 30, calendar: calendar)
        check(normalized(Layout.timeBreakLabel(previousMonth, now: now, calendar: calendar)) == "September 12", "older month/day separator wrong")
        let monthHover = normalized(Layout.hoverDate(previousMonth, now: now, calendar: calendar))
        check(monthHover.contains("Sep 12") && monthHover.contains("5:30 PM") && !monthHover.contains("2026"), "same-year older hover date wrong")
        let previousYear = date(2025, 12, 31, 17, 30, calendar: calendar)
        check(normalized(Layout.timeBreakLabel(previousYear, now: now, calendar: calendar)) == "December 31, 2025", "older-year separator omitted year")
        let yearHover = normalized(Layout.hoverDate(previousYear, now: now, calendar: calendar))
        check(yearHover.contains("Dec 31") && yearHover.contains("2025") && yearHover.contains("5:30 PM"), "older-year hover date omitted year/time")

        // Civil days cross 23/25-hour DST days. Relative labels must not divide seconds by 86400.
        for (nowDate, priorDate, expected) in [
            (date(2026, 3, 9, 0, 15, calendar: calendar), date(2026, 3, 8, 0, 30, calendar: calendar), "Yesterday"),
            (date(2026, 3, 9, 0, 15, calendar: calendar), date(2026, 3, 7, 23, 45, calendar: calendar), "2 days ago"),
            (date(2026, 11, 2, 0, 15, calendar: calendar), date(2026, 11, 1, 0, 30, calendar: calendar), "Yesterday"),
            (date(2026, 11, 2, 0, 15, calendar: calendar), date(2026, 10, 31, 23, 45, calendar: calendar), "2 days ago")
        ] { check(Layout.timeBreakLabel(priorDate, now: nowDate, calendar: calendar) == expected, "DST civil-day label used elapsed 24-hour blocks") }
        var british = calendar; british.locale = Locale(identifier: "en_GB")
        check(normalized(Layout.timeBreakLabel(today, now: now, calendar: british)) == "09:05", "supplied 24-hour locale ignored")
        var utc = calendar; utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcNow = date(2026, 10, 18, 1, 0, calendar: utc), utcPrevious = date(2026, 10, 17, 23, 0, calendar: utc)
        check(Layout.timeBreakLabel(utcPrevious, now: utcNow, calendar: utc) == "Yesterday", "UTC calendar boundary ignored")
        check(normalized(Layout.timeBreakLabel(utcPrevious, now: utcNow, calendar: calendar)) == "4:00 PM", "same instant incorrectly used process timezone instead of supplied calendar")

        // The viewport's end: resting on the Ask bar, the end marker leaves fromBottom at -insetBottom.
        // A resize or a new inset from there re-pins; a scroll or new content never moves the reader.
        typealias Viewport = Layout.Viewport
        let pinned = Viewport(top: 900, height: 760, insetTop: 52, insetBottom: 90, fromBottom: -90)
        let shorter = Viewport(top: 900, height: 740, insetTop: 52, insetBottom: 90, fromBottom: -70)
        check(pinned.atEnd && !Viewport().atEnd, "the end is the marker on the Ask bar's edge, never an unmeasured viewport")
        check(!shorter.atEnd, "20 pt short of the end is not the end, though within the 70 pt latest distance")
        check(Viewport.keepsEnd(from: pinned, to: shorter), "a window 20 pt shorter left the reader off the end")
        check(Viewport.keepsEnd(from: pinned, to: Viewport(top: 900, height: 760, insetTop: 52, insetBottom: 140, fromBottom: -90)),
              "a taller Ask bar left the reader off the end")
        check(Viewport.keepsEnd(from: pinned, to: Viewport(top: 900, height: 760, insetTop: 104, insetBottom: 90, fromBottom: -90)),
              "a toolbar band's inset is not kept at the end")
        let scrolled = Viewport(top: 700, height: 760, insetTop: 52, insetBottom: 90, fromBottom: 110)
        check(!Viewport.keepsEnd(from: pinned, to: scrolled), "a scroll away from the end was undone")
        check(!Viewport.keepsEnd(from: pinned, to: Viewport(top: 900, height: 760, insetTop: 52, insetBottom: 90, fromBottom: 200)),
              "new content alone moved the reader")
        check(!Viewport.keepsEnd(from: scrolled, to: Viewport(top: 700, height: 740, insetTop: 52, insetBottom: 90, fromBottom: 130)),
              "a resize moved a reader who was above the end")
        // A narrower column re-wraps: the content grows in the same change that narrows it.
        let wide = Viewport(top: 900, height: 760, insetTop: 52, insetBottom: 90, fromBottom: -90, width: 860, contentHeight: 1750)
        let narrow = Viewport(top: 900, height: 760, insetTop: 52, insetBottom: 90, fromBottom: -10, width: 700, contentHeight: 1830)
        check(Viewport.keepsEnd(from: wide, to: narrow), "a narrower window's re-wrap left the reader off the end")
        // A pin asked for at one change has not landed when the next arrives (a live resize).
        check(Viewport.keepsEnd(from: shorter, to: Viewport(top: 900, height: 720, insetTop: 52, insetBottom: 90, fromBottom: -50), pinPending: true),
              "a second resize before the first pin landed lost the end")
        check(!Viewport.keepsEnd(from: shorter, to: Viewport(top: 700, height: 740, insetTop: 52, insetBottom: 90, fromBottom: 130), pinPending: true),
              "a pending pin undid a scroll")
        // Coming back to Home: a follower goes to the end; a paused reader only when it was at the end
        // and nothing new came (no new item, no taller content at the same width), else it keeps its row.
        let left = Viewport(top: 900, height: 760, insetTop: 52, insetBottom: 90, fromBottom: -90, width: 860, contentHeight: 1750)
        func saved(following: Bool, atEnd: Bool) -> Layout.SavedPlace {
            .init(atBottom: following, atEnd: atEnd, lastItemID: "last", viewport: left, rowID: "row", rowTop: 12,
                  generation: nil, scrollRequest: 1)
        }
        let shorterNow = Viewport(top: 900, height: 740, insetTop: 52, insetBottom: 90, fromBottom: -70, width: 860, contentHeight: 1750)
        let grown = Viewport(top: 900, height: 760, insetTop: 52, insetBottom: 90, fromBottom: 30, width: 860, contentHeight: 1870)
        let rewrapped = Viewport(top: 900, height: 760, insetTop: 52, insetBottom: 90, fromBottom: -10, width: 700, contentHeight: 1830)
        check(saved(following: true, atEnd: false).returnsToEnd(lastItemID: "newer", now: grown), "a follower did not return to the latest message")
        check(saved(following: false, atEnd: true).returnsToEnd(lastItemID: "last", now: shorterNow), "a paused reader at the end did not stay at the end")
        check(saved(following: false, atEnd: true).returnsToEnd(lastItemID: "last", now: rewrapped), "a re-wrap while away read as new content")
        check(!saved(following: false, atEnd: true).returnsToEnd(lastItemID: "newer", now: left), "a paused reader was moved to a reply that came while away")
        check(!saved(following: false, atEnd: true).returnsToEnd(lastItemID: "last", now: grown),
              "a paused reader was moved to work that grew under its last item while away")
        check(!saved(following: false, atEnd: false).returnsToEnd(lastItemID: "last", now: left), "a paused reader above the end lost its row")
        print("\(checks - failures.count)/\(checks) Sidekick transcript-layout checks passed")
        if !failures.isEmpty { exit(1) }
    }
}
'''
with tempfile.TemporaryDirectory(prefix="sentient-transcript-layout-") as temporary:
    root = Path(temporary)
    source = root / "TranscriptLayoutChecks.swift"
    source.write_text(FIXTURE)
    binary = root / "checks"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                    "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
                    str(APP / "Notch Magic/SidekickConversationStore.swift"),
                    str(APP / "Views/Sidekick/SidekickTranscriptLayout.swift"), str(source), "-o", str(binary)],
                   check=True, timeout=60)
    subprocess.run([str(binary)], check=True, timeout=30)
