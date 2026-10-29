// The expanded notch as an interactive Live Activity: a status-labelled error or a clarification
// with two choice tiles, plus a Messages-style capsule field for typed guidance.
// Draft and timing live in SidekickRecovery, so dismissing or moving displays cannot erase them.
// Doc: Documentation - Sidekick - Notch Window & Visual.md
import SwiftUI
import AppKit

/// The same content measurement drives the shell, scroll viewport, and mouse hit area.
/// Short questions take only the space they need; overflow keeps the steering field visible.
struct SidekickRecoveryLayout {
    static let questionFont = NSFont.systemFont(ofSize: 14, weight: .medium)
    static let answerFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let errorFont = NSFont.systemFont(ofSize: 12)
    static let errorLineHeight = NSLayoutManager().defaultLineHeight(for: errorFont)
    static let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let labelHeight: CGFloat = 16
    static let sectionSpacing: CGFloat = 10
    static let answerSpacing: CGFloat = 8
    static let answerPadding: CGFloat = 8
    static let scrollHPad: CGFloat = 2
    static let scrollVPad: CGFloat = 4
    static let errorVPad: CGFloat = 4
    static let fieldSpacing: CGFloat = 8
    static let fieldHeight: CGFloat = 40
    static let topPad: CGFloat = 4
    static let bottomPad: CGFloat = 8

    let size: CGSize
    let scrollHeight: CGFloat
    let errorHeight: CGFloat
    let answerWidth: CGFloat

    init(content: SidekickRecoveryContent, metrics: NotchMetrics) {
        let maximum = metrics.size(for: .recovery)
        let textWidth = maximum.width - 2 * (metrics.hPad + Self.scrollHPad)
        let buttonWidth = (textWidth - Self.answerSpacing) / 2
        answerWidth = buttonWidth
        let questionHeight = content.question.map { Self.height($0.question, font: Self.questionFont, width: textWidth) } ?? 0
        let answersHeight = (content.question?.answers ?? []).map {
            max(18, Self.height($0, font: Self.answerFont, width: buttonWidth - 2 * Self.answerPadding))
                + 2 * Self.answerPadding
        }.max() ?? 0
        let chromeHeight = metrics.topRowHeight + metrics.topPad + metrics.bottomPad
            + Self.topPad + Self.bottomPad + Self.fieldSpacing + Self.fieldHeight
        let availableScrollHeight = max(0, maximum.height - chromeHeight)
        let upgradeHeight = content.upgradeOffer.map {
            Self.height($0.explanation, font: Self.errorFont, width: textWidth)
                + SidekickUpgradeActions.actionRowsHeight + Self.sectionSpacing
        } ?? 0
        let questionAndAnswersHeight = questionHeight + answersHeight + 2 * Self.scrollVPad
            + (content.question == nil ? 0 : Self.sectionSpacing) + upgradeHeight
        let errorChrome = Self.labelHeight + 6 + (content.question == nil ? 0 : Self.sectionSpacing)
        // Give the question and answers room first. A long error can scroll in the remaining
        // space; long questions/answers still scroll as a group above the fixed input.
        errorHeight = content.error.map {
            let lineHeight = Self.errorLineHeight
            let available = min(content.question == nil ? availableScrollHeight : 64, max(lineHeight + 2 * Self.errorVPad,
                                       availableScrollHeight - questionAndAnswersHeight - errorChrome))
            let lines = max(1, floor((available - 2 * Self.errorVPad) / lineHeight))
            // Whole lines and an inset keep the first/last lines clear of the scroll edges.
            return min(Self.height($0, font: Self.errorFont, width: textWidth), lines * lineHeight)
                + 2 * Self.errorVPad
        } ?? 0
        let contentHeight = questionAndAnswersHeight + (content.error == nil ? 0 : errorChrome + errorHeight)
        scrollHeight = min(contentHeight, availableScrollHeight)
        size = CGSize(width: maximum.width, height: chromeHeight + scrollHeight)
    }

    private static func height(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        ceil((text as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height)
    }
}

struct SidekickRecoveryView: View {
    @Bindable var recovery: SidekickRecovery
    let content: SidekickRecoveryContent
    let layout: SidekickRecoveryLayout
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }

