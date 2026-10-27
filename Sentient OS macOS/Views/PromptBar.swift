//
//  PromptBar.swift
//  Sentient OS macOS
//
//  The "Tell me what you want me to DO" command bar that docks at the foot of the For You
//  window — the one glowing object on the screen (the jewelry rule). A slow, soft conic
//  AI-gradient glow (the Analyze Now / GlowButton palette, GlowHalo.stops) hugs a glassy
//  rounded field:
//    [ Computer use ]  ·  the prompt input (verb "DO" bolded bright)  ·  ◯↑ send
//  `onSend(text, mode)` is wired LIVE: HomeView builds "Using <mode.promptPhrase>, <text>.
//  My knowledge base is at …" and runs it through CodexCLI.runAgentCommand (codex exec, gpt-6-sol,
//  bypass sandbox).
//
//  Key pieces: PromptBar (the bar) · ModeToggle (the segmented selector) · SendButton ·
//  PromptGlow (the rounded-rect twin of GlowButton's GlowHalo).
//

import SwiftUI

/// What the agent is allowed to drive when it acts on the user's request.
nonisolated enum AgentMode: String, CaseIterable {
    case computer
    var label: String { "Computer use" }
    var icon: String { "desktopcomputer" }
    /// The command-bar prompt phrase: "Using <promptPhrase>, <task>" — fed to CodexCLI.runAgentCommand.
    var promptPhrase: String { "computer use" }
}

struct PromptBar: View {
    var isPresented = true
    /// Fired when the user sends — routes (text, mode) → the command run (CommandRunModel.start).
    var onSend: (String, AgentMode) -> Void = { _, _ in }
    /// Fired when the user taps STOP during a live run.
    var onStop: () -> Void = {}
    /// While running, the bar shows codex's live `statusLine` and the send button becomes STOP.
    var isRunning: Bool = false
    var statusLine: String = ""

    @State private var text = ""
    @State private var mode: AgentMode = .computer
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if isRunning {
                runningArea
                StopButton(action: onStop)
            } else {
                ModeToggle(mode: $mode)
                inputArea
                SendButton(active: !trimmed.isEmpty, action: send)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 11)
        .padding(.vertical, 11)
        .background(field)
        .background(PromptGlow(intensity: isRunning ? 0.7 : (focused ? 0.55 : 0.32)))
        .animation(.easeInOut(duration: 0.4), value: focused)
        .animation(.easeInOut(duration: 0.35), value: isRunning)
        // Launch focus lands HERE, not on the top bar's first button (the orange ring on
        // "Analysis"). defaultFocus declares it; the delayed onAppear claim backs it up —
        // AppKit assigns the window's initial key view a beat after SwiftUI's appear, so an
        // immediate `focused = true` can get stomped.
        .defaultFocus($focused, isPresented)
        .task(id: isPresented) {
            guard isPresented else { focused = false; return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            focused = true
        }
    }

    /// Idle: the editable input (bright "DO" placeholder + the text field).
    private var inputArea: some View {
        ZStack(alignment: .leading) {
            if trimmed.isEmpty { placeholder }
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.primary)
                .tint(Theme.accent)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(send)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    /// Running: the living orb + codex's latest line(s) — monospace, dimmed, ≤2 lines.
    private var runningArea: some View {
        HStack(spacing: 10) {
            OrbMark(size: 16)
            Text(statusLine.isEmpty ? "Working…" : statusLine)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: statusLine)
        }
    }

    private func send() {
        guard !trimmed.isEmpty else { return }
        onSend(trimmed, mode)
        text = ""
    }

    /// "Tell me what you want me to DO" — the verb glows bright; the rest whispers.
    private var placeholder: some View {
        (Text("Tell me what you want me to ").foregroundColor(Theme.Ink.label)
         + Text("DO").foregroundStyle(.primary).fontWeight(.heavy))
            .font(.body)
            .allowsHitTesting(false)
    }

    /// The glassy field with a faint accent hairline that brightens on focus.
    private var field: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.Ink.cardBG)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        Theme.accent.opacity(focused ? 0.6 : 0.32),
                        lineWidth: 1)
            )
    }
}

// MARK: - The Computer use selector

private struct ModeToggle: View {
    @Binding var mode: AgentMode

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AgentMode.allCases, id: \.self) { segment($0) }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(.quinary))
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func segment(_ m: AgentMode) -> some View {
        let on = mode == m
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { mode = m }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: m.icon).font(.subheadline.weight(.semibold))
                Text(m.label).font(.system(size: 11.5, weight: on ? .semibold : .medium))
            }
            .foregroundStyle(on ? .white : Theme.Ink.label)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background {
                if on {
                    Capsule(style: .continuous).fill(.quaternary)
                        .overlay(Capsule(style: .continuous).strokeBorder(
                            LinearGradient(colors: [Theme.accent.opacity(0.85), Theme.accent.opacity(0.30)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1))
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - The send button

private struct SendButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.body.weight(.bold))
                .foregroundStyle(active ? .black : .white.opacity(0.40))
                .frame(width: 32, height: 32)
                .background(Circle().fill(active ? Color.white : Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(.white.opacity(active ? 0 : 0.10), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .shadow(color: Theme.accent.opacity(active ? 0.55 : 0), radius: 11)
        .disabled(!active)
        .animation(.easeInOut(duration: 0.25), value: active)
    }
}

// MARK: - The stop button (replaces send while a run is live)

private struct StopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.callout.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.tertiary))
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .shadow(color: Theme.accent.opacity(0.40), radius: 9)
        .help("Stop")
    }
}

// MARK: - The accent glow (twin of GlowButton's GlowHalo)

/// A still, soft accent bloom hugging the bar (formerly a 60fps rotating rainbow).
private struct PromptGlow: View {
    var intensity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.accent)
            .blur(radius: 16)
            .padding(-2)
            .opacity(intensity * 0.6)
            .animation(.easeInOut(duration: 0.5), value: intensity)
            .allowsHitTesting(false)
    }
}

// MARK: - Preview

#Preview("Prompt bar") {
    ZStack {
        Theme.bg.ignoresSafeArea()
        PromptBar { text, mode in print("[\(mode.rawValue)] \(text)") }
            .padding(40)
    }
    .frame(width: 980, height: 220)
}
