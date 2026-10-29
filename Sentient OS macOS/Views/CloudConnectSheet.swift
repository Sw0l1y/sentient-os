//
//  CloudConnectSheet.swift
//  Sentient OS macOS
//
//  The Gmail / Google Calendar connect popup — ONE sheet for both cloud sources (they are exact
//  twins: same connector page flow and storage shape), engine-aware: the
//  ChatGPT backend links on OpenAI's hosted connector page, the Claude backend on claude.ai's
//  connector directory (GmailConnect/CalendarConnect.connectorURL pick; the copy follows). Flow:
//    Connect …  → opens the engine's connector page (the user links Google there).
//    Done       → verifies linked-account/read-tool metadata, then saves the selection.
//    Cancel     → closes without saving.
//  Already connected → "Stop Reading …" clears selection, not the provider connection.
//
//  Presented from Settings → Knowledge Sources, the home's Analysis popover, onboarding's ready
//  screen, and Dev Tools. See GmailConnect / CalendarConnect for the codex side.
//

import SwiftUI
import AppKit

struct CloudConnectSheet: View {
    enum Service {
        case gmail, calendar

        var logoAsset: String { self == .gmail ? "GmailMark" : "GoogleCalendarMark" }
        var title: String { self == .gmail ? "Gmail" : "Google Calendar" }
        var connectTitle: String { self == .gmail ? "Connect Gmail" : "Connect Calendar" }
        var stopLine: String { self == .gmail ? "Stop Reading Gmail" : "Stop Reading Google Calendar" }
        var connectorURL: URL { self == .gmail ? GmailConnect.connectorURL : CalendarConnect.connectorURL }
        var slug: String { self == .gmail ? "gmail" : "google-calendar" }
        var connectedKey: String { self == .gmail ? "dbg.gmail.connected" : "dbg.calendar.connected" }
        var selectedKey: String { self == .gmail ? "dbg.run.gmail" : "dbg.run.calendar" }
        var analyticsName: String { self == .gmail ? "gmail" : "calendar" }
    }

    private let service: Service
    private let backend: ModelBackend
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var connected: Bool
    @AppStorage private var selected: Bool
    @AppStorage(ModelBackend.key) private var backendRaw = ""

    @State private var openedConnectorPage = false
    @State private var checkingConnection = false
    @State private var connectionProblem: String?
    @State private var verification: Task<Void, Never>?

    init(_ service: Service) {
        self.service = service
        self.backend = .current
        let connection = AppStorage(wrappedValue: false, service.connectedKey)
        let selection = AppStorage(wrappedValue: false, service.selectedKey)
        _connected = connection
        _selected = selection
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectorSheetHeader(service.title, message: headerLine) {
                ConnectorSheetLogo(asset: service.logoAsset)
            }
            Form {
                let lines = statusFooterLines
                if lines.isEmpty {
                    Section {
                        StatusRow("\(readerName) Connector", detail: statusDetail, tone: statusTone)
                    }
                } else {
                    Section {
                        StatusRow("\(readerName) Connector", detail: statusDetail, tone: statusTone)
                    } footer: {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(lines, id: \.self) { Text($0) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            ConnectorSheetFooter {
                // Reading remains an explicit opt-in.
                if selected {
                    Button(service.stopLine, action: stopReading)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("connector.stopReading")
                }
            } trailing: {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("connector.cancel")
                ConnectorActionButton(title: selected ? "Open connector settings" : service.connectTitle,
                                      kind: openedConnectorPage ? .again : .connect, action: openConnectorPage)
                    .disabled(backend == .custom || CodexAuth.connectorsLocked)
                if openedConnectorPage {
                    ConnectorActionButton(title: checkingConnection ? "Checking Connection…" : "Done", kind: .done,
                                          isLoading: checkingConnection, action: done)
                        .disabled(checkingConnection)
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 320, idealHeight: 380)
        .presentationSizing(.form)
        .onChange(of: backendRaw) { verification?.cancel(); dismiss() }
        .onDisappear { verification?.cancel() }
    }

    // MARK: - What the sheet says

    private var readerName: String { backend == .claude ? "Claude" : "ChatGPT" }

    private var unavailable: Bool { selected && (backend == .custom || CodexAuth.connectorsLocked) }

    private var headerLine: String {
        if selected { return "Sentient reads \(service.title) through your \(readerName) connector." }
        return openedConnectorPage
            ? "Connect \(service.title) to your \(readerName) account, and then come back to Sentient."
            : "Sentient reads through your \(readerName) connector. Enable it and sign in on that page, then press Done."
    }

    private var statusDetail: String {
        if checkingConnection { return "Checking connection…" }
        if unavailable { return "Unavailable with your current AI" }
        if connectionProblem != nil { return "Not verified" }
        if selected { return "Connected" }
        if openedConnectorPage { return "Waiting for you in \(readerName)" }
        return "Not connected"
    }

    private var statusTone: StatusTone {
        if checkingConnection { return .working }
        if unavailable { return .warning }
        if connectionProblem != nil { return .warning }
        if selected { return .ok }
        if openedConnectorPage { return .info }
        return .off
    }

    private var statusFooterLines: [String] {
        var lines: [String] = []
        if unavailable {
            lines.append("This selected source is unavailable with your current AI. You can stop reading it here or choose a supported connection.")
        }
        if let connectionProblem { lines.append(connectionProblem) }
        return lines
    }

    // MARK: - Connect, Stop Reading and Done

    private func openConnectorPage() {
        guard !checkingConnection else { return }
        guard ModelBackend.current == backend, backend != .custom else { dismiss(); return }
        if NSWorkspace.shared.open(service.connectorURL) {
            openedConnectorPage = true
            HostedConnectorSetup.settingsOpened(slug: service.slug, backend: backend)
        }
    }

    // MARK: - Done: verify native linked-account metadata before selecting

    private func stopReading() {
        guard ModelBackend.current == backend else { dismiss(); return }
        verification?.cancel()
        HostedConnectorSetup.stopReading(slug: service.slug, backend: backend)
        dismiss()
    }

    private func done() {
        guard !checkingConnection else { return }
        checkingConnection = true; connectionProblem = nil
        let firstConnection = !connected
        verification = Task { @MainActor in
            let ready = await HostedConnectorSetup.verifyAndConfirm(slug: service.slug, backend: backend,
                reconnected: openedConnectorPage)
            guard !Task.isCancelled else { return }
            checkingConnection = false; verification = nil
            guard ready else {
                connectionProblem = "This connection is not verified yet. Finish signing in to \(service.title), then try Done again. No source was added."
                return
            }
            if firstConnection { Analytics.signal("Source.connected", parameters: ["source": service.analyticsName]) }
            dismiss()
        }
    }

}

#Preview("Connect Gmail") {
    CloudConnectSheet(.gmail)
}

#Preview("Connect Google Calendar") {
    CloudConnectSheet(.calendar)
}
