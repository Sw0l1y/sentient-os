//
// KnowledgeSourcesPicker.swift
// Shared source sections and connection flows for Settings and onboarding, laid out like
// System Settings › Internet Accounts: one grouped Form, one Section per kind of source, each
// source a row with its real icon, its state and one control. Owns folder/chat selection, saved
// connector choices, and sheets. Reports the live selection count to personal setup. Permission
// requests follow an explicit protected-source Set Up action.
// Doc: Settings/Documentation - Settings.md; Onboarding/Documentation - Onboarding.md
//

import SwiftUI
import Combine
import AppKit

struct KnowledgeSourcesPicker: View {
    enum Context { case settings, onboarding }
    /// Kept for callers that name it. It shadows `SwiftUI.Section` inside this struct, so the
    /// body spells the SwiftUI type in full.
    enum Section { case connectors }

    var context: Context = .settings
    var onSelectionCountChange: (Int) -> Void = { _ in }
    /// Extra Sections a host places before and after the picker's own, inside the same Form.
    private var leadingHost: AnyView? = nil
    private var trailingHost: AnyView? = nil

    init(context: Context = .settings, onSelectionCountChange: @escaping (Int) -> Void = { _ in }) {
        self.context = context
        self.onSelectionCountChange = onSelectionCountChange
    }

    /// Hosts Sections above the picker's own, inside its Form (a whisper, an introduction).
    func leadingSections<V: View>(@ViewBuilder _ content: () -> V) -> KnowledgeSourcesPicker {
        var copy = self
        copy.leadingHost = AnyView(content())
        return copy
    }

    /// Hosts Sections below the picker's own, inside its Form.
    func trailingSections<V: View>(@ViewBuilder _ content: () -> V) -> KnowledgeSourcesPicker {
        var copy = self
        copy.trailingHost = AnyView(content())
        return copy
    }

    // The shared selection keys (defaults must match SourceSelection).
    @AppStorage("dbg.run.downloads") private var runDownloads = false
    @AppStorage("dbg.run.desktop")   private var runDesktop = false
    @AppStorage("dbg.run.documents") private var runDocuments = false
    @AppStorage("dbg.run.notes")     private var runNotes = false
    @AppStorage(SiYuanSource.enabledKey) private var runSiYuan = false
    @AppStorage("dbg.run.whatsapp")  private var runWhatsApp = false
    @AppStorage("dbg.whatsapp.chats") private var whatsappCSV = ""
    @AppStorage("dbg.run.imessage")  private var runIMessage = false
    @AppStorage("dbg.imessage.chats") private var imessageCSV = ""
    @AppStorage("dbg.run.gmail")       private var runGmail = false
    @AppStorage("dbg.run.calendar")       private var runCalendar = false
    @AppStorage(CustomRoots.key) private var customRootsRaw = ""
    @AppStorage(AppleCalendarSource.issueKey) private var calendarReadIssue = ""
    // Re-renders the connector catalog and availability when the engine changes,
    // and keys the census reload below.
    @AppStorage(ModelBackend.key) private var backendRaw = ""

    @State private var protectedSource: ProtectedLocalSource?
    @AppStorage(SourceSelection.pendingProtectedSourceKey) private var pendingProtectedSource = ""
    @State private var connectors: [ConnectorCensus.DetectedConnector] = []
    @State private var selectedConnector: ConnectorSource?
    @State private var showWhatsAppPicker = false
    @State private var showIMessagePicker = false
    @State private var showGmailConnect = false
    @State private var showCalendarConnect = false
    @State private var showAppleMailPicker = false
    @AppStorage(AppleMailSelection.key) private var appleMailAccounts = ""
    @State private var showAppleCalendarConnect = false

    private var customRoots: [URL] { CustomRoots.decode(customRootsRaw) }
    private var whatsappChats: Set<String> { Set(whatsappCSV.split(separator: ",").map(String.init)) }
    private var imessageChats: Set<String> { Set(imessageCSV.split(separator: ",").map(String.init)) }
    private var connectorSources: [ConnectorSource] {
        let sources = ConnectorSource.catalog(with: connectors)
        return context == .onboarding ? sources.filter(\.isCurated) : sources
    }

