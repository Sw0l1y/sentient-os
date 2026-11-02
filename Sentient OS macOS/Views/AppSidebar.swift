// The main window's sidebar (NAV-SPEC 1-2). Main mode: Home, Finish Setup while setup is pending,
// then a Knowledge section — All Knowledge and one row per top-level vault folder with its note
// count — and a footer with the analysis status (click → Analysis) and a Settings gear. Settings
// mode (page == .settings) swaps the same column to a Back header and the seven Settings panes.
// Selection routes through MainNavigation, so Knowledge's unsaved-edit guard still applies.
// Doc: Documentation - App Shell.md

import SwiftUI
import AppKit

struct AppSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private let navigation = MainNavigation.shared
    private let knowledge = AppSidebarKnowledge.shared

    private var settingsMode: Bool { navigation.page == .settings }

    var body: some View {
        ZStack {
            if settingsMode {
                SettingsModeList()
                    .transition(.opacity)
            } else {
                MainModeList()
                    .transition(.opacity)
            }
        }
        .animation(Motion.gated(Motion.quick, reduceMotion: motionOverride ?? systemReduced), value: settingsMode)
        .navigationSplitViewColumnWidth(min: PageMetrics.sidebarMin, ideal: PageMetrics.sidebarIdeal,
                                        max: PageMetrics.sidebarMax)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppSidebarFooter(settingsMode: settingsMode)
        }
        // Vault refresh (NAV-SPEC 1.3): on appear, on every page change (leaving Knowledge after an
        // edit, returning to the window's main mode), when a full analysis cycle rewrote the vault
        // (knowledgeRevision) or any run ends, when the app comes forward (an edit in Finder or
        // Obsidian), and every few seconds while Knowledge itself is showing (its saves, new
        // notes, new folders and deletions). Each refresh scans off-main and publishes only a change.
        .task { knowledge.refresh() }
        .onChange(of: navigation.page) { _, _ in knowledge.refresh() }
        .onChange(of: appState.processing.knowledgeRevision) { _, _ in knowledge.refresh() }
        .onChange(of: appState.processing.isBusy) { _, busy in if !busy { knowledge.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            knowledge.refresh()
        }
        .task(id: navigation.page == .knowledge) {
            guard navigation.page == .knowledge else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                if NSApp.isActive { knowledge.refresh() }
            }
        }
    }
}

// MARK: - Main mode

private struct MainModeList: View {
    @Environment(AppState.self) private var appState
    private let navigation = MainNavigation.shared
    private let knowledge = AppSidebarKnowledge.shared
    @AppStorage("nav.knowledgeExpanded") private var knowledgeExpanded = true

    enum Item: Hashable {
        case home, setup, allKnowledge
        case domain(URL)
    }

    /// Analysis has no row (its status button in the footer shows the selection) and Settings is
    /// the other mode, so both select nothing here.
    private var current: Item? {
        switch navigation.page {
        case .home: return .home
        case .setup: return .setup
        case .knowledge: return navigation.knowledgeScope.map(Item.domain) ?? .allKnowledge
        case .analysis, .settings: return nil
        }
    }

    private var selection: Binding<Item?> {
        Binding(get: { current }, set: { item in
            switch item {
            case .home: navigation.show(.home)
            case .setup: navigation.show(.setup)
            case .allKnowledge: navigation.showKnowledge(scope: nil)
            case .domain(let url): navigation.showKnowledge(scope: url)
            case nil: break
            }
        })
    }

    private var setupPending: Bool {
        (!appState.hasCompletedPersonalSetup && !appState.processing.initialComplete)
            || navigation.page == .setup
    }