    private var canSend: Bool { !recovery.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: SidekickRecoveryLayout.fieldSpacing) {
            ScrollView {
                VStack(alignment: .leading, spacing: SidekickRecoveryLayout.sectionSpacing) {
                    // The error block exists only with an error: the layout counts its chrome only then.
                    if let error = content.error {
                        VStack(alignment: .leading, spacing: 6) {
                            statusLabel
                            ScrollView {
                                Text(error)
                                    .font(Font(SidekickRecoveryLayout.errorFont))
                                    .foregroundStyle(NotchTone.errorText)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, SidekickRecoveryLayout.errorVPad)
                            }
                            .scrollIndicators(.hidden)
                            .frame(height: layout.errorHeight)
                            .mask { scrollEdges }
                            .accessibilityLabel("Complete error")
                        }
                    }
                    if content.upgradeOffer != nil {
                        SidekickUpgradeActions(recovery: recovery, content: content)
                            .tint(NotchTone.accent)
                    }
                    if let question = content.question {
                        Text(question.question)
                            .font(Font(SidekickRecoveryLayout.questionFont))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        HStack(alignment: .top, spacing: SidekickRecoveryLayout.answerSpacing) {
                            ForEach(question.answers.indices, id: \.self) { index in
                                Button { recovery.answer(id: question.id, choice: index) } label: {
                                    Text(question.answers[index])
                                        .font(Font(SidekickRecoveryLayout.answerFont))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                                        .padding(SidekickRecoveryLayout.answerPadding)
                                        .frame(width: layout.answerWidth, alignment: .leading)
                                }
                                .buttonStyle(NotchControlStyle(kind: .quiet, shape: .tile))
                                .accessibilityHint("Answer Sidekick and continue this task")
                            }
                        }
                    }
                }
                .padding(.vertical, SidekickRecoveryLayout.scrollVPad)
                .padding(.horizontal, SidekickRecoveryLayout.scrollHPad)
            }
            .scrollIndicators(.hidden)
            .frame(height: layout.scrollHeight)
            .mask { scrollEdges }
            guidanceRow
        }
        .padding(.top, SidekickRecoveryLayout.topPad)
        .padding(.bottom, SidekickRecoveryLayout.bottomPad)
        // The notch is always dark. An environment value stays inside the notch; a preferred
        // colour scheme would leak to the hosting window.
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    /// A status symbol names the kind of problem before the words do: an accent bubble for a
    /// question to answer, an orange triangle for a task that could not finish.
    private var statusLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: content.question == nil ? "exclamationmark.triangle.fill" : "questionmark.bubble.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(content.question == nil ? Color.orange : NotchTone.accent)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(content.question == nil ? "Couldn’t finish this" : "One thing to resolve")
                .font(Font(SidekickRecoveryLayout.labelFont))
                .foregroundStyle(NotchTone.label)
        }
        .frame(height: SidekickRecoveryLayout.labelHeight, alignment: .leading)
    }

    /// The same capsule compose field as the message preview: caret plus a fill step for focus, no ring.
    private var guidanceRow: some View {
        HStack(spacing: 12) {
            TextField(content.question == nil ? "Add a detail, or try again" : "Or type your answer", text: $recovery.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .tint(NotchTone.accent)
                .focused($fieldFocused)
                .onSubmit(send)
                .accessibilityLabel(content.question == nil ? "Guidance for retrying" : "Your answer to Sidekick")
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(NotchControlStyle(kind: .primary, shape: .circle))
            .disabled(!canSend)
            .accessibilityLabel("Send guidance")
            .accessibilityHint("Send your reply and continue this task")
            .help("Send guidance")
        }
        .padding(8)
        .frame(height: SidekickRecoveryLayout.fieldHeight)
        .background(fieldFocused ? NotchTone.controlFill : NotchTone.fieldFill, in: Capsule())
        .animation(Motion.gated(.easeOut(duration: 0.18), reduceMotion: reduceMotion), value: fieldFocused)
    }

    // A soft boundary makes partially scrolled lines recede instead of being sliced against
    // the heading or input. It is an alpha mask, not a visible gradient. Content padding keeps
    // complete lines outside the fade at either end.
    private var scrollEdges: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 6)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 6)
        }
        .allowsHitTesting(false)
    }

    private func send() {
        guard canSend else { return }
        recovery.answer(id: content.id)
    }
}

/// Appears only for an evidence-backed Free/Go provider limit. Every external action is a
/// deliberate click; opening pricing never buys a subscription or changes provider settings.
/// Shared by the notch (dark, notch accent via the caller's tint) and Home's RecoveryCard (system
/// accent): one prominent default and three bordered alternatives, all standard system styles.
struct SidekickUpgradeActions: View {
    @Bindable var recovery: SidekickRecovery
    let content: SidekickRecoveryContent
    static let actionRowsHeight: CGFloat = 36 // one 28-point action row and its 8-point gap

    var body: some View {
        if let offer = content.upgradeOffer {
            VStack(alignment: .leading, spacing: 8) {
                // .callout is 12 pt regular on macOS: the same metrics as SidekickRecoveryLayout.errorFont,
                // which measures this explanation.
                Text(offer.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Upgrade to Plus") {
                        guard recovery.content?.id == content.id else { return }
                        recovery.dismiss()
                        NSWorkspace.shared.open(CodexAuth.upgradeURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sidekick.recovery.upgradePlus")
                    Button("Change AI") {
                        guard recovery.content?.id == content.id else { return }
                        recovery.dismiss()
                        HomeWindowOpening.open(.settings, settingsPane: .frontierModel)
                    }
                    .accessibilityIdentifier("sidekick.recovery.changeAI")
                    Button("Try again") {
                        guard recovery.content?.id == content.id else { return }
                        let guidance = recovery.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        recovery.answer(id: content.id, text: guidance.isEmpty ? "Try this task again." : guidance)
                    }
                    .accessibilityIdentifier("sidekick.recovery.retry")
                    Button("Stop") { recovery.cancel(id: content.id) }
                        .accessibilityIdentifier("sidekick.recovery.stop")
                }
                .buttonStyle(.bordered)   // the three alternatives; Upgrade to Plus sets its own prominent style
                .frame(height: 28)
            }
            .controlSize(.small)
            .buttonBorderShape(.capsule)
        }
    }
}
