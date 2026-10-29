// Double Tap's first-use setup: Sentient's own Accessibility and Screen Recording grants.
// intercept() stops a draft before capture; finishSetup() closes setup once both grants are enabled.
// A Setup Assistant page that reuses the computer-use gate layout and grant rows, without
// depending on its helper or voice setup.
// Doc: Documentation - Permission Gate & Guide.md

import AppKit
import SwiftUI

@MainActor @Observable
final class DoubleTapPermissionGate {
    static let shared = DoubleTapPermissionGate()
    private init() {}

    private(set) var accessibility = false
    private(set) var screen = false
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    var allGranted: Bool { accessibility && screen }

    /// Setup takes keyboard focus. Never hold or replay the original draft after it closes:
    /// the user must focus their reply field and double tap again.
    func intercept() -> Bool {
        refresh()
        if allGranted {
            // A completed setup left behind another app must not steal focus on the next tap.
            // A tap IN the setup window is consumed so the draft cannot land in Sentient.
            guard window?.isKeyWindow != true else { return true }
            window?.close()
            return false
        }
        Log("DoubleTapPermissionGate: setup needed (accessibility=\(accessibility), screen=\(screen))")
        present()
        return true
    }

    func refresh() {
        accessibility = Permissions.hasAccessibility()
        // Use the same effective permission as ScreenCapture. A stored bundle-ID match alone
        // can falsely report green after the app's signing identity changes.
        screen = Permissions.hasScreenRecording()
    }

    func finishSetup() {
        refresh()
        guard allGranted else { return }
        window?.close()
    }

    private func present() {
        if window == nil {
            let hosting = NSHostingController(rootView: DoubleTapPermissionGateView(gate: self))
            let setupWindow = NSWindow(contentViewController: hosting)
            setupWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            setupWindow.title = "Set Up Double Tap"
            GateWindowStyle.apply(to: setupWindow)   // system window background and appearance
            setupWindow.isReleasedWhenClosed = false
            setupWindow.level = .floating
            setupWindow.isMovableByWindowBackground = true
            window = setupWindow
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: setupWindow, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowClosed() }
            }
            setupWindow.center()
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate()
    }

    private func windowClosed() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        // Detach the view so its permission polling stops after dismissal.
        window?.contentViewController = nil
        window = nil
        PermissionGuide.shared.close()
    }
}

private struct DoubleTapPermissionGateView: View {
    let gate: DoubleTapPermissionGate

    var body: some View {
        PermissionSetupView(tile: .setupDoubleTap, title: "Set Up Double Tap",
                            message: "Allow Sentient OS to read the conversation on your screen and paste a draft for you to review.",
                            continueTitle: gate.allGranted ? "Done" : "Grant Permissions to Continue",
                            canContinue: gate.allGranted, primaryID: "doubleTapGate.done",
                            onContinue: gate.finishSetup) {
            GateForm {
                SentientAppPermissionRows(accessibility: gate.accessibility, screen: gate.screen,
                                          accessibilityTitle: "Accessibility",
                                          accessibilityTip: "Lets Double Tap find the reply field and paste your draft. You review and send it.",
                                          footer: "When setup is complete, focus your reply field and double tap again.")
            }
        }
        .frame(width: PageMetrics.setupPage, height: 560)
        .task {
            while !Task.isCancelled {
                gate.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            gate.refresh()
        }
    }
}

#Preview("Double Tap setup") {
    DoubleTapPermissionGateView(gate: .shared)
}
