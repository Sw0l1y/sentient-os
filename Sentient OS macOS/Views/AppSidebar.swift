// The main window's sidebar: Home, Knowledge, Analysis and pending setup, then every Settings
// pane. Selection routes through MainNavigation, so Knowledge's unsaved-edit guard still applies.
// Doc: Documentation - App Shell.md

import SwiftUI

struct AppSidebar: View {
    @Environment(AppState.self) private var appState
    private let navigation = MainNavigation.shared

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
                    Label("Personal Setup", systemImage: "person.crop.circle.badge.plus").tag(Item.setup)
                }
            }
            Section("Settings") {
                ForEach(SettingsView.Pane.allCases) { pane in
                    Label(pane.title, systemImage: pane.icon).tag(Item.settings(pane))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        .accessibilityIdentifier("navigation.sidebar")
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
