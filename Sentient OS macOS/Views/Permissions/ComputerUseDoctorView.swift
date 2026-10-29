// The computer-use check window (laid out like Disk Utility's First Aid: a tile header with the
// outcome, a list of steps with live spinners, the test area, a "Show Details" log, Done and
// Check Again), its report-review sheet, and the Health row that starts it.

import AppKit
import SwiftUI

struct ComputerUseDoctorView: View {
    @Bindable var doctor: ComputerUseDoctor
    @State private var reviewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header
            steps
            if let controls = doctor.controls {
                GroupBox("Test Area") {
                    TestControlsHost(controls: controls)
                        .frame(height: 100)
                        .accessibilityIdentifier("computerUse.checkControls")
                }
            }
            DisclosureGroup("Show Details") {
                ScrollView([.vertical, .horizontal]) {
                    Text(reportJSON ?? "Report unavailable")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(reportJSON == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s)
                }
                .frame(maxHeight: 140)
            }
            bottomBar
        }
        .padding(Space.xl)
        .frame(width: 540, height: 620)
        .sheet(isPresented: $reviewing) { reportPreview }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconTile(.gateDoctor, size: 40)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(doctor.report?.title ?? "Computer-Use Check")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(doctor.report?.explanation ?? "Test the tools Sidekick uses across your computer.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Steps (and the permissions to fix)

    /// The step list takes the window's free height and scrolls when it overflows, so the test
    /// area and the bottom bar always stay in view.
    private var steps: some View {
        Form {
            Section("Checks") {
                if let steps = doctor.report?.steps, !steps.isEmpty {
                    ForEach(steps) { step in
                        StatusRow(step.check.title, detail: label(step.status), tone: tone(step.status))
                    }
                } else {
                    Text("No check has run yet.")
                        .foregroundStyle(.secondary)
                }
            }
            if doctor.report?.outcome == .permissionsNeeded {
                permissionsSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .frame(maxHeight: .infinity)
    }

    private var permissionsSection: some View {
        Section {
            StatusRow("Screen Recording", tile: .screenRecording, detail: screenDetail,
                      tone: screenDetail == "Granted" ? .ok : .warning,
                      fixTitle: "Open Settings") { Permissions.openScreenRecordingSettings() }
            StatusRow("Accessibility", tile: .accessibility, tone: .warning,
                      fixTitle: "Open Settings") { Permissions.openAccessibilitySettings() }
            StatusRow("Automation", tile: .automation, detail: automationDetail,
                      tone: automationState == "granted" ? .ok : .warning,
                      fixTitle: automationState == "notAsked" ? "Allow…" : "Open Settings") {
                if doctor.report?.permissions["automation"] == "notAsked" { ComputerUseGate.shared.requestAutomation() }
                else { Permissions.openAutomationSettings() }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("In Automation, expand Sentient OS and allow ChatGPT/Codex Computer Use.")
        }
    }

    private var automationState: String? { doctor.report?.permissions["automation"] }

    private var automationDetail: String? {
        switch automationState {
        case "granted": "Granted"
        case "denied": "Not allowed"
        case "notAsked": "Not requested"
        case nil: nil
        default: "Not checked"
        }
    }

    private var screenDetail: String? {
        switch doctor.report?.permissions["sentientScreenRecording"] {
        case "granted": "Granted"
        case "denied": "Not allowed"
        default: nil
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: Space.m) {
            if doctor.isRunning {
                Text("Only this test window is used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Stop Check") { doctor.cancel() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Review Report…") { reviewing = true }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button("Done") { doctor.close() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Check Again") { doctor.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(doctor.uploading)
            }
        }
    }

    // MARK: Review sheet

    private var reportJSON: String? {
        doctor.report.flatMap { try? $0.encoded() }.map { String(decoding: $0, as: UTF8.self) }
    }

    private var reportPreview: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Review Your Diagnostic Report")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Includes versions, permission status, test results and recent technical error categories and codes. Tool errors may have recovered during the task. No screenshots, messages, account details or document contents. Sending shares this report with the Sentient team, stored in Supabase.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GroupBox {
                ScrollView([.vertical, .horizontal]) {
                    Text(reportJSON ?? "Report unavailable")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(reportJSON == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.xs)
                }
            }
            .frame(maxHeight: .infinity)
            if let message = doctor.uploadMessage {
                StatusLabel(message, tone: .info)
            }
            HStack(spacing: Space.m) {
                Button("Done") { reviewing = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button("Save a Copy…") { doctor.saveReport() }
                    .buttonStyle(.bordered)
                Button(doctor.uploading ? "Sending…" : "Send Report") { doctor.sendReport() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(doctor.uploading || doctor.report == nil)
            }
        }
        .padding(Space.xl)
        .frame(width: 580, height: 580)
    }

    // MARK: Step status

    private func tone(_ state: ComputerUseCheckReport.Status) -> StatusTone {
        switch state {
        case .running: .working
        case .passed: .ok
        case .needsAttention, .interrupted: .warning
        case .skipped: .off
        }
    }

    private func label(_ state: ComputerUseCheckReport.Status) -> String {
        switch state {
        case .running: "Checking…"
        case .passed: "Passed"
        case .needsAttention: "Needs a look"
        case .interrupted: "Interrupted"
        case .skipped: "Not tested"
        }
    }
}

private struct TestControlsHost: NSViewRepresentable {
    let controls: ComputerUseTestControls
    func makeNSView(context: Context) -> NSView { controls.view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Permissions & Health › Computer Use Check: one status row with its trailing action.
struct ComputerUseCheckRow: View {
    @State private var doctor = ComputerUseDoctor.shared

    var body: some View {
        Section {
            StatusRow("Test & Repair Computer Use", tile: .diagnostics, detail: detail, tone: tone) {
                Button(doctor.isRunning ? "View Check" : "Test & Repair…") {
                    if doctor.isRunning { doctor.show() } else { doctor.start() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } header: {
            Text("Computer Use Check")
        } footer: {
            Text(footer)
        }
    }

    private enum CheckState { case running, passed(Date), other(String), none }

    /// A report counts only when it finished on this exact build.
    private var state: CheckState {
        if doctor.isRunning { return .running }
        guard let report = doctor.report, let ended = report.finishedAt,
              report.environment.binaryID == BuildIdentity.identifier else { return .none }
        if report.outcome == .passed || report.outcome == .repaired { return .passed(ended) }
        return .other(report.explanation)
    }

    private var tone: StatusTone {
        switch state {
        case .running: .working
        case .passed: .ok
        case .other: .warning
        case .none: .off
        }
    }

    private var detail: String? {
        switch state {
        case .running: "Checking…"
        case .passed(let ended): "Last passed " + ended.formatted(date: .abbreviated, time: .shortened)
        case .other: "Needs a look"
        case .none: "Not checked"
        }
    }

    private var footer: String {
        switch state {
        case .passed: "Permissions are checked separately."
        case .other(let explanation): explanation
        case .running, .none: "Test reading, screenshots, clicks and text entry in a small Sentient window."
        }
    }
}
