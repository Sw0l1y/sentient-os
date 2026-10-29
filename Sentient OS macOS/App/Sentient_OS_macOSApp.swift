//
//  Sentient_OS_macOSApp.swift
//  Sentient OS macOS
//
//  @main app shell. One main window hosts onboarding, then a sidebar of pages — Home,
//  Knowledge, Analysis, Finish Setup and each Settings pane; plus an always-present
//  MenuBarExtra (a standard menu). The app follows the system appearance. The live store is CycleStore (Ingestion/CycleStore.swift),
//  reached directly by the views — the app shell owns no store.
//

import SwiftUI
import AppKit

// Entry point is main.swift (the binary doubles as the root wake helper) — so no @main here.
struct SentientOSApp: App {
    @NSApplicationDelegateAdaptor(SentientAppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    private var mainWindowInitialSize: CGSize {
        guard !appState.hasCompletedOnboarding else { return CGSize(width: 1280, height: 840) }
        return OnboardingWindowLayout.initialSize(
            visibleSize: NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900))
    }

    /// Scene id for the primary home window, so the menu bar's "Open Sentient OS" can reopen/focus it.
    static let homeWindowID = "home"

    /// True when `window` is the single main scene's window. SwiftUI suffixes the scene id on the
    /// NSWindow identifier ("home-AppWindow-1"), so match the id exactly or as a prefix.
    static func isHomeWindow(_ window: NSWindow) -> Bool {
        guard let raw = window.identifier?.rawValue else { return false }
        return raw == homeWindowID || raw.hasPrefix(homeWindowID + "-")
    }

    // To add a headless self-test, restore the one-line hook here — see
    // Documentation - General - Self-Testing (Eval Harness).md (the `Self Tests - Temp/` folder is kept empty).
    init() {
        #if DEBUG
        SelfTest.runIfRequested()
        #endif
    }

    var body: some Scene {
        Window("Sentient OS", id: Self.homeWindowID) {
            RootView()
                .environment(appState)
                .task {
                    #if DEBUG
                    guard ProcessInfo.processInfo.environment["SENTIENT_SELFTEST"] == nil else { return }
                    #endif
                    await VaultCloud.pushIfDirty() // catch up a mirror sync deferred by an earlier quit/failure
                }
                .modifier(ComputerUseWindowGuard())
        }
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: mainWindowInitialSize.width, height: mainWindowInitialSize.height)
        // Launch presentation is decided after AppKit delivers the opening Apple event, when
        // login-item launches can be distinguished reliably. Explicit reopen uses our router.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    HomeWindowOpening.open(.settings, settingsPane: MainNavigation.shared.lastSettingsPane)
                }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(!appState.hasCompletedOnboarding || ComputerUseUpgrade.shared.isBlockingInterface)
            }
            SidebarCommands()
            CommandGroup(before: .sidebar) {
                Group {
                    Button("Home") { HomeWindowOpening.open(.home) }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("Knowledge") { HomeWindowOpening.open(.knowledge) }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("Analysis") { HomeWindowOpening.open(.analysis) }
                        .keyboardShortcut("3", modifiers: .command)
                }
                .disabled(!appState.hasCompletedOnboarding || ComputerUseUpgrade.shared.isBlockingInterface)
                Divider()
            }
            CommandGroup(replacing: .help) {
                Button("Sentient OS on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Sentient-OS-Labs/sentient-os")!)
                }
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Sentient-OS-Labs/sentient-os/issues")!)
                }
            }
            #if DEBUG
            CommandMenu("Debug") {
                Button("Developer Tools…") {
                    MainNavigation.shared.showDevTools = true
                    HomeWindowOpening.open()
                }
            }
            #endif
        }

        // PROACTIVE · EXECUTE — the dev window for PART 3 (the executor). Lists the real
        // ready-to-fire actions from the latest research+prepare run, each with a working FIRE
        // button. Opened from DEV TOOLS; a normal titled window so it's obviously closable.
        Window("Proactive · Execute", id: ProactiveExecuteView.windowID) {
            ProactiveExecuteView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .modifier(ComputerUseWindowGuard())
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 820)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        // Overnight Processing — the dev cockpit for the 3am scheduler (helper approval, launch-at-
        // login, manual arm). Opened from DEV TOOLS → "Overnight Processing…".
        Window("Overnight Processing", id: OvernightDevView.windowID) {
            OvernightDevView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .modifier(ComputerUseWindowGuard())
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 780)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarIcon().modifier(NotificationRouting())
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Dock reopen explicitly opens Home or resumes pending setup, even when another window is visible.
/// Ordinary activation remains separate, so silent launches and permission prompts keep their behavior.
final class SentientAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Notify.installRouting()
        // SMAppService owns launch-at-login. Prevent a second, state-restoration login launch
        // from reopening the main window independently of that preference.
        NSApp.disableRelaunchOnLogin()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ComputerUseUpgrade.shared.isBlockingInterface {
            NSApp.setActivationPolicy(.regular)
            ComputerUseUpgrade.shared.maybePresent()
        } else if LaunchPresentation.staysInMenuBar {
            DockPolicy().reevaluate()
        } else {
            HomeWindowOpening.presentCurrentPage()
        }
    }

    private var isResolvingTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isResolvingTermination else { return .terminateLater }
        isResolvingTermination = true
        let navigation = MainNavigation.shared
        navigation.confirmLeavingKnowledge { approved in
            // Always reply after AppKit receives terminateLater. Only the owned permission
            // probe is drained here; standard Quit never issues new task/analysis cancellation.
            Task { @MainActor in
                guard approved else {
                    SafeAppRelaunch.shared.cancelPendingRelaunch()
                    self.isResolvingTermination = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
                await NativePermissionCheck.shared.close()
                let mayQuit = SafeAppRelaunch.shared.approveTermination()
                self.isResolvingTermination = false
                sender.reply(toApplicationShouldTerminate: mayQuit)
            }
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        #if DEBUG
        Log("App reopen: visible windows=\(flag), suppressed launch=\(UpdateNotice.suppressHomeThisLaunch)")
        #endif
        HomeWindowOpening.open()
        return false
    }
}

/// The menu-bar label exists even on a windowless launch. Keep its scene action available for
/// notification clicks, including clicks received before SwiftUI finishes creating the scenes.
private struct NotificationRouting: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear {
            Notify.setKnowledgeSourcesHandler {
                HomeWindowOpening.open(.settings, settingsPane: .sources)
                NSApp.activate(ignoringOtherApps: true)
            }
            Notify.setLifetimeUpgradeHandler {
                HomeWindowOpening.open()
            }
        }
    }
}