    var body: some View {
        List(selection: selection) {
            Section {
                Label("Home", systemImage: "house").tag(Item.home)
                if setupPending {
                    Label("Finish Setup", systemImage: "checklist").tag(Item.setup)
                }
            }
            Section("Knowledge", isExpanded: $knowledgeExpanded) {
                Label("All Knowledge", systemImage: "books.vertical").tag(Item.allKnowledge)
                ForEach(knowledge.domains) { domain in
                    Label(domain.name, systemImage: domain.symbol)
                        .badge(domain.noteCount)
                        .tag(Item.domain(domain.url))
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("navigation.sidebar")
    }
}

// MARK: - Settings mode

private struct SettingsModeList: View {
    private let navigation = MainNavigation.shared

    private var selection: Binding<SettingsView.Pane?> {
        Binding(get: { navigation.page == .settings ? navigation.settingsPane : nil }, set: { pane in
            if let pane { navigation.show(.settings, settingsPane: pane) }
        })
    }

    var body: some View {
        List(selection: selection) {
            Section {
                Button {
                    navigation.leaveSettings()
                } label: {
                    Label {
                        Text("Settings").font(.headline)
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back")
                .accessibilityLabel("Back")
                .accessibilityHint("Leaves Settings")
                .accessibilityIdentifier("settings.back")
            }
            Section {
                ForEach(SettingsView.Pane.allCases) { pane in
                    Label(pane.title, systemImage: TileSpec.pane(pane).symbol)
                        .badge(pane == .health ? HealthBoard.shared.badgeCount : 0)
                        .tag(pane)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("navigation.sidebar")
    }
}

// MARK: - Footer

/// One `.caption` row, always visible: the analysis status button and, in main mode, the Settings
/// gear (with the health issue count) and the DEBUG hammer. The on-device model download and the
/// computer-use setup lines sit above the row while they run.
private struct AppSidebarFooter: View {
    let settingsMode: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    @State private var download = ModelDownload.shared
    private let navigation = MainNavigation.shared

    private var computerSetup: ComputerUseSetup {
        .instance(for: .selected(for: ModelBackend(rawValue: backendRaw) ?? .chatgpt))
    }

    /// Mirrors ModelDownloadWhisper's own visibility, so no empty line takes space.
    private var showsDownload: Bool {
        guard !download.fullScreenVisible else { return false }
        switch download.phase {
        case .downloading, .verifying, .failed: return true
        case .idle, .ready: return false
        }
    }

    private var showsComputerSetup: Bool { computerSetup.isInstalling }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsDownload {
                ModelDownloadWhisper(download: download)
                    .transition(.opacity)
            }
            if showsComputerSetup {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Setting up computer use…")
                        .lineLimit(1)
                }
                .transition(.opacity)
            }
            HStack(spacing: 8) {
                AnalysisStatusButton()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The id the labs know this control by (SPEC-00 5.9, SidekickPolishLab); the
                    // button inside carries NAV-SPEC's sidebar.analysisStatus.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("navigation.analysis")
                if !settingsMode {
                    #if DEBUG
                    Button {
                        navigation.showDevTools = true
                    } label: {
                        Image(systemName: "hammer")
                    }
                    .buttonStyle(.borderless)
                    .font(.body)
                    .help("Developer Tools")
                    .accessibilityLabel("Developer Tools")
                    #endif
                    SettingsGearButton()
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(Motion.gated(Motion.standard, reduceMotion: motionOverride ?? systemReduced),
                   value: [showsDownload, showsComputerSetup])
    }
}

/// The analysis state in one line: busy (spinner + status line), needs attention, or the last run.
private struct AnalysisStatusButton: View {
    @Environment(AppState.self) private var appState
    private let navigation = MainNavigation.shared

    private var selected: Bool { navigation.page == .analysis }

    var body: some View {
        Button {
            navigation.show(.analysis)
        } label: {
            HStack(spacing: 6) {
                if appState.processing.isBusy {
                    ProgressView().controlSize(.mini)
                    line(appState.processing.statusLine)
                } else if appState.processing.needsAttention {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    // Names the source when the saved record knows it ("Apple Mail needs attention").
                    line(appState.processing.statusLine)
                } else {
                    Image(systemName: "checkmark.circle")
                        .accessibilityHidden(true)
                    TimelineView(.everyMinute) { _ in
                        line(lastRunLine)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .help("Show Analysis")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.analysisStatus")
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// The same last-run date Home's analysis summary shows (the last full cycle), falling back to
    /// when the first analysis finished.
    private var lastRunLine: String {
        let last = UserDefaults.standard.object(forKey: ProactiveCycle.lastCycleKey) as? Date
            ?? ProcessingPlan.initialCompletedAt()
        guard let last else { return "Not analyzed yet" }
        return "Analyzed \(last.formatted(.relative(presentation: .named)))"
    }
}

/// Opens Settings mode at the last pane. A red count marks Permissions & Health issues, the same
/// count the Permissions & Health row shows (HealthBoard).
private struct SettingsGearButton: View {
    private let navigation = MainNavigation.shared

    var body: some View {
        let issues = HealthBoard.shared.badgeCount
        Button {
            navigation.show(.settings, settingsPane: navigation.lastSettingsPane)
        } label: {
            Image(systemName: "gearshape")
                .overlay(alignment: .topTrailing) {
                    if issues > 0 {
                        Text(issues > 9 ? "9+" : "\(issues)")
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Capsule().fill(.red))
                            .offset(x: 7, y: -6)
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(.borderless)
        .font(.body)
        .help("Settings")
        .accessibilityLabel("Settings")
        .accessibilityValue(issues > 0 ? (issues == 1 ? "1 issue" : "\(issues) issues") : "")
        .accessibilityIdentifier("navigation.settings")
    }
}

// MARK: - Esc in Settings mode

/// Esc leaves Settings mode (NAV-SPEC 2.1; ⌘[ is the View menu's Back command). A local key
/// monitor on the main window, so it never fires inside a sheet, a popover, another window, or
/// while a text field or text view is being edited (Esc stays theirs there).
struct AppSidebarSettingsEscape: ViewModifier {
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    MainActor.assumeIsolated { Self.leavesSettings(event) } ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private static func leavesSettings(_ event: NSEvent) -> Bool {
        let navigation = MainNavigation.shared
        guard navigation.page == .settings, event.keyCode == 53,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              let window = event.window, SentientOSApp.isHomeWindow(window),
              window.attachedSheet == nil, !(window.firstResponder is NSText)
        else { return false }
        navigation.leaveSettings()
        return true
    }
}
