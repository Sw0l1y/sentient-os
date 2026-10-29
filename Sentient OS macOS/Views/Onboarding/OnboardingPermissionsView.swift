// Overnight access is requested only after the user chooses overnight analysis. Source
// access belongs to the source picker; voice and notifications remain independent opt-ins.
// The rows are the same StatusRows Permissions & Health uses, placed in the caller's Form section.
import SwiftUI
import AppKit

struct OvernightSetupRequirements: View {
    let onReadinessChange: (Bool) -> Void
    @State private var wakeSetup = OvernightWakeSetup()
    @State private var loginOn = LoginItem.cachedIsEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    private var ready: Bool { wakeSetup.ready && loginOn }

    /// Form rows only: the one caller (AnalysisTimingSheet) wraps them in its
    /// `Section("For Overnight Analysis")`, so a titled group of their own would repeat that heading
    /// inside a Form row (SPEC-D3 1.5 and open issue 8, resolved at integration).
    var body: some View {
        OvernightWakeRow(setup: wakeSetup)
        StatusRow("Launch at Login",
                  detail: loginOn ? "On" : (loginNeedsApproval ? "Approval needed" : "Off"),
                  tone: loginOn ? .ok : .warning,
                  info: "Keeps Sentient available in your menu bar after you log in.") {
            if !loginOn {
                Button(loginNeedsApproval ? "Approve…" : "Turn On", action: fixLogin)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        // On this always-present row, not on a container: inside a Form, a modifier on a Group
        // or Section is applied to each of its rows, which would refresh once per row.
        .onAppear { refresh(); onReadinessChange(ready) }
        .onChange(of: ready) { _, value in onReadinessChange(value) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        if !ready {
            Text("You can choose Now to analyze without overnight setup.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fixLogin() {
        LoginItem.enableOrRequestApproval()
        refresh()
        if LoginItem.needsApproval { PermissionGuide.shared.guide(.loginItems, dragging: nil) }
    }

    private func refresh() {
        loginOn = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
        Task { await wakeSetup.refresh() }
    }
}
