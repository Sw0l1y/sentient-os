//
//  SettingsView.swift
//  Sentient OS macOS
//
//  The Settings page — the selected pane, with the trust ribbon riding the foot. The main
//  window's sidebar lists the panes (AppSidebar). Every pane is real and lives beside this file:
//  SourcesPane · FrontierModelPane · DoubleTapPane · ProactivePane · ShareKnowledgePane · SystemPane · HealthPane.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    /// The sections, in sidebar order.
    enum Pane: CaseIterable, Identifiable {
        case sources, frontierModel, doubleTap, proactive, shareKnowledge, system, health

        var id: Self { self }
        var title: String {
            switch self {
            case .sources:   return "Knowledge Sources"
            case .frontierModel: return "Frontier Model Choice"
            case .doubleTap: return "Double Tap"
            case .proactive: return "Proactive & Sidekick"
            case .shareKnowledge: return "Give AIs Knowledge"
            case .system:    return "System"
            case .health:    return "Permissions & Health"
            }
        }
        var icon: String {
            switch self {
            case .sources:   return "tray.full"
            case .frontierModel: return "cpu"
            case .doubleTap: return "hand.tap"
            case .proactive: return "sparkles"
            case .shareKnowledge: return "antenna.radiowaves.left.and.right"
            case .system:    return "gearshape"
            case .health:    return "checkmark.shield"
            }
        }
    }

    @Bindable private var navigation = MainNavigation.shared
    private var selection: Pane { navigation.settingsPane }

    /// The main window's sidebar lists the panes; this is the selected one. A pane may push
    /// a sub-page (Give AIs Knowledge → Connect your AIs), which the stack's Back button pops.
    var body: some View {
        NavigationStack {
            detail.navigationTitle(selection.title)
        }
        .id(selection)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            Group {
                switch selection {
                case .sources:   SourcesPane()
                case .frontierModel: FrontierModelPane()
                case .doubleTap: DoubleTapPane()
                case .proactive: ProactivePane()
                case .shareKnowledge: ShareKnowledgePane()
                case .system:    SystemPane()
                case .health:    HealthPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if selection == .sources || selection == .health { trustFooter }
        }
    }

    /// The trust ribbon — in Settings it rides ONLY Knowledge Sources and Permissions & Health,
    /// the panes where the files story is the message (what we read · what the grants allow);
    /// boilerplate on every pane would cheapen it.
    private var trustFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield").font(.system(size: selection == .sources ? 10.5 : 12)).foregroundStyle(Theme.Ink.label)
            Text(PrivacyCopy.trustRibbon)
                .font(.system(size: selection == .sources ? 11.5 : 13)).foregroundStyle(Theme.Ink.label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .overlay(alignment: .top) { Divider() }
    }
}

#Preview("Settings") {
    SettingsView().frame(width: 1120, height: 800)
        .preferredColorScheme(.dark)
}
