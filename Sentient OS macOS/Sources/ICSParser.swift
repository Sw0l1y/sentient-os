// ICSParser.swift
// A small iCalendar (RFC 5545) reader for assignment feeds such as Schoology's "Share Your
// Schoology Calendar" link. It reads VEVENT and VTODO only: UID, SUMMARY, DESCRIPTION, URL,
// LOCATION, CATEGORIES, DTSTART, DTEND, DUE, LAST-MODIFIED, DTSTAMP, STATUS, COMPLETED and
// RECURRENCE-ID. Folded lines are unfolded, TEXT escapes (\n \, \; \\) are undone, nested
// components (VALARM inside a VEVENT, VTIMEZONE) never leak properties into an item, and dates
// are read as all-day (VALUE=DATE or an 8-digit value), UTC ("Z"), TZID-qualified or floating.
// Recurrence rules are not expanded: an assignment feed lists each due date as its own item.
// Foundation only, with no app dependencies, so Scripts/test_school_feed.py compiles it alone.
// Doc: Documentation - Sources - Local (Files, WhatsApp, iMessage, Notes).md

import Foundation

nonisolated enum ICSParser {
    /// A date as the feed wrote it. An all-day value is the start of that day in the parse's
    /// time zone (the feed's X-WR-TIMEZONE, else the Mac's), so it shows as the same calendar day.
    nonisolated struct DateValue: Equatable, Sendable {
        let date: Date
        let allDay: Bool
    }

    nonisolated enum Component: String, Sendable { case event = "VEVENT", todo = "VTODO" }

    nonisolated struct Item: Equatable, Sendable {
        var component: Component
        var uid: String?
        var recurrenceID: String?
        var summary = ""
        var description: String?
        var url: String?
        var location: String?
        var categories: [String] = []
        var start: DateValue?
        var end: DateValue?
        var due: DateValue?
        var lastModified: Date?
        var stamp: Date?
        var status: String?
        var completed = false

        init(component: Component) { self.component = component }

        /// When the item is due: DUE for a to-do, else DTSTART (assignment feeds put the due
        /// time in DTSTART).
        var dueDate: DateValue? { due ?? start }
        var isCancelled: Bool { status?.uppercased() == "CANCELLED" }
        /// A finished to-do (STATUS:COMPLETED or a COMPLETED stamp).
        var isDone: Bool { completed || status?.uppercased() == "COMPLETED" }

        /// A stable identity: the UID (plus RECURRENCE-ID for a moved instance), or, when the
        /// feed has no UID, a hash of what the item says. The same item parses to the same value.
        var identity: String {
            if let uid, !uid.isEmpty { return recurrenceID.map { uid + "#" + $0 } ?? uid }
            let due = dueDate.map { String($0.date.timeIntervalSince1970) + ($0.allDay ? "d" : "t") } ?? ""
            return "nouid:" + ICSParser.fnv1a([component.rawValue, summary, due, url ?? ""].joined(separator: "\u{1F}"))
        }

        /// The newest edit the feed reports (LAST-MODIFIED, else DTSTAMP).
        var revision: Date { lastModified ?? stamp ?? .distantPast }
    }

    nonisolated struct Feed: Sendable {
        let name: String?
        let timeZone: TimeZone?
        let items: [Item]
    }

    // MARK: Parsing

    /// Parse a whole feed. `defaultTimeZone` applies to floating times and all-day dates when the
    /// feed names no X-WR-TIMEZONE. Unreadable lines are skipped, never fatal.
    static func parse(_ text: String, defaultTimeZone: TimeZone = .current) -> Feed {
        let lines = unfold(text)
        // The calendar's zone is needed before any item is read, so look for it first.
        var calendarZone: TimeZone?
        var calendarName: String?
        var depth = 0
        for line in lines {
            guard let property = Property(line) else { continue }
            switch property.name {
            case "BEGIN": depth += 1
            case "END": depth -= 1
            case "X-WR-TIMEZONE" where depth == 1: calendarZone = zone(named: property.value)
            case "X-WR-CALNAME" where depth == 1: calendarName = unescape(property.value)
            default: break
            }
        }
        let zone = calendarZone ?? defaultTimeZone

        var items: [Item] = []
        var stack: [String] = []
        var current: Item?
        for line in lines {
            guard let property = Property(line) else { continue }
            switch property.name {
            case "BEGIN":
                let name = property.value.uppercased()
                stack.append(name)
                if current == nil, let component = Component(rawValue: name) { current = Item(component: component) }
                continue
            case "END":
                let name = property.value.uppercased()
                // Close back to the matching BEGIN, tolerating a missing END inside it.
                if let index = stack.lastIndex(of: name) { stack.removeSubrange(index...) }
                if let item = current, Component(rawValue: name) == item.component,
                   !stack.contains(item.component.rawValue) {
                    items.append(item)
                    current = nil
                }
                continue
            default: break
            }
            // Only the item's own properties: never a VALARM's DESCRIPTION or a VTIMEZONE's DTSTART.
            guard var item = current, stack.last == item.component.rawValue else { continue }
            apply(property, to: &item, zone: zone)
            current = item
        }
        return Feed(name: calendarName, timeZone: calendarZone, items: items)
    }

    private static func apply(_ property: Property, to item: inout Item, zone: TimeZone) {
        switch property.name {
        case "UID": item.uid = property.value.trimmingCharacters(in: .whitespaces)
        case "RECURRENCE-ID": item.recurrenceID = property.value.trimmingCharacters(in: .whitespaces)
        case "SUMMARY": item.summary = clean(unescape(property.value))
        case "DESCRIPTION": item.description = unescape(property.value)
        case "LOCATION": item.location = clean(unescape(property.value))
        case "URL": item.url = property.value.trimmingCharacters(in: .whitespaces)
        case "CATEGORIES":
            for category in splitList(property.value).map(clean) where !category.isEmpty && !item.categories.contains(category) {
                item.categories.append(category)
            }
        case "STATUS": item.status = property.value.trimmingCharacters(in: .whitespaces)
        case "COMPLETED": item.completed = true
        case "DTSTART": item.start = date(property, zone: zone)
        case "DTEND": item.end = date(property, zone: zone)
        case "DUE": item.due = date(property, zone: zone)
        case "LAST-MODIFIED": item.lastModified = date(property, zone: zone)?.date
        case "DTSTAMP": item.stamp = date(property, zone: zone)?.date
        default: break
        }
    }

    /// One content line: NAME;PARAM=VALUE;PARAM="quoted:value":VALUE.
    private struct Property {
        let name: String
        let parameters: [String: String]
        let value: String

        init?(_ line: String) {
            var inQuotes = false
            var colon: String.Index?
            for index in line.indices {
                let character = line[index]
                if character == "\"" { inQuotes.toggle() }
                else if character == ":" && !inQuotes { colon = index; break }
            }
            guard let colon else { return nil }
            let head = line[..<colon]
            value = String(line[line.index(after: colon)...])
            var parts: [String] = []
            var part = ""
            inQuotes = false
            for character in head {
                if character == "\"" { inQuotes.toggle(); part.append(character) }
                else if character == ";" && !inQuotes { parts.append(part); part = "" }
                else { part.append(character) }
            }
            parts.append(part)
            let name = parts.removeFirst().trimmingCharacters(in: .whitespaces).uppercased()
            guard !name.isEmpty else { return nil }
            self.name = name
            var parameters: [String: String] = [:]
            for parameter in parts {
                guard let equals = parameter.firstIndex(of: "=") else { continue }
                let key = parameter[..<equals].trimmingCharacters(in: .whitespaces).uppercased()
                var raw = parameter[parameter.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 { raw = String(raw.dropFirst().dropLast()) }
                parameters[key] = raw
            }
            self.parameters = parameters
        }
    }

    /// RFC 5545 3.1: a line break followed by one space or tab continues the previous line.
    /// Accepts CRLF, LF and lone CR line endings.
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        if let first = lines.first, first.hasPrefix("\u{FEFF}") { lines[0] = String(first.dropFirst()) }
        return lines.filter { !$0.isEmpty }
    }

    /// Undo TEXT escapes: \n or \N → line break, \, → comma, \; → semicolon, \\ → backslash.
    static func unescape(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                switch character {
                case "n", "N": result.append("\n")
                case ",", ";", "\\", ":", "\"": result.append(character)
                default: result.append("\\"); result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping { result.append("\\") }
        return result
    }

    /// A comma-separated TEXT list (CATEGORIES), split on unescaped commas, each unescaped.
    static func splitList(_ value: String) -> [String] {
        var parts: [String] = []
        var part = ""
        var escaping = false
        for character in value {
            if escaping { part.append("\\"); part.append(character); escaping = false }
            else if character == "\\" { escaping = true }
            else if character == "," { parts.append(part); part = "" }
            else { part.append(character) }
        }
        if escaping { part.append("\\") }
        parts.append(part)
        return parts.map(unescape)
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Dates

    private static func date(_ property: Property, zone: TimeZone) -> DateValue? {
        let raw = property.value.trimmingCharacters(in: .whitespaces)
        let digits = raw.filter(\.isNumber)
        let isDate = property.parameters["VALUE"]?.uppercased() == "DATE" || (raw.count == 8 && digits.count == 8)
        if isDate {
            guard let date = components(raw.prefix(8), time: nil, zone: zone) else { return nil }
            return DateValue(date: date, allDay: true)
        }
        // yyyyMMdd'T'HHmm[ss][Z]
        guard let t = raw.firstIndex(where: { $0 == "T" || $0 == "t" }) else { return nil }
        let day = raw[..<t]
        var time = raw[raw.index(after: t)...]
        var utc = false
        if time.hasSuffix("Z") || time.hasSuffix("z") { utc = true; time = time.dropLast() }
        let valueZone: TimeZone
        if utc { valueZone = TimeZone(identifier: "UTC")! }
        else if let tzid = property.parameters["TZID"] { valueZone = self.zone(named: tzid) ?? zone }
        else { valueZone = zone }
        guard let date = components(day, time: time, zone: valueZone) else { return nil }
        return DateValue(date: date, allDay: false)
    }

    private static func components(_ day: Substring, time: Substring?, zone: TimeZone) -> Date? {
        guard day.count == 8, day.allSatisfy(\.isNumber),
              let year = Int(day.prefix(4)), let month = Int(day.dropFirst(4).prefix(2)),
              let dayOfMonth = Int(day.suffix(2)) else { return nil }
        var parts = DateComponents(year: year, month: month, day: dayOfMonth, hour: 0, minute: 0, second: 0)
        if let time {
            guard time.count == 4 || time.count == 6, time.allSatisfy(\.isNumber),
                  let hour = Int(time.prefix(2)), let minute = Int(time.dropFirst(2).prefix(2)) else { return nil }
            parts.hour = hour; parts.minute = minute
            parts.second = time.count == 6 ? Int(time.suffix(2)) : 0
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard (1...12).contains(month), (1...31).contains(dayOfMonth),
              let date = calendar.date(from: parts),
              calendar.component(.day, from: date) == dayOfMonth else { return nil }
        return date
    }

    /// An IANA zone name, tolerating quotes and the "/mozilla.org/…/" style prefix some producers
    /// add. A name the system does not know (a Windows zone name) falls back to the default.
    static func zone(named raw: String) -> TimeZone? {
        var name = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" ").union(.whitespaces))
        if let zone = TimeZone(identifier: name) { return zone }
        while name.hasPrefix("/") { name.removeFirst() }
        if let zone = TimeZone(identifier: name) { return zone }
        // "/mozilla.org/20050126_1/America/New_York" → the last two path components.
        let parts = name.split(separator: "/")
        if parts.count >= 2, let zone = TimeZone(identifier: parts.suffix(2).joined(separator: "/")) { return zone }
        return nil
    }

    // MARK: Duplicates

    /// One item per identity: the newest LAST-MODIFIED (else DTSTAMP) wins; on a tie, the one
    /// later in the feed. Order of first appearance is kept.
    static func deduplicated(_ items: [Item]) -> [Item] {
        var order: [String] = []
        var chosen: [String: Item] = [:]
        for item in items {
            let key = item.identity
            if let existing = chosen[key] {
                if item.revision >= existing.revision { chosen[key] = item }
            } else {
                order.append(key)
                chosen[key] = item
            }
        }
        return order.compactMap { chosen[$0] }
    }

    /// FNV-1a, 64-bit, as hex: a stable identifier that is the same on every launch.
    static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }
}
