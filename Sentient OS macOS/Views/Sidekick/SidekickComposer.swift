import SwiftUI
import AppKit

struct SidekickComposer: View {
    let coordinator: CommandCoordinator
    let presentation: SidekickPresentation
    var isPresented: Bool
    var onAccepted: () -> Void
    var focusRequest = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduced: Bool { motionOverride ?? systemReduced }
    @FocusState private var focused: Bool
    @State private var submissionError: String?
    /// The field has grown past one line; the capsule becomes a rounded rectangle, like Messages.
    @State private var multiline = false

    private var conversation: SidekickConversation { coordinator.run.conversation }
    private var recovery: SidekickRecovery { coordinator.run.recovery }
    private var notchHasKeyboard: Bool {
        coordinator.phase == .typing || coordinator.phase == .listening || coordinator.messageReplyFocused
    }
    private var answering: Bool { recovery.isPending }
    private var text: Binding<String> {
        Binding(get: { answering ? recovery.draft : conversation.draft },
                set: { if answering { recovery.draft = $0 } else { conversation.draft = $0 }; submissionError = nil })
    }
    private var canSend: Bool {
        !coordinator.run.isClearingChat && !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (answering || !coordinator.run.isRunning)
    }

    /// Top to bottom: the RecoveryCard or the ReplyChip, the floating Ask field, then the error
    /// line. HomeView's floating bar supplies no background; the field carries its own glass.
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if answering, let content = recovery.content {
                RecoveryCard(content: content, recovery: recovery, running: coordinator.run.isRunning,
                             stop: coordinator.stop, choose: { choose(question: $0, index: $1) })
                    .transition(.opacity)
            } else if let reference = conversation.replyReference {
                ReplyChip(preview: replyPreview(reference),
                          show: { conversation.show(messageID: reference.messageID) },
                          remove: {
                              withAnimation(Motion.gated(Motion.quick, reduceMotion: reduced)) {
                                  conversation.replyReference = nil
                              }
                          })
                    .transition(.opacity)
            }
            askField
            if let error = submissionError ?? conversation.storageError {
                StatusLabel(error, tone: .error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.l)
            }
        }
        .disabled(coordinator.run.isClearingChat)
        .onChange(of: coordinator.run.isClearingChat) { _, clearing in
            if clearing { focused = false; presentation.composerFocused = false; submissionError = nil }
        }
        .onChange(of: conversation.generation) { _, _ in submissionError = nil }
        .animation(Motion.gated(Motion.standard, reduceMotion: reduced), value: recovery.content?.id)
        .defaultFocus($focused, isPresented && !answering && !notchHasKeyboard)
        .onChange(of: notchHasKeyboard) { _, ownsKeyboard in
            if ownsKeyboard { focused = false; presentation.composerFocused = false }
        }
        .onChange(of: focused) { _, value in presentation.composerFocused = value }
        .onChange(of: isPresented) { _, visible in
            if !visible { focused = false; presentation.composerFocused = false }
        }
        .onChange(of: conversation.replyReference) { _, value in if value != nil && isPresented { focused = true } }
        .onChange(of: focusRequest) { _, _ in
            if isPresented && !notchHasKeyboard && !coordinator.run.isClearingChat { focused = true }
        }
        .onDisappear { presentation.composerFocused = false }
    }

    /// The Messages / Apple Intelligence compose field: a floating glass capsule with a multi-line
    /// field and a circular Send that turns into Stop while a task runs. System focus ring only.
    private var askField: some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            TextField(answering ? "Add your answer…" : "Ask Sentient", text: text, axis: .vertical)
                .textFieldStyle(.plain).font(.body)
                .lineLimit(1...6).focused($focused).onSubmit(handleReturn)
                .padding(.vertical, 7)
                .accessibilityLabel(answering ? "Answer Sidekick" : "Message Sidekick")
                .accessibilityIdentifier("sidekick.composer")
                .help("Return to send. Shift-Return for a new line.")
                .onGeometryChange(for: Bool.self) { $0.size.height > 30 } action: { multiline = $0 }
            if coordinator.run.isRunning && !answering {
                Button(action: coordinator.stop) {
                    Image(systemName: "stop.fill").frame(width: 28, height: 28)
                }
                .glassButtonStyle()
                .buttonBorderShape(.circle)
                .accessibilityLabel("Stop current task")
                .accessibilityIdentifier("sidekick.stop")
                .help("Stop")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.body.weight(.semibold)).frame(width: 28, height: 28)
                }
                .glassButtonStyle(prominent: true)
                .buttonBorderShape(.circle)
                .disabled(!canSend)
                .accessibilityLabel(answering ? "Send answer" : "Send message")
                .accessibilityIdentifier("sidekick.send")
                .help("Send (Return)")
            }
        }
        .padding(.leading, Space.l).padding(.trailing, Space.xs).padding(.vertical, Space.xs)
        .frame(minHeight: 36)
        .modifier(AskFieldShape(multiline: multiline))
    }

    /// Body moved verbatim from the old in-field recovery header.
    private func choose(question: SidekickQuestion, index: Int) {
        recovery.answer(id: question.id, choice: index)
        if recovery.content?.id != question.id {
            Self.didAccept(conversation: conversation, presentation: presentation)
            onAccepted(); focused = true
        }
    }

    private func replyPreview(_ reference: SidekickConversationEvent.ReplyReference) -> AttributedString {
        let raw = reference.selectedText ?? conversation.messages.first(where: { $0.event.id == reference.messageID })?.event.text ?? "Earlier in your conversation"
        let preview = String(raw.prefix(600))
        return (try? AttributedString(markdown: preview, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(preview)
    }

    private func handleReturn() {
        guard isPresented, !coordinator.run.isClearingChat else { return }
        // AppKit's multiline TextField commits on Shift-Return by default. Chat keeps that
        // chord for a newline, including an insertion in the middle of an existing draft.
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                editor.insertNewlineIgnoringFieldEditor(nil)
            } else { text.wrappedValue += "\n" }
            return
        }
        send()
    }

    private func send() {
        guard isPresented, canSend else { return }
        let accepted = withAnimation(Motion.gated(Motion.standard, reduceMotion: reduced)) {
            Self.sendDraft(coordinator: coordinator, presentation: presentation)
        }
        if accepted { onAccepted(); focused = true }
        else {
            submissionError = coordinator.run.statusLine.isEmpty ? "Your message wasn’t sent. Your draft is still here." : coordinator.run.statusLine
        }
    }

    /// The native acceptance lab calls this same composer action. Clear only a durably
    /// accepted request; a busy run, setup refusal or storage failure preserves the draft.
    @discardableResult
    static func sendDraft(coordinator: CommandCoordinator, presentation: SidekickPresentation) -> Bool {
        guard !coordinator.run.isClearingChat else { return false }
        let conversation = coordinator.run.conversation
        let recovery = coordinator.run.recovery
        let value = (recovery.isPending ? recovery.draft : conversation.draft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if let content = recovery.content {
            recovery.answer(id: content.id, text: value)
            guard recovery.content?.id != content.id else { return false }
        } else {
            guard !coordinator.run.isRunning,
                  coordinator.submit(value, mode: .computer, source: .promptBar) else { return false }
            conversation.draft = ""
        }
        didAccept(conversation: conversation, presentation: presentation)
        return true
    }

    private static func didAccept(conversation: SidekickConversation, presentation: SidekickPresentation) {
        presentation.sendPulse &+= 1
        presentation.surface = .conversation
        conversation.requestNavigation()
    }
}

