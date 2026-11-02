import Foundation

/// Presentation only: original events, IDs and task outcomes stay untouched on disk.
nonisolated enum SidekickTranscriptLayout {
    typealias Record = SidekickConversationStore.Record
    struct Row: Identifiable {
        let record: Record
        let showsWork: Bool
        let timeBreak: Date?
        var id: String { record.event.id }
    }

    static func rows(_ records: [Record]) -> [Row] {
        var firstResponse: [UUID: String] = [:]
        for row in records where row.event.kind == .assistantMessage || row.event.kind == .question {
            if firstResponse[row.event.taskID] == nil { firstResponse[row.event.taskID] = row.event.id }
        }
        var result: [Row] = []
        var previousDate: Date?
        for record in records {
            let event = record.event
            guard [.userMessage, .assistantMessage, .question, .answer, .taskFinished].contains(event.kind) else { continue }
            let user = event.kind == .userMessage || event.kind == .answer
            let isEnding = event.kind == .taskFinished
            let visible = !isEnding || firstResponse[event.taskID] == nil
            if visible {
                let separated = result.isEmpty || (user && previousDate.map { event.createdAt.timeIntervalSince($0) > 30 * 60 } == true)
                result.append(Row(record: record,
                    showsWork: firstResponse[event.taskID] == event.id || isEnding,
                    timeBreak: separated ? event.createdAt : nil))
            }
            previousDate = max(previousDate ?? event.createdAt, event.createdAt)
        }
        return result
    }

    /// The question the Ask bar's card is asking right now. The transcript leaves it out while the
    /// card shows it (nothing in two places); answered or dismissed, it is ordinary history again.
    /// The run records the card's question as `question:<id>` (SidekickConversationRun); only that
    /// row is left out, never another one with the same words.
    static func pendingQuestion(_ records: [Record], id: UUID?) -> String? {
        guard let id else { return nil }
        let recorded = "question:" + id.uuidString
        return records.contains(where: { $0.event.id == recorded && $0.event.kind == .question }) ? recorded : nil
    }

    /// A search result's excerpt of already-plain text: up to `length` characters starting a
    /// little before the first case-insensitive match, cut between words, with an ellipsis
    /// wherever the message goes on. Line breaks and runs of spaces read as one space.
    static func excerpt(_ text: String, query: String, lead: Int = 48, length: Int = 220) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var start = words.startIndex
        if !needle.isEmpty, let match = words.range(of: needle, options: .caseInsensitive) {
            start = words.index(match.lowerBound, offsetBy: -lead, limitedBy: words.startIndex) ?? words.startIndex
            // Begin at a word, never inside one; the match itself is the latest possible start.
            if start > words.startIndex, words[words.index(before: start)] != " " {
                start = words[start..<match.lowerBound].firstIndex(of: " ").map { words.index(after: $0) } ?? match.lowerBound
            }
        }
        var end = words.index(start, offsetBy: length, limitedBy: words.endIndex) ?? words.endIndex
        if end < words.endIndex, words[end] != " ", let space = words[start..<end].lastIndex(of: " ") { end = space }
        let body = String(words[start..<end])
        return (start > words.startIndex ? "…" : "") + body + (end < words.endIndex ? "…" : "")
    }

    /// A hidden success/footer event still has a valid history-search destination.
    static func destination(_ id: String, records: [Record]) -> String {
        guard let ending = records.first(where: { $0.event.id == id }), ending.event.kind == .taskFinished else { return id }
        return records.first(where: {
            $0.event.taskID == ending.event.taskID && ($0.event.kind == .assistantMessage || $0.event.kind == .question)
        })?.event.id ?? id
    }

    static func duration(_ interval: TimeInterval) -> String? {
        guard interval.isFinite, interval >= 0 else { return nil }
        if interval < 1 { return "<1s" }
        let seconds = Int(min(interval, 315_576_000))
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, remaining = seconds % 60
        if hours > 0 { return "\(hours)h" + (minutes > 0 ? " \(minutes)m" : "") }
        if minutes > 0 { return "\(minutes)m" + (remaining > 0 ? " \(remaining)s" : "") }
        return "\(remaining)s"
    }

    static func workLabel(state: SidekickConversationStore.TranscriptTaskState?, running: Bool,
                          waiting: Bool, now: Date = Date()) -> String {
        let interval = state?.startedAt.flatMap { start in
            (state?.finished?.event.createdAt ?? (running ? now : nil)).map { $0.timeIntervalSince(start) }
        }
        let elapsed = interval.flatMap(duration)
        if running {
            return (waiting ? "Waiting for your answer" : "Working") + (elapsed.map { " · " + $0 } ?? "…")
        }
        switch state?.finished?.event.outcome {
        case .stopped:
            let reason = state?.finished?.event.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let label = reason == "[stopped by user]" || reason == "stopped by user" ? "Stopped by you" : "Stopped"
            return label + (elapsed.map { " · " + $0 } ?? "")
        case .failed: return "Couldn’t finish" + (elapsed.map { " · " + $0 } ?? "")
        case .interrupted: return "Interrupted" + (elapsed.map { " · " + $0 } ?? "")
        case .success:
            if let elapsed { return state?.hasActivity == true ? "Worked for " + elapsed : "Responded in " + elapsed }
            return state?.hasActivity == true ? "Activity" : "Completed"
        case nil: return "Activity"
        }
    }

    /// The notch already filters prompt echoes/reasoning/command output. Here we keep its
    /// human progress note and let the structured activity rows describe raw tool labels.
    static func progressNote(_ status: String) -> String? {
        let lines = status.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("→") && !$0.hasPrefix("$ ")
                && !$0.uppercased().hasPrefix("STATUS:")
                && $0 != "Thinking through your task" && $0 != "Working…" }
        let text = String(lines.suffix(2).joined(separator: "\n").prefix(800))
        return text.isEmpty ? nil : text
    }

    static func timeBreakLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 0 { return format(date, template: "jm", calendar: calendar) }
        if days == 1 { return "Yesterday" }
        if (2...6).contains(days) { return "\(days) days ago" }
        return format(date, template: calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "MMMMd" : "MMMMdy", calendar: calendar)
    }

    static func hoverDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 0 { return format(date, template: "jm", calendar: calendar) }
        if days == 1 { return "Yesterday, " + format(date, template: "jm", calendar: calendar) }
        if (2...6).contains(days) { return format(date, template: "EEEEjm", calendar: calendar) }
        return format(date, template: calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "MMMdjm" : "MMMd y jm", calendar: calendar)
    }

    private static func format(_ date: Date, template: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