    // Connector opt-ins use dynamic mcp.<slug>.kb keys, so the fixed @AppStorage properties
    // above cannot observe every selection. Recount on preferences changes, including edits
    // in a connection sheet or another window, and report the live count to onboarding.
    @State private var selectionCount = SourceSelection.selectionCount

    /// One Form owns every sheet, task and observer below: a modifier on a Section inside a Form
    /// would be applied to each of its rows.
    var body: some View {
        PaneForm(maxWidth: context == .settings ? PageMetrics.readingColumn : PageMetrics.setupPage) {
            if let leadingHost { leadingHost }

            SwiftUI.Section {
                gmailRow
                ForEach(connectorSources.filter { $0.serviceSlug == "outlook-mail" }) { source in
                    connectorPill(source, featured: true)
                }
                appleMailRow
                googleCalendarRow
                ForEach(connectorSources.filter { $0.serviceSlug == "outlook-calendar" }) { source in
                    connectorPill(source, featured: true)
                }
                appleCalendarRow
            } header: {
                HStack {
                    Text("Email & Calendar")
                    Spacer()
                    Label("Recommended", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Label(PrivacyCopy.emailSources, systemImage: "lock.fill")
            }

            SwiftUI.Section {
                if SourceSelection.shouldShowWhatsApp { whatsAppRow }
                iMessageRow
            } header: {
                Text("Your Conversations")
            } footer: {
                Label(PrivacyCopy.conversationSources, systemImage: "lock.fill")
            }

            SwiftUI.Section("More of Your World") {
                ForEach(connectorSources.filter {
                    !["outlook-mail", "outlook-calendar"].contains($0.serviceSlug)
                }) { source in
                    connectorPill(source)
                }
                KnowledgeSourcePill(label: "Apple Notes",
                                    detail: protectedDetail(.notes, selected: runNotes, ready: nil),
                                    asset: "AppleNotesMark", selected: runNotes,
                                    action: {
                                        if runNotes { runNotes = false } else { connectProtectedSource(.notes) }
                                    },
                                    toggles: true,
                                    needsAttention: protectedNeedsAttention(.notes, selected: runNotes))
                if SiYuanSource.isInstalled || runSiYuan {
                    KnowledgeSourcePill(label: "SiYuan",
                                        detail: runSiYuan && !SiYuanSource.isInstalled ? "Workspace unavailable" : nil,
                                        asset: "SiYuanMark", selected: runSiYuan,
                                        action: { runSiYuan.toggle() },
                                        toggles: true)
                }
                // Connect More Apps is hidden for this release until discovery can
                // reliably notice new hosted connections. Curated setup remains available.
            }

            SwiftUI.Section("Folders on This Mac") {
                folderSwitch("Desktop", isOn: runDesktop) { runDesktop.toggle() }
                folderSwitch("Downloads", isOn: runDownloads) { runDownloads.toggle() }
                folderSwitch("Documents", isOn: runDocuments) { runDocuments.toggle() }
                ForEach(customRoots, id: \.self) { url in
                    KnowledgeSourcePill(label: url.lastPathComponent, selected: true,
                                        trailingSymbol: "xmark.circle.fill",
                                        action: { CustomRoots.remove(url) },
                                        folderPath: url.path)
                        .help("Remove \(url.lastPathComponent) from analysis.")
                }
                Button("Add Folder…", systemImage: "folder.badge.plus", action: chooseFolder)
                    .buttonStyle(.link)
            }

            if context == .settings {
                SwiftUI.Section {} footer: {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Choose at least three sources to set up your personal context.")
                        Label(PrivacyCopy.trustRibbon, systemImage: "lock.shield")
                    }
                }
            }

            if let trailingHost { trailingHost }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)) { _ in
                selectionCount = SourceSelection.selectionCount
            }
        .onChange(of: selectionCount, initial: true) { _, count in
            onSelectionCountChange(count)
        }
        // Catalog and saved selections only. Opening this picker never verifies a connection.
        .task(id: backendRaw) { updateConnectors() }
        .task {
            if let source = ProtectedLocalSource(rawValue: pendingProtectedSource) { connectProtectedSource(source) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updateConnectors()
        }
        .sheet(item: $protectedSource, onDismiss: { pendingProtectedSource = "" }) { source in
            SourceAccessSheet(source: source, onStopReading: isProtectedSourceSelected(source) ? {
                stopReading(source)
                pendingProtectedSource = ""
                protectedSource = nil
            } : nil) {
                pendingProtectedSource = ""
                protectedSource = nil
                // Present the source picker only after the permission sheet has dismissed.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    openProtectedSource(source)
                }
            }
            .environment(\.settingsFormStyle, false)
        }
        .sheet(isPresented: $showWhatsAppPicker) {
            ChatPicker(sourceName: "WhatsApp", loadChats: { try WhatsAppSource().listChats() },
                       initialSelection: whatsappChats) { sel in
                whatsappCSV = sel.sorted().joined(separator: ","); runWhatsApp = !sel.isEmpty
            }
            .environment(\.settingsFormStyle, false)
        }
        .sheet(isPresented: $showIMessagePicker) {
            ChatPicker(sourceName: "iMessage", loadChats: { try iMessageSource().listChats() },
                       initialSelection: imessageChats) { sel in
                imessageCSV = sel.sorted().joined(separator: ","); runIMessage = !sel.isEmpty
            }
            .environment(\.settingsFormStyle, false)
        }
        .sheet(isPresented: $showGmailConnect) {
            CloudConnectSheet(.gmail).environment(\.settingsFormStyle, false)
        }
        .sheet(isPresented: $showCalendarConnect) {
            CloudConnectSheet(.calendar).environment(\.settingsFormStyle, false)
        }
        .sheet(isPresented: $showAppleMailPicker) {
            AppleMailPicker(initialSelection: AppleMailSelection.accounts) { accounts in
                appleMailAccounts = accounts.sorted().joined(separator: ",")
            }
            .environment(\.settingsFormStyle, false)
        }
        .sheet(isPresented: $showAppleCalendarConnect) {
            AppleCalendarConnectSheet().environment(\.settingsFormStyle, false)
        }
        .sheet(item: $selectedConnector) { source in
            ConnectorConnectSheet(source: source, connectors: $connectors, context: context)
                .environment(\.settingsFormStyle, false)
        }
        .onChange(of: backendRaw) { selectedConnector = nil }
        .onReceive(NotificationCenter.default.publisher(for: DirectMCPStore.changed).receive(on: RunLoop.main)) { _ in updateConnectors() }
    }

