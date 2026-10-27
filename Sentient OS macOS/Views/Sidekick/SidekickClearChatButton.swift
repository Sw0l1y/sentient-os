import SwiftUI

/// One conversation action, backed by the same clear operation on every provider.
struct SidekickClearChatButton: View {
    let coordinator: CommandCoordinator
    let presentation: SidekickPresentation
    @State private var failure: String?
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reducedMotion: Bool { motionOverride ?? systemReducedMotion }
    private var clearing: Bool { coordinator.run.isClearingChat }

    static let reassurance = "You can keep chatting. Sidekick automatically summarizes older messages in the background, so there’s no need to clear your chat unless you want to start fresh."
    static let consequence = "Clearing your chat deletes its history and conversation context. Your knowledge base and saved Sidekick instructions stay."

    var body: some View {
        SidekickToolbarIconButton(symbol: "trash", busy: clearing) {
            presentation.clearChatConfirmationShown = true
        }
        .disabled(clearing)
        .help(clearing ? "Clearing chat…" : "Clear chat…")
        .accessibilityLabel(clearing ? "Clearing chat" : "Clear chat…")
        .accessibilityIdentifier("sidekick.clearChat")
        .confirmationDialog("Clear chat?", isPresented: Binding(
            get: { presentation.clearChatConfirmationShown },
            set: { presentation.clearChatConfirmationShown = $0 }
        ), titleVisibility: .visible) {
            Button(coordinator.run.isRunning ? "Stop and Clear Chat" : "Clear Chat", role: .destructive, action: confirmClear)
            Button("Cancel", role: .cancel) { presentation.clearChatConfirmationShown = false }
        } message: {
            Text("\(Self.reassurance)\n\n\(Self.consequence)"
                 + (coordinator.run.isRunning ? "\n\nSidekick will stop its current task before clearing the chat." : ""))
        }
        .alert("Chat couldn’t be cleared", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("OK", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "Please try again.") }
    }

    private func confirmClear() {
        presentation.clearChatConfirmationShown = false
        Task { @MainActor in
            do {
                try await coordinator.clearChat()
                withAnimation(SidekickStyle.motion(reducedMotion)) {
                    presentation.didClearChat(generation: coordinator.run.conversation.generation)
                }
            } catch { failure = error.localizedDescription }
        }
    }

}