/// The Ask field's glass shape: a capsule at one line, a continuous rounded rectangle once the
/// draft wraps (as Messages does).
private struct AskFieldShape: ViewModifier {
    let multiline: Bool
    func body(content: Content) -> some View {
        if multiline {
            content.floatingGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        } else {
            content.floatingGlass(in: Capsule(), interactive: true)
        }
    }
}

/// Siri's clarification card on macOS 26, built like an inset grouped section: what Sidekick
/// needs, suggested answers, and the consequence. The typed answer goes in the Ask field below.
private struct RecoveryCard: View {
    let content: SidekickRecoveryContent
    let recovery: SidekickRecovery
    let running: Bool
    let stop: () -> Void
    let choose: (_ question: SidekickQuestion, _ index: Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header.font(.subheadline.weight(.semibold))
            Text(content.question?.question ?? content.error ?? "")
                .font(.headline).lineLimit(4).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if content.upgradeOffer != nil {
                SidekickUpgradeActions(recovery: recovery, content: content)
            }
            if let question = content.question {
                HStack(spacing: Space.s) {
                    ForEach(Array(question.answers.enumerated()), id: \.offset) { index, answer in
                        Button { choose(question, index) } label: {
                            Text(answer).lineLimit(3).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            HStack {
                Label("Your answer continues this task", systemImage: "arrow.turn.down.right")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                // Stop ends the task (the only `sidekick.stop` while answering); Dismiss
                // withdraws the question when nothing is running.
                if running {
                    Button("Stop", systemImage: "stop.fill", action: stop)
                        .accessibilityIdentifier("sidekick.stop")
                } else {
                    Button("Dismiss") { recovery.cancel() }
                }
            }
            .buttonStyle(.borderless).controlSize(.small)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    @ViewBuilder private var header: some View {
        if content.upgradeOffer != nil {
            Label("ChatGPT Needs Your Attention", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            Label(content.question == nil ? "A Little Guidance?" : "A Quick Question", systemImage: "questionmark.bubble.fill")
                .foregroundStyle(Color.accentColor)
        }
    }
}

/// The Messages inline-reply preview above the compose field.
private struct ReplyChip: View {
    let preview: AttributedString
    let show: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "arrowshape.turn.up.left").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to a Message").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(preview).font(.callout).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: show) { Image(systemName: "arrow.up.right") }
                .help("Show Original Message").accessibilityLabel("Show original message")
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                .help("Remove Reply").accessibilityLabel("Remove reply")
        }
        .buttonStyle(.borderless).controlSize(.small)
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .fixedSize(horizontal: false, vertical: true)
    }
}
