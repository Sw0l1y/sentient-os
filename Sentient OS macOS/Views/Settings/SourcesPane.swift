//
// SourcesPane.swift
// Settings › Knowledge Sources. The picker is the pane's Form, shared with onboarding so both
// surfaces expose the same catalog, account connections, and persisted source selection. This
// pane adds only its whisper (a leading footer) and its window subtitle.
// Doc: Documentation - Settings.md
//

import SwiftUI

struct SourcesPane: View {
    @State private var count = SourceSelection.selectionCount

    var body: some View {
        KnowledgeSourcesPicker(onSelectionCountChange: { count = $0 })
            .leadingSections {
                SwiftUI.Section {} footer: {
                    Text("The context your Sentient learns from, every night.")
                }
            }
            .pageSubtitle(count == 1 ? "1 source on" : "\(count) sources on", page: .settings, pane: .sources)
    }
}

#Preview("Knowledge Sources pane") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            SourcesPane()
                .environment(\.settingsFormStyle, true)
                .frame(width: 720, height: 720)
                .environment(\.colorScheme, scheme)
        }
    }
}
