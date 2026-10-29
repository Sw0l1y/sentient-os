import SwiftUI

/// The Clear Chat confirmation copy (SPEC-00 Part 9). The legacy toolbar button that used to live
/// here had no callers after Home moved Clear Chat into its More menu (`SidekickClearChatMenuItem`),
/// so the final cleanup deleted it (SPEC-D2 2.10); `sidekick.clearChat` is now only on the menu item.
enum SidekickClearChatButton {
    static let reassurance = "You can keep chatting. Sidekick automatically summarizes older messages in the background, so there’s no need to clear your chat unless you want to start fresh."
    static let consequence = "Clearing your chat deletes its history and conversation context. Your knowledge base and saved Sidekick instructions stay."
}

/// "Clear Chat…" in Home's More menu, like Messages' Delete Conversation… or Safari's Clear History….
/// It only raises the confirmation; the dialog itself is hosted once on the Home root by
/// `sidekickClearChatConfirmation(coordinator:presentation:)`, because a dialog attached to a menu
/// item is torn down with the menu.
struct SidekickClearChatMenuItem: View {
    let coordinator: CommandCoordinator
    let presentation: SidekickPresentation
    private var clearing: Bool { coordinator.run.isClearingChat }

    var body: some View {
        Button(clearing ? "Clearing Chat…" : "Clear Chat…", systemImage: "trash") {
            presentation.clearChatConfirmationShown = true
        }
        .disabled(clearing)
        .accessibilityLabel(clearing ? "Clearing chat" : "Clear chat…")
        .accessibilityIdentifier("sidekick.clearChat")
    }
}

extension View {
    /// Hosts "Clear Chat?" and "Chat Couldn’t Be Cleared". Attach exactly once, to the Home root view
    /// (outside the toolbar and outside any `if isPresented` gate).
    func sidekickClearChatConfirmation(coordinator: CommandCoordinator, presentation: SidekickPresentation) -> some View {
        modifier(SidekickClearChatConfirmation(coordinator: coordinator, presentation: presentation))
    }
}

/// One conversation action, backed by the same clear operation on every provider.
private struct SidekickClearChatConfirmation: ViewModifier {
    let coordinator: CommandCoordinator
    let presentation: SidekickPresentation
    @State private var failure: String?
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reducedMotion: Bool { motionOverride ?? systemReducedMotion }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Clear Chat?", isPresented: Binding(
                get: { presentation.clearChatConfirmationShown },
                set: { presentation.clearChatConfirmationShown = $0 }
            ), titleVisibility: .visible) {
                Button(coordinator.run.isRunning ? "Stop and Clear Chat" : "Clear Chat", role: .destructive, action: confirmClear)
                Button("Cancel", role: .cancel) { presentation.clearChatConfirmationShown = false }
            } message: {
                Text("\(SidekickClearChatButton.reassurance)\n\n\(SidekickClearChatButton.consequence)"
                     + (coordinator.run.isRunning ? "\n\nSidekick will stop its current task before clearing the chat." : ""))
            }
            .alert("Chat Couldn’t Be Cleared", isPresented: Binding(
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
                withAnimation(Motion.gated(Motion.standard, reduceMotion: reducedMotion)) {
                    presentation.didClearChat(generation: coordinator.run.conversation.generation)
                }
            } catch { failure = error.localizedDescription }
        }
    }
}
