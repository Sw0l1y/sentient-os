//
//  ShareKnowledgePane.swift
//  Sentient OS macOS
//
//  Settings › Share with AIs, laid out like System Settings › General › Sharing: a status row and
//  a row that pushes the setup page (ConnectAIsView) in SettingsView's NavigationStack. That page
//  owns sharing on AND off (its consent step and toolbar switch), so this pane carries no toggle.
//  Live activity from /stats shows while sharing is on. Regenerate lives in MirrorClient only
//  (a support/dev remediation; a UI button was a footgun that bricks every connector).
//

import SwiftUI
import AppKit

struct ShareKnowledgePane: View {
    @State private var enabled = false
    @State private var stats: MirrorClient.Stats?
    @State private var loaded = false

    var body: some View {
        PaneForm {
            connectionsSection
            if loaded && enabled {
                activitySection
            } else if loaded {
                localSection
            }
            controlSection
        }
        .pageSubtitle(loaded ? (enabled ? "On" : "Off") : nil, page: .settings, pane: .shareKnowledge)
        // Sharing flips inside the pushed Connect Your AIs page; re-probe on every return so
        // Activity vs. local-only never shows a stale answer.
        .onAppear { Task { await refresh() } }
    }

    // MARK: - AI Connections

    private var connectionsSection: some View {
        Section {
            LabeledContent {
                if loaded {
                    StatusLabel(enabled ? "On" : "Off", tone: enabled ? .ok : .off)
                }
            } label: {
                TileLabel("Share Your Knowledge", tile: .sharing)
            }
            NavigationLink(enabled ? "Configure…" : "Set Up Sharing…") {
                ConnectAIsView()
            }
        } header: {
            Text("AI Connections")
        } footer: {
            Text("Let ChatGPT, Claude, and other AIs get to know you. Connect your AIs with a private link. Works on your phone, too.")
        }
    }

    // MARK: - Activity (sharing on)

    private var activitySection: some View {
        Section("Activity") {
            if let stats {
                LabeledContent("Last 24 Hours", value: readsLine(stats))
                if let last = stats.lastAccess {
                    LabeledContent("Last Read", value: last.formatted(.relative(presentation: .named)))
                }
            } else {
                Text("No activity yet. Connect an AI and ask it about you.")
            }
        }
    }

    private func readsLine(_ stats: MirrorClient.Stats) -> String {
        if stats.notesRead24h == 0 { return "Your AIs haven’t read anything in the last day." }
        return "Your AIs read \(stats.notesRead24h) note\(stats.notesRead24h == 1 ? "" : "s") in the last 24 hours."
    }

    // MARK: - Local only (sharing off)

    private var localSection: some View {
        Section("Use Your Knowledge Locally") {
            Text(PrivacyCopy.localKnowledge)
        }
    }

    // MARK: - Privacy

    private var controlSection: some View {
        Section("Your Knowledge, Your Control") {
            Text("Sharing is optional. Your original knowledge stays in a folder on this Mac.")
            DisclosureGroup("How Sharing and Privacy Work") {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(PrivacyCopy.sharingContents)
                    Text(PrivacyCopy.sharingEncryption)
                    Text(PrivacyCopy.sharingControl)
                    Text(PrivacyCopy.sharingOpenSource)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Probes

    private func refresh() async {
        enabled = await MirrorClient.shared.isEnabled
        loaded = true
        if enabled { stats = try? await MirrorClient.shared.stats() }
    }
}

#Preview("Share with AIs pane") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            NavigationStack { ShareKnowledgePane() }
                .frame(width: 720, height: 640)
                .environment(\.colorScheme, scheme)
        }
    }
}
