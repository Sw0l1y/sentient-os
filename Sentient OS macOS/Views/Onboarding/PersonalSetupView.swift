// Finish Setup: an ordinary Settings-style page in the main window's sidebar, titled by the
// window. Home stays mounted behind it, so the notch and a live Sidekick conversation keep their
// lifetime while sources are chosen. OnboardingReadyView is the page's form and its pinned
// Start Analysis footer; this view adds only the problem line.
import SwiftUI

struct PersonalSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            if let problem {
                StatusLabel(problem, tone: .warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: PageMetrics.setupPage, alignment: .leading)
                    .padding(.horizontal, Space.xl)
                    .padding(.top, Space.m)
                    .accessibilityIdentifier("personalSetup.problem")
            }
            OnboardingReadyView(onStart: { timing in
                guard appState.finishPersonalSetup(timing) else {
                    problem = "Choose three available sources and wait for any current analysis to finish, then try again."
                    return
                }
                MainNavigation.shared.show(timing == .now ? .analysis : .home)
            }, isProcessing: appState.processing.isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("personalSetup.window")
        .onAppear {
            guard appState.hasCompletedOnboarding else {
                MainNavigation.shared.show(.home)
                return
            }
            PersonalSetupProgress.begin()
            _ = PersonalSetupProgress.consumeRelaunchResume()
        }
        .allowsHitTesting(appState.hasCompletedOnboarding)
    }
}
