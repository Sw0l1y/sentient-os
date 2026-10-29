//
//  PlanEditor.swift
//  Sentient OS macOS  ·  Views/
//
//  The computer-use plan's editor, built like Reminders: one editable row per step with its
//  number leading in secondary, Return adds the next step, Delete on an empty step removes it,
//  and a final "Add Step" row appends one. Same contract as TextEditor(text:): the binding is
//  the only output, written only on a user edit, so autosave and the verbatim fire path are
//  untouched. Height hugs the steps; the host (the draft block or the letter sheet's form)
//  scrolls. Used by the draft block for computer-use plans.
//

import SwiftUI

struct PlanEditor: View {
    @Binding var text: String
    var accent: Color

    @State private var preamble = ""
    /// Set by `parse()` only, so clearing the notes field mid-edit does not unmount it.
    @State private var hasPreamble = false
    @State private var steps: [PlanStep] = []
    /// The text this editor last parsed or wrote. An external change (a card switch) re-parses
    /// only when the binding differs from it.
    @State private var lastSerialized: String?
    /// True for the run loop in which `parse()` assigns `steps`, so that assignment is never
    /// written back: a plan with irregular numbering or blank lines is normalised on the first
    /// real edit only, never on display.
    @State private var suppressCommit = false
    @FocusState private var focused: UUID?

    private struct PlanStep: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    private static let stepNumber = try! NSRegularExpression(pattern: #"^\s*\d+[.)]"#)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if hasPreamble {
                TextField("Notes", text: $preamble, axis: .vertical)
                    .textFieldStyle(.plain)
            }
            ForEach($steps) { $step in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(number(of: step.id)).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                        .accessibilityHidden(true)
                    TextField("Step", text: $step.text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($focused, equals: step.id)
                        .accessibilityLabel("Step \(number(of: step.id))")
                        .onSubmit { insertStep(after: step.id) }
                        .onKeyPress(.delete) {
                            guard step.text.isEmpty, steps.count > 1 else { return .ignored }
                            removeStep(step.id)
                            return .handled
                        }
                }
            }
            Button { insertStep(after: steps.last?.id) } label: {
                Label("Add Step", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .tint(accent)
        .autocorrectionDisabled()
        .onAppear(perform: parse)
        .onChange(of: text) { _, new in if new != lastSerialized { parse() } }
        .onChange(of: steps) { _, _ in commit() }
        .onChange(of: preamble) { _, _ in commit() }
    }

    private func number(of id: UUID) -> Int {
        (steps.firstIndex { $0.id == id } ?? 0) + 1
    }

    /// `text` → preamble (lines before the first numbered line) + steps. Each line matching
    /// `^\s*\d+[.)]` starts a step with its number token stripped; un-numbered lines after it
    /// join that step with "\n".
    private func parse() {
        suppressCommit = true
        lastSerialized = text
        var head: [String] = []
        var parsed: [PlanStep] = []
        for line in text.components(separatedBy: "\n") {
            let ns = line as NSString
            if let match = Self.stepNumber.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let rest = ns.substring(from: NSMaxRange(match.range))
                parsed.append(PlanStep(text: rest.hasPrefix(" ") ? String(rest.dropFirst()) : rest))
            } else if parsed.isEmpty {
                head.append(line)
            } else {
                parsed[parsed.count - 1].text += "\n" + line
            }
        }
        // A plan with no numbered lines keeps its whole text as notes; an empty plan starts empty.
        let notes = head.joined(separator: "\n")
        preamble = notes
        hasPreamble = !notes.isEmpty
        steps = parsed
        DispatchQueue.main.async { suppressCommit = false }
    }

    /// Preamble (if any) + "N. step" lines, joined by "\n". `parse()` itself never writes back.
    private func commit() {
        let body = steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }
        let out = ((hasPreamble ? [preamble] : []) + body).joined(separator: "\n")
        guard !suppressCommit, out != text else { return }
        lastSerialized = out
        text = out
    }

    private func insertStep(after id: UUID?) {
        let new = PlanStep(text: "")
        let at = id.flatMap { target in steps.firstIndex { $0.id == target } }.map { $0 + 1 } ?? steps.count
        steps.insert(new, at: at)
        focused = new.id
    }

    private func removeStep(_ id: UUID) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        steps.remove(at: i)
        if !steps.isEmpty { focused = steps[max(0, i - 1)].id }
    }
}

#if DEBUG
#Preview("Plan editor") {
    @Previewable @State var text = """
    1. Open the browser to canva.com/settings/billing-and-teams (already logged in).
    2. Under Canva Pro, click Cancel trial.
    3. If asked for a reason, pick 'I don't use it enough'.
    4. Decline any pause, discount, or free-month offers.
    5. Confirm the cancellation.
    6. Verify the page shows Pro ending July 15 with no renewal.
    """
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            PlanEditor(text: $text, accent: .accentColor)
                .frame(width: 420)
                .padding(24)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
#endif
