//
//  SettingsView.swift
//  Sentient OS macOS
//
//  The Settings detail column, as in System Settings: the sidebar row (AppSidebar) picks the pane,
//  and the window title and subtitle name it (RootView). Every pane is a grouped Form and lives
//  beside this file: SourcesPane · FrontierModelPane · DoubleTapPane · ProactivePane ·
//  ShareKnowledgePane · SystemPane · HealthPane.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    /// The panes, in sidebar order. `String(describing:)` of a case is persisted by MainNavigation
    /// (`nav.lastSettingsPane`), so the case names and their order never change.
    enum Pane: CaseIterable, Identifiable {
        case sources, frontierModel, doubleTap, proactive, shareKnowledge, system, health

        var id: Self { self }
        var title: String {
            switch self {
            case .sources:        return "Knowledge Sources"
            case .frontierModel:  return "AI Model"
            case .doubleTap:      return "Double Tap"
            case .proactive:      return "Sidekick"
            case .shareKnowledge: return "Share with AIs"
            case .system:         return "General"
            case .health:         return "Permissions & Health"
            }
        }
        /// The filled symbol of the pane's sidebar tile (equals `TileSpec.pane(self).symbol`).
        var icon: String {
            switch self {
            case .sources:        return "tray.full.fill"
            case .frontierModel:  return "cpu.fill"
            case .doubleTap:      return "hand.tap.fill"
            case .proactive:      return "sparkles"
            case .shareKnowledge: return "antenna.radiowaves.left.and.right"
            case .system:         return "gearshape.fill"
            case .health:         return "checkmark.shield.fill"
            }
        }
    }

    @Bindable private var navigation = MainNavigation.shared
    private var selection: Pane { navigation.settingsPane }

    /// The stack lets a pane push a detail page (Share with AIs → Connect Your AIs); `.id` resets
    /// it whenever the pane changes. Panes draw no title: the window chrome names them.
    var body: some View {
        NavigationStack {
            detail
        }
        .id(selection)
        .environment(\.settingsFormStyle, true)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .sources:        SourcesPane()
        case .frontierModel:  FrontierModelPane()
        case .doubleTap:      DoubleTapPane()
        case .proactive:      ProactivePane()
        case .shareKnowledge: ShareKnowledgePane()
        case .system:         SystemPane()
        case .health:         HealthPane()
        }
    }
}

#Preview("Settings") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            SettingsView()
                .frame(width: 720, height: 760)
                .environment(\.colorScheme, scheme)
        }
    }
}
