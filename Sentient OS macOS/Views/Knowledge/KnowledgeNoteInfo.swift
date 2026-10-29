//
//  KnowledgeNoteInfo.swift
//  Sentient OS macOS
//
//  Facts about the open note, for the reader's metadata line and the Note Info inspector:
//  its folder, when it was last edited, the notes it links with (from the graph's wikilink
//  adjacency, so the reader and the graph always agree), and its file name.
//  `KnowledgeNoteInfo` is a pure value built off the main render path; `KnowledgeNoteInspector`
//  is the Notes/Finder-style inspector that shows it.
//

import SwiftUI
import AppKit

struct KnowledgeNoteInfo: Equatable {
    struct Link: Hashable, Identifiable {
        let url: URL
        let title: String
        var id: URL { url }
    }

    let url: URL
    let title: String
    /// The first folder under the vault root; "Overview" for the README, "Knowledge Base" at the top level.
    let folder: String
    let fileName: String
    let modified: Date?
    /// The graph neighbours of this note (links in and out together), the Overview root excluded, by title.
    let linked: [Link]
    /// The graph domain (`-1` = root level); nil before the graph is built or when the note is not in it.
    let domain: Int?
    /// False until the graph is built, so the link count is not claimed before it is known.
    let linksKnown: Bool

    /// "Edited yesterday · 4 links · Projects"; parts that are unknown are left out.
    var metadataLine: String {
        var parts: [String] = []
        if let modified { parts.append("Edited " + Self.relative(modified)) }
        if linksKnown { parts.append(linked.count == 1 ? "1 link" : "\(linked.count) links") }
        parts.append(folder)
        return parts.joined(separator: " · ")
    }

    static func make(url: URL, title: String, vault: KnowledgeVault, graph: SkyGraph?) -> KnowledgeNoteInfo {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        var linked: [Link] = []
        var domain: Int?
        if let graph, let i = graph.nodes.firstIndex(where: { $0.url == url }) {
            domain = graph.nodes[i].domain
            if graph.adjacency.indices.contains(i) {
                linked = graph.adjacency[i]
                    .filter { graph.nodes.indices.contains($0) && !graph.nodes[$0].isRoot }
                    .map { Link(url: graph.nodes[$0].url, title: graph.nodes[$0].title) }
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
        }
        return KnowledgeNoteInfo(url: url, title: title,
                                 folder: folderName(of: url, vault: vault),
                                 fileName: url.lastPathComponent,
                                 modified: modified, linked: linked, domain: domain,
                                 linksKnown: graph != nil)
    }

    private static func folderName(of url: URL, vault: KnowledgeVault) -> String {
        if url == vault.readme { return "Overview" }
        let parent = url.deletingLastPathComponent().standardizedFileURL.pathComponents
        let base = vault.root.standardizedFileURL.pathComponents
        guard parent.count > base.count, Array(parent.prefix(base.count)) == base else { return "Knowledge Base" }
        return parent[base.count]
    }

    private static func relative(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

/// The Note Info inspector: the note's facts as grouped rows, its linked notes, and Reveal in Finder.
struct KnowledgeNoteInspector: View {
    let info: KnowledgeNoteInfo?
    let onOpen: (URL) -> Void
    let onReveal: (URL) -> Void

    init(info: KnowledgeNoteInfo?, onOpen: @escaping (URL) -> Void, onReveal: @escaping (URL) -> Void) {
        self.info = info
        self.onOpen = onOpen
        self.onReveal = onReveal
    }

    var body: some View {
        if let info {
            Form {
                Section {
                    LabeledContent("Folder") {
                        HStack(spacing: Space.xs) {
                            if let d = info.domain {
                                Circle().fill(SkyRenderer.domainColor(d)).frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                            }
                            Text(info.folder)
                        }
                    }
                    LabeledContent("Modified") {
                        if let d = info.modified {
                            Text(d, format: .dateTime.month().day().year().hour().minute())
                        } else {
                            Text("—")
                        }
                    }
                    LabeledContent("Links") {
                        if info.linksKnown {
                            Text(info.linked.count, format: .number).monospacedDigit()
                        } else {
                            Text("—")
                        }
                    }
                    LabeledContent("File") {
                        Text(info.fileName)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                if !info.linked.isEmpty {
                    Section("Linked Notes") {
                        ForEach(info.linked) { link in
                            Button(link.title) { onOpen(link.url) }
                                .buttonStyle(.link)
                                .lineLimit(1)
                        }
                    }
                }
                Section {
                    Button("Reveal in Finder") { onReveal(info.url) }
                        .buttonStyle(.link)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Note Selected", systemImage: "info.circle")
        }
    }
}

#Preview("Note Info") {
    let info = KnowledgeNoteInfo(
        url: URL(fileURLWithPath: "/Vault/Projects/Northstar.md"), title: "Northstar",
        folder: "Projects", fileName: "Northstar.md", modified: .now.addingTimeInterval(-90_000),
        linked: [.init(url: URL(fileURLWithPath: "/Vault/People/Alex.md"), title: "Alex"),
                 .init(url: URL(fileURLWithPath: "/Vault/Plans/Friday.md"), title: "Friday")],
        domain: 0, linksKnown: true)
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            KnowledgeNoteInspector(info: info, onOpen: { _ in }, onReveal: { _ in })
                .frame(width: 300, height: 420)
                .environment(\.colorScheme, scheme)
        }
    }
}
