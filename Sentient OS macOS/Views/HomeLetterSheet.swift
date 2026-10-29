//
//  HomeLetterSheet.swift
//  Sentient OS macOS
//
//  An opened suggestion, as Mail shows a message being composed: a header (the suggestion's icon,
//  its provenance line and title), one scrolling body (the letter, then the draft with editable
//  To / Subject fields and the body editor, what to check before sending, and the details), and a
//  bottom button bar: Copy, the gift's Save to Desktop / Share…, Done (Esc) and the offer (Return).
//  Every mechanism of the old LetterView (HomeView.swift) moved here verbatim: the per-card seed
//  and reseed, the 300 ms debounced auto-save, the dirty / saved status, the Subject split that
//  recombines into the one draft string, commit-before-fire, and the gift's poster save.
//  SPEC-D1 S11.
//

import SwiftUI
import AppKit

struct HomeLetterSheet: View {
    let briefing: Briefing
    let action: PreparedAction?
    let phase: BriefingPhase
    let editable: Bool                        // real card with a draft → the draft is editable
    let liveDraft: String                     // THIS card's current content (seeds the editor)
    let liveRecipient: String                 // THIS card's "To:" (seeds the recipient field); "" = no recipient
    let fireDimmed: Bool                      // one task at a time: another task is running → the offer waits
    let onCommitEdit: (String, String) -> Void   // persist (edited draft, edited recipient) → what fires
    let onLiveEdit: (String, String) -> Void     // current editor values for Sidekick context
    let onOffer: () -> Void
    let onClose: () -> Void

    @State private var editedDraft = ""        // the live editor text
    @State private var savedDraft = ""         // the last COMMITTED text — drift from editedDraft = unsaved edits
    @State private var editedRecipient = ""    // the live "To:" text
    @State private var savedRecipient = ""     // the last COMMITTED "To:"
    @State private var saveTask: Task<Void, Never>?   // in-flight debounced auto-save
    @State private var everEdited = false      // the user has edited THIS opening — flips "Editable" to the save status
    @State private var savedGiftURL: URL?      // the welcome letter's keepsake PNG on the Desktop (nil = not saved)

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reducedMotion: Bool { motionOverride ?? systemReducedMotion }

    private static let dimmedHelp = "Sidekick is working on another task"

    /// This card sends a message to someone, so it shows an editable "To:" (the model filled a recipient).
    private var hasRecipient: Bool { !liveRecipient.isEmpty }

    /// A research briefing (it reads as a letter, not a working draft): its bullets use quiet ink.
    private var isResearchNote: Bool { briefing.kind != .welcome && briefing.letter != nil }

    /// Auto-save is pending (unsaved edits still settling). Drives the "Saving…" status.
    private var isDirty: Bool { editable && (editedDraft != savedDraft || editedRecipient != savedRecipient) }

    /// What Copy puts on the pasteboard: the live draft when editing, else the card's text.
    private var copyText: String { editable ? editedDraft : (briefing.draft ?? briefing.letter ?? briefing.body) }

    // MARK: Editing (moved verbatim from LetterView)

    /// Commit the current draft + recipient so they persist + are what fires. Cancels any pending debounce.
    private func commitEdit() {
        saveTask?.cancel()
        onCommitEdit(editedDraft, editedRecipient)
        savedDraft = editedDraft
        savedRecipient = editedRecipient
    }

