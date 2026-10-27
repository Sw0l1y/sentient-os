// Optional personal-context setup is a page in the main window. Home stays mounted behind it,
// so the notch and a live Sidekick conversation keep their lifetime while sources are chosen.
import SwiftUI

struct PersonalSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var problem: String?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if let problem {
                    Text(problem).font(.callout).foregroundStyle(.orange)
                        .padding(.horizontal, 30).padding(.top, 12)
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
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Theme.bg)
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
