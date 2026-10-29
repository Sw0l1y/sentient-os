//
// ConnectorConnectSheet.swift
// The Internet Accounts add-account sheet for a connector source. Hosted connections verify native
// linked-account metadata before saving selection. Direct accounts retain their browser OAuth,
// account IDs, knowledge toggle and cancellation lifecycle.
// Doc: Documentation - Settings.md
//

import SwiftUI
import AppKit

struct ConnectorConnectSheet: View {
    let source: ConnectorSource
    @Binding var connectors: [ConnectorCensus.DetectedConnector]
    let context: KnowledgeSourcesPicker.Context

    @Environment(\.dismiss) private var dismiss
    @State private var openedConnectorPage = false
    @State private var startedDirectConnection = false
    @State private var boundConnectorID: String?
    @State private var connectionPhase: DirectMCPConnectPhase?
    @State private var newConnectionID: UUID?
    @State private var connectionCompleted = false
    @State private var disconnecting = false
    @State private var verifyingHosted = false
    @State private var message: String?
    @State private var operation: Task<Void, Never>?
    @State private var confirmDisconnect = false
    @AppStorage private var hostedSelected: Bool
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    private let hostedBackend: ModelBackend

    init(source: ConnectorSource, connectors: Binding<[ConnectorCensus.DetectedConnector]>,
         context: KnowledgeSourcesPicker.Context = .settings) {
        self.source = source
        _connectors = connectors
        self.context = context
        _boundConnectorID = State(initialValue: source.connector?.id)
        _hostedSelected = AppStorage(wrappedValue: false,
            ConnectorRegistry.kbKey(source.connector?.slug ?? source.serviceSlug))
        switch source.connector?.origin {
        case .claude: hostedBackend = .claude
        case .chatgpt: hostedBackend = .chatgpt
        default: hostedBackend = ModelBackend.current
        }
    }

    private var connector: ConnectorCensus.DetectedConnector? {
        if let newConnectionID {
            let id = DirectMCPStore.connection(id: newConnectionID)?.detected.id
            return connectors.first { $0.id == id }
        }
        if let boundConnectorID { return connectors.first { $0.id == boundConnectorID } }
        return connectors.first { ConnectorRegistry.pack(for: $0)?.slug == source.serviceSlug }
    }

    private var direct: DirectMCPConnection? {
        if let newConnectionID { return DirectMCPStore.connection(id: newConnectionID) }
        return connector.flatMap { DirectMCPStore.connection($0.slug) }
    }

    private var usesDirect: Bool {
        (connector ?? source.connector).map { $0.origin == .direct } ?? (source.directProvider != nil)
    }