    /// Clicking a protected app is explicit intent. Merely showing its row never opens a
    /// database, asks for FDA, or enables a source. The final chat/account choice owns opt-in.
    private func connectProtectedSource(_ source: ProtectedLocalSource) {
        pendingProtectedSource = source.rawValue
        if source.isReadable { pendingProtectedSource = ""; openProtectedSource(source) }
        else { protectedSource = source }
    }

    private func isProtectedSourceSelected(_ source: ProtectedLocalSource) -> Bool {
        switch source {
        case .whatsapp: runWhatsApp
        case .imessage: runIMessage
        case .notes: runNotes
        case .mail: !appleMailAccounts.isEmpty
        }
    }

    private func stopReading(_ source: ProtectedLocalSource) {
        switch source {
        case .whatsapp: runWhatsApp = false
        case .imessage: runIMessage = false
        case .notes: runNotes = false
        case .mail: appleMailAccounts = ""; AppleMailResearchAccess.save(accounts: [])
        }
    }

    private func openProtectedSource(_ source: ProtectedLocalSource) {
        switch source {
        case .whatsapp: showWhatsAppPicker = true
        case .imessage: showIMessagePicker = true
        case .mail: showAppleMailPicker = true
        case .notes: runNotes = true
        }
        selectionCount = SourceSelection.selectionCount
    }

    // MARK: - Email & Calendar

    private var gmailRow: some View {
        let attention = runGmail && !SourceSelection.hostedSourceReady("gmail")
        return KnowledgeSourcePill(label: "Gmail", detail: attention ? "Connection needs attention" : nil,
                                   asset: "GmailMark", selected: runGmail, featured: true,
                                   locked: CodexAuth.connectorsLocked && !runGmail,
                                   action: { showGmailConnect = true },
                                   needsAttention: attention)
    }

