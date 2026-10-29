// The Analysis page in the main window. Leaving it only hides progress; the app owns the task.
// Before the first analysis is set up it shows one unavailable state with "Finish Setup…";
// either way the window subtitle carries the analysis state.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI

struct ProcessingWindowView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(ProcessingView.resizableDemoKey) private var resizableDemo = false

    var body: some View {
        let session = ProcessingCoordinator.shared
        let gated = !appState.hasCompletedPersonalSetup && !appState.processing.initialComplete
            && appState.processing.record.status == .idle && !resizableDemo
        ZStack {
            if gated {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageSubtitle(AnalysisStatusText.subtitle(
                          state: session.state, progress: session.progress,
                          needsAnotherPass: AnalysisStatusText.needsAnotherPass(notice: session.record.notice,
                                                                                progress: session.progress),
                          gated: gated, initialComplete: session.initialComplete),
                      page: .analysis)
    }
}
