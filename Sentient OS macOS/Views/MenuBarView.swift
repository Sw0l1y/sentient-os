//
//  MenuBarView.swift
//  Sentient OS macOS
//
//  The menu bar extra, as a standard macOS menu (MenuBarExtra uses the `.menu` style): a disabled
//  status line first, then the window commands, then updates and the version, then Quit. Only
//  menu-compatible content lives here (Button, Toggle, Picker, Menu, Divider, Text); Text renders
//  as a disabled item. The label is the template brand mark, so it tints with the menu bar.
//

import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if isFinishingPersonalSetup {
            Text(CodexAuth.knowledgeBaseOnly ? "Personal setup is ready" : "Sidekick is ready")
        } else if appState.hasCompletedOnboarding {
            Text(appState.processing.statusLine)
        } else {
            Text("Finish setting up Sentient")
        }

        Divider()

        Button("Open Sentient OS") { openHome() }
        if isFinishingPersonalSetup {
            Button("Finish Personal Setup…") { openHome(.setup) }
                .disabled(ComputerUseUpgrade.shared.isBlockingInterface)
        } else if appState.hasCompletedOnboarding {
            Button("View Analysis Progress") { openHome(.analysis) }
                .disabled(ComputerUseUpgrade.shared.isBlockingInterface)
        }

        Divider()

        Button("Check for Updates…") {
            openHome()   // the check's sheet attaches to the home window, so bring it forward first
            appState.update.checkForUpdatesNow(from: .home)
        }
        .disabled(ComputerUseUpgrade.shared.isBlockingInterface || !UpdateController.appUpdatesEnabled)
        Text("Version \(UpdateController.currentVersionString)")

        Divider()

        Button("Quit Sentient OS") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var isFinishingPersonalSetup: Bool {
        appState.hasCompletedOnboarding && !appState.hasCompletedPersonalSetup && !appState.processing.initialComplete
    }

    /// Share explicit reopening with Dock clicks, including minimized Home and pending setup.
    @MainActor private func openHome(_ page: MainNavigation.Page = .home) {
        HomeWindowOpening.registerOpener {
            openWindow(id: SentientOSApp.homeWindowID)
        }
        HomeWindowOpening.open(page)
    }
}

/// The label is mounted even when no menu or regular scene has opened. Its SwiftUI environment
/// supplies home creation for setup completed after a suppressed, windowless update launch.
struct MenuBarIcon: View {
    @Environment(\.openWindow) private var openWindow

    /// Drawn once: an 18 pt template image, so AppKit tints it for a light or dark menu bar.
    private static let icon = BrandMark.templateImage(pointSize: 18)

    var body: some View {
        Image(nsImage: Self.icon)
            .accessibilityLabel("Sentient OS")
            .onAppear {
                HomeWindowOpening.registerOpener {
                    openWindow(id: SentientOSApp.homeWindowID)
                }
                ComputerUseUpgrade.shared.registerHomeOpener {
                    openWindow(id: SentientOSApp.homeWindowID)
                }
                if UserDefaults.standard.bool(forKey: AppState.onboardingKey),
                   PersonalSetupProgress.consumeRelaunchResume() {
                    MainNavigation.shared.show(.setup)
                    openWindow(id: SentientOSApp.homeWindowID)
                }
            }
    }
}
