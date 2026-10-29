// A bounded, non-focus-stealing glimpse of one durable conversation message, laid out like an
// expanded Live Activity with an inline reply (Messages): header, body, capsule compose field.
// The coordinator owns presentation/timing; opening or replying targets the original message.
//
// This file also declares the notch's palette and its one control style. They live here because
// test_sidekick_notch_reply.py compiles this file standalone: it may name only SwiftUI, AppKit,
// SidekickConversationStore, SidekickMarkdown, SidekickNotchMessageLayout, the reduce-motion
// override entry, and what it declares itself.
import SwiftUI

// MARK: - Notch palette and controls

/// The notch's fixed palette. The notch is always OLED black in both system appearances,
/// so these are literals by design. Never used outside the notch files.
enum NotchTone {
    /// The one accent: the identity mark and the thing to press next (Send). Does not follow the system accent.
    static let accent = Color(red: 0.604, green: 0.651, blue: 1.0)   // #9AA6FF
    static let strong = Color.white.opacity(0.90)      // notice text, read-back
    static let primary = Color.white.opacity(0.85)     // status lines, captions, quiet control glyphs
    static let errorText = Color.white.opacity(0.75)   // recovery error body
    static let label = Color.white.opacity(0.70)       // recovery label row
    static let secondary = Color.white.opacity(0.60)   // transcribing, stopped glyph, Hide ✕
    static let quiet = Color.white.opacity(0.50)       // time, vault path, "You can draft a reply"
    static let tertiary = Color.white.opacity(0.45)    // placeholders
    static let controlFill = Color.white.opacity(0.14)
    static let controlHover = Color.white.opacity(0.22)
    static let controlPress = Color.white.opacity(0.30)
    static let fieldFill = Color.white.opacity(0.12)
}

/// The three shapes a notch control can take. `tile` is a 10 pt continuous rounded rectangle.
enum NotchControlShape { case circle, capsule, tile }

/// Every pressable thing in the notch. The label sets its frame; the style supplies fill, glyph
/// colour, hover and press. Three roles: quiet (white 14%), primary (accent, black glyph), destructive (red).
struct NotchControlStyle: ButtonStyle {
    enum Kind { case quiet, primary, destructive }
    var kind: Kind = .quiet
    var shape: NotchControlShape = .circle

    func makeBody(configuration: Configuration) -> some View {
        NotchControlBody(configuration: configuration, kind: kind, shape: shape)
    }
}

private struct NotchControlBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: NotchControlStyle.Kind
    let shape: NotchControlShape
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    /// Same rule as the app's motion gate: Reduce Motion, the Sidekick override, or Low Power Mode.
    private var stillness: Bool {
        (motionOverride ?? systemReduceMotion) || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        configuration.label
            .foregroundStyle(glyph)
            .background {
                switch shape {
                case .circle: Circle().fill(fill)
                case .capsule: Capsule().fill(fill)
                case .tile: RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill)
                }
            }
            .brightness(brightness)
            .opacity(kind != .quiet && !isEnabled ? 0.4 : 1)
            // Small circles get a 5 pt halo so they stay easy to hit; capsules and tiles use their frame,
            // so adjacent answer tiles 8 pt apart never overlap.
            .contentShape(Rectangle().inset(by: shape == .circle ? -5 : 0))
            .onHover { hovering = $0 && isEnabled }
            // A hit-transparent (disabled) control never receives the hover exit.
            .onChange(of: isEnabled) { _, on in if !on { hovering = false } }
            .animation(stillness ? nil : .easeOut(duration: 0.13), value: hovering)
            .animation(stillness ? nil : .easeOut(duration: 0.13), value: configuration.isPressed)
            .animation(stillness ? nil : .easeOut(duration: 0.13), value: isEnabled)
    }

    private var fill: Color {
        switch kind {
        case .quiet:
            if !isEnabled { return NotchTone.controlFill }
            if configuration.isPressed { return NotchTone.controlPress }
            return hovering ? NotchTone.controlHover : NotchTone.controlFill
        case .primary: return NotchTone.accent
        case .destructive: return Color.red
        }
    }

    private var glyph: Color {
        switch kind {
        case .quiet:
            if !isEnabled { return Color.white.opacity(0.3) }
            return hovering ? Color.white : NotchTone.primary
        case .primary: return Color.black
        case .destructive: return Color.white
        }
    }

    private var brightness: Double {
        guard kind != .quiet, isEnabled else { return 0 }
        return configuration.isPressed ? -0.08 : hovering ? 0.06 : 0
    }
}

// MARK: - Message preview