    /// Debounced auto-save: commit ~0.3s after the user stops typing (live, without write-spam).
    private func scheduleAutoSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            commitEdit()
        }
    }

    private func editChanged() {
        guard editable else { return }
        onLiveEdit(editedDraft, editedRecipient)
        if isDirty {
            everEdited = true
            scheduleAutoSave()
        } else {
            saveTask?.cancel()
        }
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    LetterBody(text: briefing.letter ?? briefing.body, accent: briefing.accent,
                               neutral: isResearchNote)
                    if let draft = briefing.draft { draftBlock(draft) }
                    if let action, !action.reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label(action.reviewNote, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if let action { details(action) }
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 620)
        .frame(minHeight: 340, idealHeight: 600, maxHeight: 760)
        // Seed the editor from THIS card's live content — on first appear AND every time a different
        // briefing opens (the sheet content can be reused across cards, so .onAppear alone would show
        // the first card's draft). edited + saved start equal: a freshly-opened card has no unsaved edits.
        .onAppear { editedDraft = liveDraft; savedDraft = liveDraft; editedRecipient = liveRecipient; savedRecipient = liveRecipient }
        // A different card opened: cancel any pending auto-save (it belongs to the OLD card's closure) and reseed.
        .onChange(of: briefing.id) { _, _ in
            saveTask?.cancel(); editedDraft = liveDraft; savedDraft = liveDraft
            editedRecipient = liveRecipient; savedRecipient = liveRecipient
            savedGiftURL = nil; everEdited = false
        }
        // Every keystroke (draft OR recipient) reschedules the debounced commit, so edits persist without a Save click.
        .onChange(of: editedDraft) { _, _ in editChanged() }
        .onChange(of: editedRecipient) { _, _ in editChanged() }
        .onDisappear { saveTask?.cancel() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            HomeSuggestionTile(briefing: briefing, action: action, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(briefing.kicker)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(briefing.title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.l)
    }

    // MARK: Draft

    /// "Subject: X" opening line + the body after it; nil when the draft doesn't open with one.
    /// The draft STRING stays the single verbatim artifact — this only splits it for display.
    private static func splitSubject(_ draft: String) -> (subject: String, body: String)? {
        let lines = draft.components(separatedBy: "\n")
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first.lowercased().hasPrefix("subject:") else { return nil }
        let subject = String(first.dropFirst("subject:".count)).trimmingCharacters(in: .whitespaces)
        var rest = Array(lines.dropFirst())
        while rest.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { rest.removeFirst() }
        return (subject, rest.joined(separator: "\n"))
    }

    /// The Subject field, derived from `editedDraft` — edits recombine into the one draft string,
    /// so auto-save, Copy, and what fires all keep seeing the complete artifact.
    private var draftSubject: Binding<String> {
        Binding(get: { Self.splitSubject(editedDraft)?.subject ?? "" },
                set: { editedDraft = "Subject: \($0)\n\n\(Self.splitSubject(editedDraft)?.body ?? "")" })
    }

    /// The body editor's text — the part after the Subject line when one exists, the whole draft otherwise.
    private var draftBody: Binding<String> {
        Binding(get: { Self.splitSubject(editedDraft)?.body ?? editedDraft },
                set: { newBody in
                    if let subject = Self.splitSubject(editedDraft)?.subject {
                        editedDraft = "Subject: \(subject)\n\n\(newBody)"
                    } else {
                        editedDraft = newBody
                    }
                })
    }

    private func draftBlock(_ draft: String) -> some View {
        let split = Self.splitSubject(editable ? editedDraft : draft)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(briefing.draftLabel ?? "Draft")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if editable { editStatus }
            }
            // "To:" — WHO this message goes to; editable (the executor sends to exactly this), so a wrong
            // recipient is visible and correctable. "Subject:" — an email draft's opening line, composed
            // as its own field while the draft that FIRES stays one verbatim string.
            if hasRecipient || split != nil {
                HomeInsetGroup {
                    VStack(alignment: .leading, spacing: Space.s) {
                        if hasRecipient {
                            LabeledContent("To") {
                                if editable {
                                    TextField("To", text: $editedRecipient)
                                        .labelsHidden()
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    Text(editedRecipient.isEmpty ? liveRecipient : editedRecipient)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        if let split {
                            LabeledContent("Subject") {
                                if editable {
                                    TextField("Subject", text: draftSubject)
                                        .labelsHidden()
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    Text(split.subject)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(Space.m)
                }
            }
            // A computer-use PLAN is a numbered step list (PlanEditor); messages, emails and events are
            // prose (TextEditor). Both ride the same draftBody binding.
            if editable {
                if briefing.isPlan {
                    PlanEditor(text: draftBody, accent: briefing.accent)
                } else {
                    TextEditor(text: draftBody)
                        .font(.body)
                        .lineSpacing(3)
                        .frame(minHeight: 220)
                        .accessibilityLabel(briefing.draftLabel ?? "Draft")
                }
            } else {
                Text(split?.body ?? draft)
                    .font(briefing.isPlan ? .system(.callout, design: .monospaced) : .body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The auto-save status, in one quiet slot. Fresh card: "Editable" (an invitation). Typing:
    /// "Saving…". Edit landed: "Saved" (green — YOUR change is what fires). Never a button.
    @ViewBuilder private var editStatus: some View {
        Group {
            if isDirty {
                Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            } else if everEdited {
                Label("Saved", systemImage: "checkmark")
                    .foregroundStyle(.green)
            } else {
                Label("Editable", systemImage: "pencil")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .animation(Motion.gated(Motion.quick, reduceMotion: reducedMotion), value: isDirty)
        .animation(Motion.gated(Motion.quick, reduceMotion: reducedMotion), value: everEdited)
    }

    // MARK: Details

    private func details(_ action: PreparedAction) -> some View {
        DisclosureGroup("Details") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.xs) {
                if let due = action.dueDate?.trimmingCharacters(in: .whitespacesAndNewlines), !due.isEmpty {
                    detailRow("Due", due)
                }
                detailRow("Urgency", action.urgency.rawValue.capitalized)
                detailRow("Status", statusText(action.status))
                if !action.verification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    GridRow {
                        Text("Verification").foregroundStyle(.secondary)
                        Text(action.verification)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !action.sources.isEmpty {
                    GridRow {
                        Text("Sources").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(action.sources.enumerated()), id: \.offset) { _, source in
                                Text(source)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .font(.callout)
            .padding(.top, Space.xs)
        }
    }

    private func detailRow(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusText(_ status: PreparedAction.Status) -> String {
        switch status {
        case .confirmed:  "Confirmed"
        case .updated:    "Updated"
        case .unverified: "Not verified"
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Space.m) {
            CopyButton(value: copyText)
                .buttonStyle(.bordered)
            if briefing.kind == .welcome { giftControls }
            Spacer(minLength: Space.s)
            Button("Done", action: onClose)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            if let offer = briefing.offer, phase == .offer {
                Button(offer) {
                    if editable { commitEdit() }   // fire what's shown — commit any unsaved edit first
                    onOffer()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(fireDimmed)
                .help(fireDimmed ? Self.dimmedHelp : offer)
            }
        }
        .padding(Space.l)
    }

    /// The welcome letter's keepsake: "Save to Desktop" (a poster PNG of the gift, revealed in Finder),
    /// then "Saved to your Desktop" with a Share… menu for the saved file, and the quiet why.
    @ViewBuilder private var giftControls: some View {
        if let savedGiftURL {
            Label("Saved to your Desktop", systemImage: "checkmark")
                .foregroundStyle(.green)
                .lineLimit(1)
            ShareLink(item: savedGiftURL) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        } else {
            Button("Save to Desktop", systemImage: "square.and.arrow.down", action: saveGift)
                .buttonStyle(.bordered)
        }
        Text("Your gift will be cleared from the home screen soon.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func saveGift() {
        do {
            let url = try GiftShareImage.save(briefing: briefing)
            withAnimation(Motion.gated(Motion.quick, reduceMotion: reducedMotion)) { savedGiftURL = url }
            NSWorkspace.shared.activateFileViewerSelecting([url])   // sharing = one drag from here
        } catch {
            Log("GiftShareImage: save failed — \(ErrorLabel(error))")
        }
    }
}

// MARK: - Previews

private let previewDraftAction = PreparedAction(
    title: "Reply to Priya about Thursday",
    method: .gmail, target: "", urgency: .high, dueDate: "Thursday",
    status: .confirmed, verification: "Checked your thread with Priya.",
    cardSummary: "Priya asked if you’re free Thursday. You are, so I drafted a yes.",
    preparedContent: "Subject: Thursday\n\nHi Priya,\n\nThursday works great. See you at 2.",
    executionRecipe: "Reply in the thread with Priya.",
    recipient: "Priya Iyer · priya@example.com",
    buttonText: "Send It for You?", detailLabel: "read the draft",
    sources: ["Gmail · Priya Iyer", "Calendar · Thursday"], reviewNote: "Confirm the time is 2 PM.")

#Preview("Draft letter") {
    HomeLetterSheet(briefing: Briefing(from: previewDraftAction), action: previewDraftAction, phase: .offer,
                    editable: true, liveDraft: previewDraftAction.preparedContent,
                    liveRecipient: previewDraftAction.recipient, fireDimmed: false,
                    onCommitEdit: { _, _ in }, onLiveEdit: { _, _ in }, onOffer: {}, onClose: {})
}

#Preview("Gift letter") {
    let sample = """
    # The System Builder's Map

    I just analyzed your digital life to understand you.
    ### Something you might not know about yourself

    **Your real pattern is turning recurring ambiguity into reusable systems.**

    ## Also noticed

    ✦ Your breakout projects keep starting from Apple-shaped constraints.
    ✦ You maintain tailored prompts across several assistants.

    -- Your Sentient
    """
    return HomeLetterSheet(briefing: Briefing(fromGiftMarkdown: sample), action: nil, phase: .offer, editable: false,
                           liveDraft: "", liveRecipient: "", fireDimmed: false,
                           onCommitEdit: { _, _ in }, onLiveEdit: { _, _ in }, onOffer: {}, onClose: {})
        .environment(\.colorScheme, .dark)
}