    private var selectionSlug: String { connector?.slug ?? source.serviceSlug }
    private var connecting: Bool { connectionPhase != nil }
    private var busy: Bool { connecting || disconnecting || verifyingHosted }
    private var connectTitle: String {
        switch connectionPhase {
        case .openingBrowser: "Opening Sign-In…"
        case .waitingForBrowser: "Waiting for Sign-In…"
        case .savingConnection: "Saving Connection…"
        case .checkingTools: "Preparing Tools…"
        case nil: connector == nil ? "Connect \(name)" : "Reconnect \(name)"
        }
    }
    private var name: String { ConnectorRegistry.pack(forSlug: source.serviceSlug)?.displayName ?? source.displayName }
    private var reader: String { hostedBackend == .claude ? "Claude" : "ChatGPT" }
    private var hostedCanRead: Bool { ConnectorRegistry.kbEligible(source.serviceSlug, backend: hostedBackend) }
    private var hostedConnected: Bool {
        if hostedCanRead { return hostedSelected }
        // Task-only apps have no reading preference. Keep their saved declaration without
        // inventing an analysis opt-in or treating a cached health result as a setup gate.
        guard let origin = ConnectorCensus.DetectedConnector.Origin(backend: hostedBackend) else { return false }
        return ConnectorCensus.cached(for: origin).contains { $0.slug == selectionSlug }
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectorSheetHeader(usesDirect ? "Connect \(name)" : name, message: headerLine) {
                ConnectorSheetLogo(asset: source.isCurated ? source.logoAsset : nil)
            }
            Form {
                if usesDirect {
                    directSections
                } else {
                    hostedSections
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            ConnectorSheetFooter {
                footerLeading
            } trailing: {
                footerTrailing
            }
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 360, idealHeight: 440)
        .presentationSizing(.form)
        .confirmationDialog("Disconnect \(name)?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive, action: disconnect)
        } message: {
            Text("Sentient removes this account’s access from this Mac.")
        }
        .onChange(of: connector?.id, initial: true) { _, id in
            // Once linked, never silently move this popup to another account of the service.
            if boundConnectorID == nil { boundConnectorID = id }
        }
        .onChange(of: backendRaw) { if !usesDirect { dismiss() } }
        .onDisappear(perform: cancelOperation)
    }

    // MARK: - Direct path (a Granola, Notion or other direct-MCP account)

    @ViewBuilder private var directSections: some View {
        Section {
            Label {
                Text("Your connection stays in this Mac’s Keychain")
            } icon: {
                Image(systemName: "lock").foregroundStyle(.secondary)
            }
            Label {
                Text("Your selected AI processes the content you request")
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(.secondary)
            }
        }
        if let direct {
            Section("Account") {
                StatusRow(direct.label, detail: direct.accountLabel ?? "Uses the account you approved in the browser.",
                          tone: .ok) {
                    if disconnecting {
                        HStack(spacing: Space.s) {
                            ProgressView().controlSize(.small)
                            Text("Disconnecting…").font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Disconnect…", role: .destructive) { confirmDisconnect = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(busy)
                            .accessibilityIdentifier("connector.disconnect")
                    }
                }
            }
        }
        if ConnectorRegistry.kbEligible(selectionSlug) {
            if context == .settings || direct != nil {
                ConnectorKnowledgeControl(slug: selectionSlug)
                    .disabled(busy)
            }
        } else if connector != nil {
            taskOnlySection
        }
        if message != nil || connectionPhase != nil || startedDirectConnection {
            Section("Status") {
                if let message {
                    StatusLabel(message, tone: .error)
                } else if connectionPhase != nil {
                    StatusRow(phaseLine, tone: .working)
                } else {
                    StatusLabel("Sign in in your browser, then press Done.", tone: .info)
                }
            }
        }
    }

    /// The phase half of the OAuth progress, as status copy.
    private var phaseLine: String {
        switch connectionPhase {
        case .openingBrowser: "Opening \(name)’s sign-in page…"
        case .waitingForBrowser: "Finish signing in in your browser."
        case .savingConnection: "Saving your sign-in…"
        case .checkingTools: "Signed in. Checking available tools. This can take a moment."
        case nil: ""
        }
    }

    // MARK: - Hosted path (a ChatGPT or Claude connector)

    @ViewBuilder private var hostedSections: some View {
        let lines = hostedFooterLines
        if lines.isEmpty {
            Section {
                StatusRow("\(reader) Connector", detail: connectionDetail, tone: connectionTone)
            }
        } else {
            Section {
                StatusRow("\(reader) Connector", detail: connectionDetail, tone: connectionTone)
            } footer: {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(lines, id: \.self) { Text($0) }
                }
            }
        }
        if hostedConnected {
            if !hostedCanRead && !hostedSelected { taskOnlySection }
        }
    }

    private var connectionDetail: String {
        if verifyingHosted { return "Checking connection…" }
        if hostedSelected && !hostedCanRead { return "Unavailable with your current AI" }
        if message != nil { return "Not verified" }
        if hostedConnected { return "Connected" }
        if openedConnectorPage { return "Waiting for you in \(reader)" }
        return "Not connected"
    }

    private var connectionTone: StatusTone {
        if verifyingHosted { return .working }
        if hostedSelected && !hostedCanRead { return .warning }
        if message != nil { return .warning }
        if hostedConnected { return .ok }
        if openedConnectorPage { return .info }
        return .off
    }

    private var hostedFooterLines: [String] {
        var lines: [String] = []
        if hostedSelected && !hostedCanRead {
            lines.append("This selected source is unavailable with your current AI. Choose a supported connection or stop reading it here.")
        }
        if let message { lines.append(message) }
        if !hostedConnected && hostedBackend == .claude
            && ["outlook-mail", "outlook-calendar"].contains(source.serviceSlug) {
            lines.append("Uses Microsoft 365 with a work or school account.")
        }
        return lines
    }

    /// Union of the two places the hosted sheet offers to stop reading.
    private var showsStopReading: Bool {
        (hostedSelected && !hostedCanRead) || (hostedConnected && hostedCanRead)
    }

    private var hostedInstructions: String {
        if openedConnectorPage {
            return "Connect \(name) to your \(reader) account, and then come back to Sentient."
        }
        return hostedCanRead
            ? "Sentient reads \(name) through your \(reader) connector. Enable it and sign in there, then press Done."
            : "Enable \(name) in your \(reader) connectors and sign in there, then press Done to use it for tasks."
    }

    // MARK: - Shared pieces

    private var headerLine: String {
        if usesDirect { return "Sign in to \(name) in your browser, and then come back to Sentient." }
        if !hostedConnected { return hostedInstructions }
        return hostedCanRead
            ? "Sentient reads \(name) through your \(reader) connector."
            : "Available for tasks through your \(reader) connector."
    }

    private var taskOnlySection: some View {
        Section {
            LabeledContent("Knowledge Base") {
                StatusLabel("Tasks only", tone: .off)
            }
        } footer: {
            Text("Available for tasks. This app does not support knowledge-base analysis.")
        }
    }

    @ViewBuilder private var footerLeading: some View {
        if !usesDirect && showsStopReading {
            Button("Stop Reading \(name)", action: stopHostedReading)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("connector.stopReading")
        }
    }

    @ViewBuilder private var footerTrailing: some View {
        Button("Cancel", role: .cancel) { dismiss() }
            .keyboardShortcut(.cancelAction)
            .disabled(disconnecting)
            .accessibilityIdentifier("connector.cancel")
        if usesDirect {
            ConnectorActionButton(title: connectTitle, kind: startedDirectConnection ? .again : .connect,
                                  isLoading: connecting, action: connect)
                .disabled(busy)
            if startedDirectConnection {
                ConnectorActionButton(title: "Done", kind: .done, action: done)
                    .disabled(busy)
            }
        } else {
            ConnectorActionButton(title: hostedConnected ? "Open connector settings" : "Connect \(name)",
                                  kind: openedConnectorPage ? .again : .connect, action: connect)
                .disabled(hostedBackend == .custom || (hostedSelected && !hostedCanRead))
            if openedConnectorPage {
                ConnectorActionButton(title: verifyingHosted ? "Checking Connection…" : "Done", kind: .done,
                                      isLoading: verifyingHosted, action: done)
                    .disabled(busy)
            }
        }
    }

    private func connect() {
        guard !busy else { return }
        message = nil
        guard usesDirect else {
            openConnectorPage()
            return
        }
        guard let provider = direct?.provider ?? source.directProvider else { return }
        startedDirectConnection = true
        let existing = direct
        let id = existing?.id ?? newConnectionID ?? UUID()
        let label = existing?.label ?? nextAccountLabel(for: provider)
        if existing == nil { newConnectionID = id }
        connectionPhase = .openingBrowser
        operation = Task {
            defer { connectionPhase = nil }
            do {
                _ = try await DirectMCPConnections.shared.connect(provider: provider, label: label, replacing: id,
                    onProgress: { phase in
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            connectionPhase = phase
                        }
                    })
                guard !Task.isCancelled else { return }
                connectionCompleted = true
                if let connection = DirectMCPStore.connection(id: id) {
                    // Carry the catalog choice onto this account's stable source key.
                    let defaults = UserDefaults.standard
                    if let enabled = defaults.object(forKey: ConnectorRegistry.kbKey(source.serviceSlug)) as? Bool {
                        ConnectorRegistry.setKBEnabled(connection.slug, enabled)
                        defaults.removeObject(forKey: ConnectorRegistry.kbKey(source.serviceSlug))
                    }
                    boundConnectorID = connection.detected.id
                    connectors.removeAll { $0.id == connection.detected.id }
                    connectors.append(connection.detected)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                message = (error as? DirectMCPError)?.errorDescription
                    ?? "Sign-in couldn’t be completed. Please try again."
            }
        }
    }

    private func openConnectorPage() {
        guard ModelBackend.current == hostedBackend, hostedBackend != .custom else { dismiss(); return }
        if NSWorkspace.shared.open(ConnectorLinks.page(for: source.serviceSlug, backend: hostedBackend)) {
            openedConnectorPage = true
            HostedConnectorSetup.settingsOpened(slug: source.serviceSlug, backend: hostedBackend)
        }
    }

    private func nextAccountLabel(for provider: DirectMCPProvider) -> String {
        let accounts = DirectMCPStore.connections().filter { $0.providerSlug == provider.slug }
        var label = "Account"
        var number = 2
        while accounts.contains(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) {
            label = "Account \(number)"
            number += 1
        }
        return label
    }

    private func cancelOperation() {
        let pending = operation
        pending?.cancel()
        guard let newConnectionID, !connectionCompleted else { return }
        // Wait for OAuth cancellation to settle before removing this sheet's unfinished account.
        // Reconnects retain their existing grant through DirectMCPConnections' recovery path.
        Task {
            await pending?.value
            _ = try? await DirectMCPConnections.shared.disconnect(newConnectionID)
        }
    }

    private func done() {
        guard !busy else { return }
        if !usesDirect {
            verifyingHosted = true; message = nil
            operation = Task { @MainActor in
                let ready = await HostedConnectorSetup.verifyAndConfirm(slug: source.serviceSlug, backend: hostedBackend,
                    reconnected: openedConnectorPage)
                guard !Task.isCancelled else { return }
                verifyingHosted = false; operation = nil
                guard ready else {
                    message = "This connection is not verified yet. Finish signing in, then try Done again. No source was added."
                    return
                }
                connectors = ConnectorRegistry.detectedForCurrentBackend()
                dismiss()
            }
            return
        }
        if ConnectorRegistry.kbEligible(selectionSlug),
           UserDefaults.standard.object(forKey: ConnectorRegistry.kbKey(selectionSlug)) == nil {
            ConnectorRegistry.setKBEnabled(selectionSlug, true)
        }
        dismiss()
    }

    private func stopHostedReading() {
        guard ModelBackend.current == hostedBackend else { dismiss(); return }
        operation?.cancel()
        HostedConnectorSetup.stopReading(slug: source.serviceSlug, backend: hostedBackend)
        dismiss()
    }

    private func disconnect() {
        guard let direct else { return }
        disconnecting = true
        message = nil
        operation = Task {
            do {
                _ = try await DirectMCPConnections.shared.disconnect(direct.id)
                dismiss()
            } catch {
                message = "Local access couldn’t be fully removed. Please try again."
            }
            disconnecting = false
        }
    }
}

/// The existing opt-in, on its production key. Discovery never selects a source for the user.
private struct ConnectorKnowledgeControl: View {
    @AppStorage private var enabled: Bool

    init(slug: String) {
        _enabled = AppStorage(wrappedValue: false, ConnectorRegistry.kbKey(slug))
    }

    var body: some View {
        Section {
            Toggle("Use for Knowledge Base", isOn: $enabled)
                .accessibilityIdentifier("connector.knowledgeToggle")
        } footer: {
            Text("Include this app in your analysis and nightly updates.")
        }
    }
}

#Preview("Connect Google Drive · not connected") {
    ConnectorConnectSheet(source: ConnectorSource.catalog(with: [])[0], connectors: .constant([]))
}

#Preview("Onboarding · connect Granola") {
    if let source = ConnectorSource.catalog(with: []).first(where: { $0.serviceSlug == "granola" }) {
        ConnectorConnectSheet(source: source, connectors: .constant([]), context: .onboarding)
    }
}

#Preview("Connect Asana · no logo") {
    let connector = ConnectorCensus.DetectedConnector(
        slug: "asana", displayName: "Asana", origin: .claude,
        serverURL: nil, catalogID: nil, iconPath: nil, healthy: true, lastSeen: .now)
    if let source = ConnectorSource.catalog(with: [connector]).first(where: { $0.id == connector.id }) {
        ConnectorConnectSheet(source: source, connectors: .constant([connector]))
    }
}
