#!/usr/bin/env python3
"""The School source's feed reader, snapshot, notes and vault writer, against a fixture feed only.
Compiles the production ICSParser.swift, SchoolAssignments.swift, SchoolFeedFetch.swift and
SchoolFeedVault.swift whole (they are Foundation only) and checks: folded lines, TEXT escapes,
all-day DTSTART and DUE, TZID (plain and /mozilla.org/-prefixed), UTC "Z" and floating times, a
VTODO, a VALARM that must not leak into its event, a missing UID, a duplicate UID whose newer
LAST-MODIFIED wins in either order, cancelled and completed items, the course derivation
(CATEGORIES, a "Course:" line, a trailing "[Course]", a Schoology "/course/<id>/" link that borrows
its name), the 7-days-back / 60-days-ahead window, link normalization (webcal, https only), the
proactive notes ("due tomorrow", "past due"), the vault notes and the owned-file manifest that
never touches a School note Sentient did not write, and that the feed link never reaches a
snapshot, a note or a cycle note. The fetcher is exercised against a loopback HTTP server that
serves the fixture (200), 401, 404, a sign-in page, 503 and an oversized body.
Reads .remake/fixtures/schoology-sample.ics. No network beyond 127.0.0.1, no Keychain, no app
data, no real Schoology link.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import platform
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'Sentient OS macOS'
FIXTURE = ROOT / '.remake' / 'fixtures' / 'schoology-sample.ics'
SOURCES = [APP / 'Sources' / name for name in
           ('ICSParser.swift', 'SchoolAssignments.swift', 'SchoolFeedFetch.swift', 'SchoolFeedVault.swift')]

TESTS = r'''
import Foundation

@main struct Tests {
    nonisolated(unsafe) static var count = 0
    static func check(_ value: Bool, _ label: String) {
        if !value { print("FAIL " + label); exit(1) }
        count += 1
    }

    static func main() async throws {
        let args = CommandLine.arguments
        let fixtureURL = URL(fileURLWithPath: args[1])
        let server = URL(string: args[2])!
        let scratch = URL(fileURLWithPath: args[3], isDirectory: true)
        let text = try String(contentsOf: fixtureURL, encoding: .utf8)
        let la = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = la
        calendar.locale = Locale(identifier: "en_US_POSIX")
        func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
        let now = local(2026, 11, 2, 12)
        let feedLink = URL(string: "https://app.schoology.com/calendar/feed/ical/1700000000/0123456789abcdef0123456789abcdef/ipal.ics")!
        let secret = "0123456789abcdef0123456789abcdef"

        // MARK: Lines and escapes
        check(ICSParser.unfold("SUMMARY:fo\r\n lded\r\nX:1") == ["SUMMARY:folded", "X:1"], "CRLF + space continues a line")
        check(ICSParser.unfold("A:one\n\ttwo\nB:2\n") == ["A:onetwo", "B:2"], "LF + tab continues a line")
        check(ICSParser.unescape(#"a\,b\;c\nd\\e\Nf"#) == "a,b;c\nd\\e\nf", "TEXT escapes are undone")
        check(ICSParser.splitList(#"Assignment,Biology\, Honors"#) == ["Assignment", "Biology, Honors"], "CATEGORIES split on unescaped commas only")

        // MARK: Parsing the fixture
        let feed = ICSParser.parse(text, defaultTimeZone: TimeZone(identifier: "Asia/Tokyo")!)
        check(feed.items.count == 15, "every VEVENT and VTODO is read, nothing else (\(feed.items.count))")
        check(feed.timeZone?.identifier == "America/Los_Angeles" && feed.name == "Fixture Student", "X-WR-TIMEZONE and X-WR-CALNAME")
        func item(_ uid: String) -> ICSParser.Item? { feed.items.first { $0.uid?.hasPrefix(uid) == true } }
        let worksheet = item("sgy-assignment-1001")!
        check(worksheet.summary == "Worksheet 4.2: Systems of Equations, Part 2 (this title is folded across two lines)", "folded SUMMARY with an escaped comma")
        check(worksheet.description == "Problems 1-30\nShow your work; no calculators.", "DESCRIPTION escapes, and the VALARM's DESCRIPTION does not leak")
        check(worksheet.start == ICSParser.DateValue(date: utc("2026-11-04T04:59:00Z"), allDay: false), "TZID=America/New_York time")
        check(worksheet.categories == ["Algebra II"], "CATEGORIES")
        let lab = item("sgy-assignment-2001")!
        check(lab.summary == "Lab report, draft 1" && lab.description == "Course: Biology\nBring goggles; lab coat. Path C:\\labs", "escaped comma, semicolon and backslash")
        check(lab.start == ICSParser.DateValue(date: local(2026, 11, 5), allDay: true), "all-day DTSTART is the start of that day in the feed's zone")
        check(item("sgy-assessment-2002")!.start?.date == utc("2026-11-04T15:00:00Z"), "UTC Z time")
        let todo = item("sgy-todo-3001")!
        check(todo.component == .todo && todo.due == ICSParser.DateValue(date: local(2026, 11, 10), allDay: true) && todo.dueDate == todo.due, "VTODO with an all-day DUE")
        check(item("sgy-todo-3002")!.isDone && item("sgy-cancelled-6004")!.isCancelled, "completed and cancelled items are recognised")
        check(item("sgy-assignment-5001")!.start?.date == local(2026, 11, 12, 8), "floating time uses X-WR-TIMEZONE")
        check(item("sgy-assignment-5002")!.start?.date == utc("2026-11-13T15:00:00Z"), "quoted /mozilla.org/ TZID resolves to America/Chicago")
        let noUID = feed.items.first { $0.uid == nil }!
        check(noUID.summary == "Spirit Day" && noUID.identity.hasPrefix("nouid:")
              && ICSParser.parse(text).items.first { $0.uid == nil }!.identity == noUID.identity
              && noUID.identity != ICSParser.Item(component: .event).identity, "a missing UID gets a stable identity of its own")
        let unknownZone = ICSParser.parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:z\nDTSTART;TZID=Pacific Standard Time:20261103T090000\nEND:VEVENT\nEND:VCALENDAR", defaultTimeZone: la)
        check(unknownZone.items.first?.start?.date == local(2026, 11, 3, 9), "an unknown TZID falls back to the default zone")

        // MARK: Duplicates
        let unique = ICSParser.deduplicated(feed.items)
        let quiz = unique.filter { $0.uid?.hasPrefix("sgy-assessment-2002") == true }
        check(unique.count == 14 && quiz.count == 1 && quiz[0].summary == "Quiz: Cell structure", "duplicate UID keeps the newer LAST-MODIFIED even when the stale copy comes later")
        check(ICSParser.deduplicated(feed.items.reversed()).first { $0.uid?.hasPrefix("sgy-assessment-2002") == true }?.summary == "Quiz: Cell structure", "duplicate UID: order does not matter")

        // MARK: Snapshot: window, courses, links, redaction
        let snapshot = SchoolSnapshot.build(feed.items, now: now, calendar: calendar, feedLink: feedLink)
        func titled(_ t: String) -> SchoolAssignment? { snapshot.assignments.first { $0.title == t } }
        check(snapshot.lower == local(2026, 10, 26) && snapshot.upper == local(2027, 1, 2), "window: 7 days back to the end of the 60th day ahead")
        check(snapshot.assignments.count == 10, "window, cancelled and completed filters (\(snapshot.assignments.count))")
        check(titled("Too old (10 days ago)") == nil && titled("Too far (62 days ahead)") == nil, "items outside the window are dropped")
        check(titled("Semester project (59 days ahead)") != nil && titled("Unit 3 test corrections") != nil, "59 days ahead and 5 days back are kept")
        check(titled("Cancelled field trip") == nil && titled("Finished reading log") == nil, "cancelled events and finished to-dos are dropped")
        check(titled("Worksheet 4.2: Systems of Equations, Part 2 (this title is folded across two lines)")?.course == "Algebra II", "course from CATEGORIES")
        check(titled("Unit 3 test corrections")?.course == "Algebra II", "a /course/<id>/ link borrows its course's name, and the repeated course prefix leaves the title")
        check(titled("Lab report, draft 1")?.course == "Biology", "course from a Course: line in DESCRIPTION")
        check(titled("Quiz: Cell structure")?.course == "Biology", "a generic category is skipped for the course")
        check(titled("Read chapter 5")?.course == "English 10", "course from a trailing [Course] in SUMMARY")
        check(titled("Essay outline")?.course == "Course 9009", "an unnamed Schoology course keeps its ID")
        check(titled("Spirit Day")?.course == SchoolCourse.unsorted && titled("Spirit Day")?.isEvent == true, "no course: Unsorted; a /event/ page is an event")
        check(snapshot.courses == ["Algebra II", "Biology", "Course 9009", "English 10", "World History", "Unsorted"], "courses in order, Unsorted last")
        check(titled("Worksheet 4.2: Systems of Equations, Part 2 (this title is folded across two lines)")?.link == "https://app.schoology.com/course/7001234/assignments/1001", "item links drop their query and fragment")
        check(titled("Map project")?.link == nil, "an http item link is dropped")
        let leak = titled("Calendar sync check")
        check(leak?.link == nil && leak?.details == "Subscribe with [link removed] today", "the feed link is never an item link and is removed from descriptions")
        check(SchoolFeedLink.safeItemLink("https://app.schoology.com/share/" + secret, feed: feedLink) == nil
              && SchoolFeedLink.safeItemLink("https://app.schoology.com/share/12345", feed: feedLink) == "https://app.schoology.com/share/12345",
              "an item link carrying the feed's token is dropped even outside a calendar path")
        check(titled("Unit 3 test corrections")!.isPast(now: now, calendar: calendar) && !titled("Read chapter 5")!.isPast(now: now, calendar: calendar), "past and upcoming")
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        check(!json.contains(secret) && !json.contains("calendar/feed") && !json.contains("sgy-assignment"), "the saved snapshot holds neither the feed link nor raw UIDs")
        check(SchoolSnapshot.build([], now: now, calendar: calendar).assignments.isEmpty, "an empty feed is a valid, empty snapshot")

        // MARK: The link the user pastes
        check(SchoolFeedLink.normalize("  <webcal://district.schoology.com/calendar/feed/ical/1/abc/ipal.ics> ")?.absoluteString
              == "https://district.schoology.com/calendar/feed/ical/1/abc/ipal.ics", "webcal becomes https; whitespace and brackets are trimmed")
        check(SchoolFeedLink.normalize("WEBCALS://x.schoology.com/a.ics")?.scheme == "https", "webcals becomes https")
        check(SchoolFeedLink.normalize("https://calendar.google.com/calendar/ical/x/private-y/basic.ics") != nil, "any https calendar link is accepted")
        for bad in ["http://x.schoology.com/a.ics", "ftp://x.com/a.ics", "not a link", "", "https://user:pw@x.com/a.ics", "https:///a.ics"] {
            check(SchoolFeedLink.normalize(bad) == nil, "refused: \(bad)")
        }
        check(SchoolFeedLink.redact("see " + feedLink.absoluteString + " or " + secret, feed: feedLink) == "see [link removed] or [link removed]", "redaction removes the link and its token")

        // MARK: Status and proactive notes
        func status(_ t: String) -> String { SchoolCycleNotes.status(titled(t)!, now: now, calendar: calendar) }
        check(status("Worksheet 4.2: Systems of Equations, Part 2 (this title is folded across two lines)") == "due tomorrow", "due tomorrow")
        check(status("Quiz: Cell structure") == "due in 2 days", "due in 2 days")
        check(status("Unit 3 test corrections") == "past due: was due 5 days ago", "past due")
        check(status("Spirit Day") == "in 4 days", "events are not due")
        let today = SchoolAssignment(id: "t", title: "T", course: "C", due: local(2026, 11, 2), allDay: true, link: nil, isEvent: false, details: nil)
        let earlier = SchoolAssignment(id: "e", title: "E", course: "C", due: local(2026, 11, 2, 8), allDay: false, link: nil, isEvent: false, details: nil)
        check(SchoolCycleNotes.status(today, now: now, calendar: calendar) == "due today"
              && SchoolCycleNotes.status(earlier, now: now, calendar: calendar) == "past due: was due earlier today", "all-day today is still due; a time earlier today has passed")
        let cycle = SchoolCycleNotes.notes(snapshot, now: now, calendar: calendar)
        check(cycle.first?.sourceID == "school-feed:coverage" && cycle.count == 10, "a coverage note plus every item due through the next 14 days (\(cycle.count))")
        check(!cycle.contains { $0.title.hasPrefix("Semester project") }, "items beyond 14 days stay out of the proactive notes")
        check(cycle.allSatisfy { $0.sourceID.hasPrefix("school-feed:") }, "cycle notes share one source ID namespace")
        check(cycle.contains { $0.title == "Worksheet 4.2: Systems of Equations, Part 2 (this title is folded across two lines) (Algebra II): due tomorrow" && $0.folder == "Algebra II" }, "a cycle note names the class and how soon it is due")
        check(cycle.contains { $0.text.contains("past due: was due 5 days ago. Submission status unknown.") }, "a past-due note says submission is unknown")

        // MARK: Vault notes
        let files = SchoolVaultNotes.render(snapshot, now: now, calendar: calendar)
        check(files.map(\.name) == ["School", "Algebra II", "Biology", "Course 9009", "English 10", "World History", "Unsorted"], "an overview and one note per class")
        let overview = files[0].markdown, algebra = files[1].markdown
        check(overview.hasPrefix("# School\n") && overview.contains("## Due in the next 7 days") && overview.contains("[[Algebra II]]")
              && overview.contains("- [[Algebra II]]: 2 upcoming, 1 recently due"), "overview: this week across classes, with links")
        check(algebra.contains("## Upcoming\n- **Tue, Nov 3, 8:59 PM** · Worksheet 4.2: Systems of Equations, Part 2 (this title is folded across two lines) · [Open in Schoology](https://app.schoology.com/course/7001234/assignments/1001)"),
              "course note: due date, title and link")
        check(algebra.contains("## Recently due\n- **Wed, Oct 28** · Unit 3 test corrections"), "course note: recently due")
        check(files.allSatisfy { !$0.markdown.contains(secret) && !$0.markdown.contains("calendar/feed") && !$0.markdown.contains("—") }, "no note carries the feed link or an em dash")
        check(cycle.allSatisfy { !$0.text.contains(secret) && !$0.title.contains(secret) && !$0.text.contains("calendar/feed") }, "no cycle note carries the feed link")
        check(SchoolVaultNotes.escape("a*b_[c]") == "a\\*b\\_\\[c\\]", "titles are Markdown-escaped")
        check(SchoolVaultNotes.baseName("AP Bio: Period 3/4") == "AP Bio- Period 3-4" && SchoolVaultNotes.baseName("School") == "School (class)", "safe file names")

        // MARK: Vault writer
        let fm = FileManager.default
        let missing = scratch.appendingPathComponent("no-vault")
        check(try SchoolFeedVault.publish(snapshot, root: missing, now: now, calendar: calendar) == false && !fm.fileExists(atPath: missing.path), "no vault: nothing is created")
        let vault = scratch.appendingPathComponent("vault", isDirectory: true)
        let school = vault.appendingPathComponent("School", isDirectory: true)
        try fm.createDirectory(at: school, withIntermediateDirectories: true)
        try "# Biology\nThe architect's own note.\n".write(to: school.appendingPathComponent("Biology.md"), atomically: true, encoding: .utf8)
        check(try SchoolFeedVault.publish(snapshot, root: vault, now: now, calendar: calendar), "publishes into an existing vault")
        let ownBiology = try String(contentsOf: school.appendingPathComponent("Biology.md"), encoding: .utf8)
        check(ownBiology == "# Biology\nThe architect's own note.\n" && fm.fileExists(atPath: school.appendingPathComponent("Biology (Schoology).md").path),
              "a School note Sentient did not write is never replaced; its class note takes another name")
        let written = try String(contentsOf: school.appendingPathComponent("School.md"), encoding: .utf8)
        check(written.contains("[[Biology (Schoology)]]") && !written.contains("[[Biology]]"), "the overview links the names actually written")
        check(SchoolFeedVault.ownedPaths(in: vault) == Set(["School/School.md", "School/Algebra II.md", "School/Biology (Schoology).md", "School/Course 9009.md",
              "School/English 10.md", "School/World History.md", "School/Unsorted.md"]), "the manifest lists exactly Sentient's notes")
        let later = SchoolSnapshot.build(feed.items.filter { !$0.categories.contains("World History") }, now: now, calendar: calendar, feedLink: feedLink)
        try SchoolFeedVault.publish(later, root: vault, now: now, calendar: calendar)
        check(!fm.fileExists(atPath: school.appendingPathComponent("World History.md").path)
              && fm.fileExists(atPath: school.appendingPathComponent("Biology.md").path), "a class that left the feed loses its note; others' notes stay")
        let staging = scratch.appendingPathComponent("staging", isDirectory: true)
        try fm.copyItem(at: vault, to: staging)
        try "# Algebra II\nEdited by the architect.\n".write(to: staging.appendingPathComponent("School/Algebra II.md"), atomically: true, encoding: .utf8)
        try "# Study plan\nThe architect's new note.\n".write(to: staging.appendingPathComponent("School/Study plan.md"), atomically: true, encoding: .utf8)
        SchoolFeedVault.preserve(in: staging, snapshot: later, now: now, calendar: calendar)
        check(try String(contentsOf: staging.appendingPathComponent("School/Algebra II.md"), encoding: .utf8).contains("## Upcoming")
              && fm.fileExists(atPath: staging.appendingPathComponent("School/Study plan.md").path), "a swap restores Sentient's notes and keeps the architect's others")
        let fresh = scratch.appendingPathComponent("fresh-build", isDirectory: true)
        try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        SchoolFeedVault.preserve(in: fresh, snapshot: later, now: now, calendar: calendar)
        check(fm.fileExists(atPath: fresh.appendingPathComponent("School/School.md").path), "a first build's staging gets the School notes too")
        try SchoolFeedVault.publish(nil, root: vault, now: now, calendar: calendar)
        check(SchoolFeedVault.ownedPaths(in: vault).isEmpty && !fm.fileExists(atPath: school.appendingPathComponent("Algebra II.md").path)
              && fm.fileExists(atPath: school.appendingPathComponent("Biology.md").path), "disconnect removes only Sentient's notes")

        // MARK: Fetching (loopback fixture server)
        let body = try await SchoolFeedFetch.fetchBody(from: server.appendingPathComponent("feed.ics"), requireHTTPS: false)
        check(ICSParser.parse(body).items.count == 15, "the served fixture reads like the file")
        let fileBody = try await SchoolFeedFetch.fetchBody(from: fixtureURL, requireHTTPS: false)
        check(fileBody == text, "a file URL fixture reads too")
        func failure(_ path: String, maximumBytes: Int = SchoolFeedFetch.maximumBytes) async -> SchoolFeedFetch.Failure? {
            do { _ = try await SchoolFeedFetch.fetchBody(from: server.appendingPathComponent(path), requireHTTPS: false, maximumBytes: maximumBytes, timeout: 5); return nil }
            catch let error as SchoolFeedFetch.Failure { return error }
            catch { return nil }
        }
        let gone = await failure("gone"), locked = await failure("locked"), login = await failure("login")
        let busy = await failure("busy"), big = await failure("feed.ics", maximumBytes: 100), moved = await failure("moved")
        check(gone == .revoked(status: 404), "404: the school stopped sharing")
        check(locked == .revoked(status: 401), "401: the school stopped sharing")
        check(login == .notCalendar, "a sign-in page is not a calendar")
        check(busy == .server(status: 503), "503: try again later")
        check(big == .tooLarge, "an oversized feed is refused")
        check(moved == nil, "a same-scheme redirect to the feed is followed")
        do { _ = try await SchoolFeedFetch.fetch(server.appendingPathComponent("feed.ics")); check(false, "plain http is refused in production") }
        catch let error as SchoolFeedFetch.Failure { check(error == .invalidLink, "plain http is refused in production") }
        var closed = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        closed.port = Int(args[4])!
        do { _ = try await SchoolFeedFetch.fetchBody(from: closed.url!.appendingPathComponent("feed.ics"), requireHTTPS: false, timeout: 5); check(false, "a closed port is unreachable") }
        catch let error as SchoolFeedFetch.Failure {
            if case .unreachable = error { check(!error.needsNewLink, "a closed port is unreachable and keeps the link") } else { check(false, "a closed port is unreachable (\(error.code))") }
        }
        check(SchoolFeedFetch.Failure.revoked(status: 404).code == "school.feed.revoked.404" && SchoolFeedFetch.Failure.notCalendar.needsNewLink, "failure codes carry status only")

        print("PASS \(count) school feed checks")
    }
}
'''


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/feed.ics':
            self.reply(200, FIXTURE.read_bytes(), 'text/calendar; charset=utf-8')
        elif path == '/locked':
            self.reply(401, b'Unauthorized', 'text/plain')
        elif path == '/login':
            self.reply(200, b'<!DOCTYPE html><html><body>Sign in to Schoology</body></html>', 'text/html')
        elif path == '/busy':
            self.reply(503, b'Try later', 'text/plain')
        elif path == '/moved':
            self.send_response(302)
            self.send_header('Location', '/feed.ics')
            self.send_header('Content-Length', '0')
            self.end_headers()
        else:
            self.reply(404, b'Not found', 'text/plain')

    def reply(self, status, body, kind):
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


assert FIXTURE.exists(), f'missing fixture {FIXTURE}'
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
# A port that was free a moment ago and has nothing listening: the "unreachable" case.
closed = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
closed_port = closed.server_address[1]
closed.server_close()
try:
    with tempfile.TemporaryDirectory(prefix='sentient-school-feed-') as directory:
        path = Path(directory)
        (path / 'Tests.swift').write_text(TESTS)
        scratch = path / 'scratch'
        scratch.mkdir()
        binary = path / 'test'
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                        '-target', f'{platform.machine()}-apple-macos15.0',
                        *map(str, SOURCES), str(path / 'Tests.swift'), '-o', str(binary)], check=True, timeout=180)
        subprocess.run([str(binary), str(FIXTURE), f'http://127.0.0.1:{server.server_address[1]}/',
                        str(scratch), str(closed_port)], check=True, timeout=120)
finally:
    server.shutdown()