    private var googleCalendarRow: some View {
        let attention = runCalendar && !SourceSelection.hostedSourceReady("calendar")
        return KnowledgeSourcePill(label: "Google Calendar", detail: attention ? "Connection needs attention" : nil,
                                   asset: "GoogleCalendarMark", selected: runCalendar, featured: true,
                                   locked: CodexAuth.connectorsLocked && !runCalendar,
                                   action: { showCalendarConnect = true },
                                   needsAttention: attention)
    }

    /// Apple Mail needs macOS 26. On an older system it is locked while empty; a selection left
    /// over from a newer system shows a Remove button that clears it.
    private var appleMailRow: some View {
        let mailSupported = AppleMailSource.isSupported
        let selected = !appleMailAccounts.isEmpty
        return KnowledgeSourcePill(label: "Apple Mail",
                                   detail: mailSupported
                                       ? protectedDetail(.mail, selected: selected, ready: nil) : "Requires macOS 26",
                                   asset: "AppleMailMark", selected: selected, featured: true,
                                   locked: !mailSupported && !selected,
                                   trailingSymbol: !mailSupported && selected ? "xmark.circle.fill" : nil,
                                   action: {
                                       if mailSupported { connectProtectedSource(.mail) }
                                       else { appleMailAccounts = ""; AppleMailResearchAccess.save(accounts: []) }
                                   },
                                   needsAttention: mailSupported && protectedNeedsAttention(.mail, selected: selected))
            .accessibilityValue(!mailSupported ? "Requires macOS 26 or later"
                : appleMailAccounts.isEmpty ? "Not selected"
                : "\(AppleMailSelection.accounts.count) \(AppleMailSelection.accounts.count == 1 ? "account" : "accounts") selected for analysis")
            .help(mailSupported ? "Choose which Apple Mail accounts to include."
                : "Apple Mail requires macOS 26 or later.")
    }

    private var appleCalendarRow: some View {
        KnowledgeSourcePill(label: "Apple Calendar", detail: appleCalendarDetail,
                            asset: "AppleCalendarMark", selected: AppleCalendarSource.isEnabled, featured: true,
                            action: { showAppleCalendarConnect = true },
                            needsAttention: appleCalendarNeedsAttention)
    }

    private var appleCalendarNeedsAttention: Bool {
        let count = AppleCalendarSource.selectedIDs.count
        guard count > 0 else { return false }
        return !AppleCalendarSource.hasAccess
            || (!calendarReadIssue.isEmpty && !PipelineActivity.shared.isRunning)
    }

    private var appleCalendarDetail: String? {
        let count = AppleCalendarSource.selectedIDs.count
        if count > 0 && !AppleCalendarSource.hasAccess { return "Calendar access needed" }
        if count > 0 && !calendarReadIssue.isEmpty && !PipelineActivity.shared.isRunning { return "Analysis needs attention" }
        return count > 0 ? "\(count) calendars selected · On this Mac" : nil
    }

    // MARK: - Conversations

    private var whatsAppRow: some View {
        let selected = runWhatsApp && !whatsappChats.isEmpty
        return KnowledgeSourcePill(label: "WhatsApp",
                                   detail: protectedDetail(.whatsapp, selected: selected,
                                       ready: whatsappChats.isEmpty ? "Choose the chats that matter" : "\(whatsappChats.count) chats selected"),
                                   asset: "WhatsAppMark", selected: selected, featured: true,
                                   action: { connectProtectedSource(.whatsapp) },
                                   needsAttention: protectedNeedsAttention(.whatsapp, selected: selected))
    }

    private var iMessageRow: some View {
        let selected = runIMessage && !imessageChats.isEmpty
        return KnowledgeSourcePill(label: "iMessage",
                                   detail: protectedDetail(.imessage, selected: selected,
                                       ready: imessageChats.isEmpty ? "Choose the chats that matter" : "\(imessageChats.count) chats selected"),
                                   asset: "IMessageMark", selected: selected, featured: true,
                                   action: { connectProtectedSource(.imessage) },
                                   needsAttention: protectedNeedsAttention(.imessage, selected: selected))
    }