struct SidekickNotchMessageView: View {
    let message: SidekickConversationStore.Record
    let isTaskRunning: Bool
    let onOpen: () -> Void
    let onReply: (String?) -> Void
    let onStop: () -> Void
    let onSelecting: (Bool) -> Void
    var draft: Binding<String> = .constant("")
    var replyFocused = false
    var replyingToSelection = false
    var onReplyFocusChanged: (Bool) -> Void = { _ in }
    var onSend: (String) -> Bool = { _ in false }
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduceMotion: Bool {
        (motionOverride ?? systemReduceMotion) || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var canSend: Bool {
        !isTaskRunning && !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SidekickNotchMessageLayout.sectionSpacing) {
            labelRow
            bodyScroll
            replyRow
            footer
        }
        .padding(.top, SidekickNotchMessageLayout.topPad)
        .padding(.bottom, SidekickNotchMessageLayout.bottomPad)
        // The hardware notch stays OLED black in both system appearances, so its system controls
        // (the field, the Markdown text view) draw in the dark appearance locally.
        .environment(\.colorScheme, .dark)
        .onChange(of: fieldFocused) { _, value in onReplyFocusChanged(value) }
        .onChange(of: draft.wrappedValue) { _, _ in onReplyFocusChanged(fieldFocused) }
        .onChange(of: replyFocused) { _, value in if !value { fieldFocused = false } }
        .onDisappear { onSelecting(false); onReplyFocusChanged(false) }
        .accessibilityElement(children: .contain)
    }

    /// Live Activity header: who is speaking, and when.
    private var labelRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(message.event.messageKind == .answer ? "Sidekick" : "An update from Sidekick")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Text(message.event.createdAt, style: .time)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NotchTone.quiet)
                .accessibilityLabel("Received at \(message.event.createdAt.formatted(date: .omitted, time: .shortened))")
        }
        .frame(height: SidekickNotchMessageLayout.labelHeight)
    }

    /// The answer itself, in the native Markdown renderer; long answers scroll under a short fade mask.
    private var bodyScroll: some View {
        ScrollView(.vertical) {
            SidekickMarkdown(markdown: message.event.text, compact: true, onReply: {
                onReply($0); fieldFocused = true
            },
                onSelectionChange: onSelecting)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, SidekickNotchMessageLayout.textVerticalPad)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .mask {
            VStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 9)
            }
            .allowsHitTesting(false)
        }
    }

    /// Messages-style inline reply: a capsule field and an accent send circle. Focus shows as the
    /// caret plus a fill step (12% → 14%); there is no stroked ring.
    private var replyRow: some View {
        HStack(spacing: 10) {
            TextField(replyingToSelection ? "Reply to selected text…" : "Reply to Sidekick…", text: draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .tint(NotchTone.accent)
                .focused($fieldFocused)
                .onSubmit(send)
                .accessibilityLabel("Reply to Sidekick")
                .accessibilityIdentifier("sidekick.notch.reply")
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(NotchControlStyle(kind: .primary, shape: .circle))
            .disabled(!canSend)
            .help(isTaskRunning ? "Send when Sidekick finishes" : "Send reply")
            .accessibilityLabel("Send reply")
            .accessibilityIdentifier("sidekick.notch.sendReply")
        }
        .padding(.horizontal, 11)
        .frame(height: SidekickNotchMessageLayout.replyHeight)
        .background(fieldFocused ? NotchTone.controlFill : NotchTone.fieldFill, in: Capsule())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: fieldFocused)
    }

    /// One secondary action (open the full conversation), the selection chip or the running hint, and STOP.
    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Label("Open in Sentient", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: SidekickNotchMessageLayout.footerHeight)
            }
            .buttonStyle(NotchControlStyle(kind: .quiet, shape: .capsule))
            .accessibilityHint("Open this exact response in your full conversation")
            Spacer(minLength: 8)
            if replyingToSelection {
                Button { onReply(nil) } label: {
                    Label("Selected text", systemImage: "xmark")
                        .font(.system(size: 10))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                }
                .buttonStyle(NotchControlStyle(kind: .quiet, shape: .capsule))
                .help("Reply to the whole message instead")
            } else if isTaskRunning {
                Text("You can draft a reply")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTone.quiet)
            }
            if isTaskRunning {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: SidekickNotchMessageLayout.footerHeight, height: SidekickNotchMessageLayout.footerHeight)
                }
                .buttonStyle(NotchControlStyle(kind: .quiet, shape: .circle))
                .help("Stop current task")
                .accessibilityLabel("Stop current Sidekick task")
            }
        }
    }

    private func send() {
        guard canSend else { return }
        let text = draft.wrappedValue
        if onSend(text) { fieldFocused = false }
    }
}
