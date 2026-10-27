// The Analysis page in the main window. Leaving it only hides progress; the app owns the task.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI

struct ProcessingWindowView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(ProcessingView.resizableDemoKey) private var resizableDemo = false

    var body: some View {
        if !appState.hasCompletedPersonalSetup && !appState.processing.initialComplete
            && appState.processing.record.status == .idle && !resizableDemo {
            ContentUnavailableView {
                Label("Make Sentient Personal", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("Choose three sources before your first analysis. You can keep using Sidekick while you set up.")
            } actions: {
                Button("Finish Setup…") { MainNavigation.shared.show(.setup) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else {
            ProcessingView { MainNavigation.shared.show(.home) }
        }
    }
}
