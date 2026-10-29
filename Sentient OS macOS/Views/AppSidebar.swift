// The main window's sidebar: Home, Knowledge, Analysis and pending setup (plain symbols, tinted
// by the sidebar), then every Settings pane (System Settings tiles). Selection routes through
// MainNavigation, so Knowledge's unsaved-edit guard still applies. The footer shows background
// progress only and is hidden when nothing runs.
// Doc: Documentation - App Shell.md

import SwiftUI

struct AppSidebar: View {
    @Environment(AppState.self) private var appState
    private let navigation = MainNavigation.shared
    @AppStorage("nav.settingsExpanded") private var settingsExpanded = true

    enum Item: Hashable {
        case home, knowledge, analysis, setup
        case settings(SettingsView.Pane)
    }

    private var current: Item {
        switch navigation.page {
        case .home: return .home
        case .knowledge: return .knowledge
        case .analysis: return .analysis
        case .setup: return .setup
        case .settings: return .settings(navigation.settingsPane)
        }
    }

    private var selection: Binding<Item?> {
        Binding(get: { current }, set: { item in
            switch item {
            case .home: navigation.show(.home)
            case .knowledge: navigation.show(.knowledge)
            case .analysis: navigation.show(.analysis)
            case .setup: navigation.show(.setup)
            case .settings(let pane): navigation.show(.settings, settingsPane: pane)
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
                Label("Knowledge", systemImage: "books.vertical").tag(Item.knowledge)
                analysisRow.tag(Item.analysis)
                if setupPending {
                    Label("Finish Setup", systemImage: "checklist").tag(Item.setup)
                }
            }
            Section("Settings", isExpanded: $settingsExpanded) {
                ForEach(SettingsView.Pane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        IconTile(.pane(pane), size: 20)
                    }
                    .badge(pane == .health ? navigation.healthIssueCount : 0)
                    .tag(Item.settings(pane))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: PageMetrics.sidebarMin, ideal: PageMetrics.sidebarIdeal,
                                        max: PageMetrics.sidebarMax)
        .accessibilityIdentifier("navigation.sidebar")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatusFooter()
        }
    }

    private var analysisRow: some View {
        Label {
            HStack(spacing: 6) {
                Text("Analysis")
                Spacer(minLength: 0)
                if appState.processing.isBusy {
                    ProgressView().controlSize(.small)
                } else if appState.processing.needsAttention {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Needs attention")
                }
            }
        } icon: {
            Image(systemName: "waveform.path")
        }
        .accessibilityIdentifier("navigation.analysis")
    }
}

/// Background progress only, one `.caption` line each: the analysis status (hidden on the Analysis
/// page), the on-device model download, the computer-use setup, and in DEBUG the Developer Tools
/// hammer. Hidden entirely when nothing runs.
private struct SidebarStatusFooter: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    @State private var download = ModelDownload.shared
    private let navigation = MainNavigation.shared

    private var computerSetup: ComputerUseSetup {
        .instance(for: .selected(for: ModelBackend(rawValue: backendRaw) ?? .chatgpt))
    }

    private var showsAnalysis: Bool {
        appState.processing.isBusy && navigation.page != .analysis
    }

    /// Mirrors ModelDownloadWhisper's own visibility, so the footer hides when it would be empty.
    private var showsDownload: Bool {
        guard !download.fullScreenVisible else { return false }
        switch download.phase {
        case .downloading, .verifying, .failed: return true
        case .idle, .ready: return false
        }
    }

    private var showsComputerSetup: Bool { computerSetup.isInstalling }

    private var showsDeveloperTools: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if showsAnalysis || showsDownload || showsComputerSetup || showsDeveloperTools {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        if showsAnalysis {
                            Button {
                                navigation.show(.analysis)
                            } label: {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text(appState.processing.statusLine)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Show Analysis")
                            .accessibilityIdentifier("sidebar.analysisStatus")
                            .transition(.opacity)
                        }
                        if showsDownload {
                            ModelDownloadWhisper(download: download)
                        }
                        if showsComputerSetup {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("Setting up computer use…")
                                    .lineLimit(1)
                            }
                            .transition(.opacity)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if DEBUG
                    Button {
                        navigation.showDevTools = true
                    } label: {
                        Image(systemName: "hammer")
                    }
                    .buttonStyle(.borderless)
                    .help("Developer Tools")
                    .accessibilityLabel("Developer Tools")
                    #endif
                }
                .padding(12)
            }
        }
        .animation(Motion.gated(Motion.standard, reduceMotion: motionOverride ?? systemReduced),
                   value: [showsAnalysis, showsDownload, showsComputerSetup])
    }
}