    // MARK: - Folders

    /// Desktop, Downloads or Documents: a switch with Finder's icon for the folder.
    private func folderSwitch(_ name: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        KnowledgeSourcePill(label: name, selected: isOn, action: toggle, toggles: true,
                            folderPath: FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent(name).path)
    }

    // MARK: - Hosted and direct connectors

    private func connectorPill(_ source: ConnectorSource, featured: Bool = false) -> some View {
        ConnectorPill(source: source,
                      locked: !ConnectorRegistry.isKBEnabled(source.connector?.slug ?? source.serviceSlug)
                        && (source.usesHostedConnection ? CodexAuth.connectorsLocked : CodexAuth.knowledgeBaseOnly),
                      featured: featured) { selectedConnector = source }
    }

    private func protectedDetail(_ source: ProtectedLocalSource, selected: Bool, ready: String?) -> String? {
        selected && !source.isReadable ? "Access or synced data needed" : ready
    }

    private func protectedNeedsAttention(_ source: ProtectedLocalSource, selected: Bool) -> Bool {
        selected && !source.isReadable
    }

    private func updateConnectors() {
        connectors = ConnectorRegistry.detectedForCurrentBackend().filter { $0.origin != .direct }
            + DirectMCPStore.connections().map(\.detected)
        selectionCount = SourceSelection.selectionCount
    }

    // Selections are always revocable. The three-source requirement gates starting personal
    // setup, never a user's ability to stop reading a source in Settings.

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Add a folder for Sentient to read."
        // A sheet on the window the user is in, not a free-floating app-modal panel.
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            for url in panel.urls { CustomRoots.add(url) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}

/// Source-specific explanation, reached only by choosing a protected local source. A standard
/// form sheet: the source's icon and name, the live Full Disk Access status with a hand-off to
/// System Settings, and relaunch. No automatic relaunch: the user can leave this pending while a
/// Sidekick task continues in another window.
private struct SourceAccessSheet: View {
    let source: ProtectedLocalSource
    var onStopReading: (() -> Void)?
    var onReady: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var checked = false
    /// Opening the source's database is real I/O, so it is read on appear and on Check Again,
    /// never on every render.
    @State private var readable = false

    private var asset: String {
        switch source {
        case .whatsapp: "WhatsAppMark"
        case .imessage: "IMessageMark"
        case .notes: "AppleNotesMark"
        case .mail: "AppleMailMark"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                KnowledgeSourcePill.icon(asset: asset, size: 40)
                Text("Connect \(source.title)")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(Space.xl)

            Form {
                SwiftUI.Section {
                    StatusRow("Full Disk Access", tile: .fullDiskAccess,
                              detail: readable ? "Allowed" : "Not allowed",
                              tone: readable ? .ok : .warning) {
                        Button("Open Settings…") {
                            PermissionGuide.shared.guide(.fullDiskAccess, dragging: Bundle.main.bundleURL)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("macOS protects \(source.title)’s local data with Full Disk Access. Allow Sentient in System Settings to choose what it can read from this source.")
                        Text("Your selection stays optional. Granting access does not select any other app or folder.")
                    }
                }

                SwiftUI.Section {
                    LabeledContent("Relaunch") {
                        Button("Relaunch Sentient") { _ = SafeAppRelaunch.shared.relaunchForPersonalSetup() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!SafeAppRelaunch.shared.canRelaunch)
                    }
                } footer: {
                    if let reason = SafeAppRelaunch.shared.statusReason { Text(reason) }
                }

                if checked && !readable {
                    SwiftUI.Section {
                        StatusLabel("Access is not ready yet. If you already allowed Sentient, finish any active tasks and relaunch the app. Also make sure \(source.title) has data synced to this Mac.",
                                    tone: .warning)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if let onStopReading {
                    Button("Stop Reading \(source.title)", role: .destructive, action: onStopReading)
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("Later") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Check Again") {
                    readable = source.isReadable
                    if readable { onReady() } else { checked = true }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(Space.l)
        }
        .onAppear { readable = source.isReadable }
        .presentationSizing(.form)
    }
}
