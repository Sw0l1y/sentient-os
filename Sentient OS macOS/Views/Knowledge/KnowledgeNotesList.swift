//
//  KnowledgeNotesList.swift
//  Sentient OS macOS
//
//  The Knowledge page's notes list, shaped like the Notes folder list: a source list with the
//  pinned "Overview" (the vault README), disclosure folders and note rows; while searching, a
//  flat list of matching notes with their folders. A bottom strip, like Mail's mailbox footer,
//  shows where the notes live (synced to the encrypted cloud MCP copy, or on this Mac only) and
//  how many there are. Selecting a row goes through KnowledgeView's `requestOpen`, so unsaved
//  edits still prompt before the switch.
//
//  Scoped (NAV-SPEC 4: a sidebar domain row, `MainNavigation.knowledgeScope`): the list shows only
//  that folder's subtree (its notes and subfolders, without Overview), search searches within it,
//  and the strip counts its notes. The scope helpers at the bottom (`KnowledgeVault.folder(at:)`,
//  `notes(in:)`, `landingNote(in:)`) are shared with KnowledgeView.
//

import SwiftUI
import AppKit

struct KnowledgeNotesList: View {
    let vault: KnowledgeVault?
    /// The scoped folder, or nil for the whole vault.
    let scope: VaultNode?
    let selection: URL?
    let search: String
    @Binding var expanded: Set<URL>
    let mirrorEnabled: Bool
    let onOpen: (URL) -> Void
    let onCreate: (_ folder: Bool, _ parent: URL?) -> Void
    let onTrash: (URL) -> Void
    let onReveal: (URL) -> Void

    init(vault: KnowledgeVault?, scope: VaultNode? = nil, selection: URL?, search: String,
         expanded: Binding<Set<URL>>,
         mirrorEnabled: Bool, onOpen: @escaping (URL) -> Void,
         onCreate: @escaping (_ folder: Bool, _ parent: URL?) -> Void,
         onTrash: @escaping (URL) -> Void, onReveal: @escaping (URL) -> Void) {
        self.vault = vault
        self.scope = scope
        self.selection = selection
        self.search = search
        self._expanded = expanded
        self.mirrorEnabled = mirrorEnabled
        self.onOpen = onOpen
        self.onCreate = onCreate
        self.onTrash = onTrash
        self.onReveal = onReveal
    }

    var body: some View {
        List(selection: Binding(get: { selection }, set: { url in
            if let url, url != selection { onOpen(url) }
        })) {
            if search.isEmpty {
                if scope == nil, let readme = vault?.readme {
                    Label("Overview", systemImage: "text.book.closed")
                        .tag(readme)
                        .contextMenu { noteMenu(readme) }
                }
                ForEach(scope?.children ?? vault?.nodes ?? [], id: \.url) { node in
                    KnowledgeTreeRow(node: node, expanded: $expanded,
                                     onCreate: onCreate, onTrash: onTrash, onReveal: onReveal)
                }
            } else {
                ForEach(results, id: \.url) { node in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(node.name).lineLimit(1)
                            Text(folder(of: node))
                                .font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                    .tag(node.url)
                    .contextMenu { noteMenu(node.url) }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if !search.isEmpty && results.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if search.isEmpty, let scope, scope.children.isEmpty {
                ContentUnavailableView("No Notes", systemImage: "folder",
                                       description: Text("“\(scope.name)” is empty."))
            }
        }
        .contextMenu {   // empty list space → create in the scoped folder, or at the vault root
            Button("New Note…") { onCreate(false, scope?.url) }
            Button("New Folder…") { onCreate(true, scope?.url) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: Space.s) {
                    syncLabel
                    Spacer(minLength: 0)
                    Text(countText).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
            }
            .background(.bar)
        }
    }

    /// Where the notes live: on this Mac only (mirror off), or the live cloud-MCP sync state.
    /// AES-256-GCM seals the vault on this Mac before upload; the relay stores ciphertext and
    /// decrypts in memory for authorised requests.
    @ViewBuilder private var syncLabel: some View {
        Group {
            if mirrorEnabled {
                switch VaultActivity.shared.syncState {
                case .synced:
                    Label("Synced", systemImage: "lock.icloud")
                        .help("Synced to your encrypted cloud MCP copy")
                case .pending:
                    Label("Sync pending", systemImage: "icloud")
                        .help("Changes will sync to your encrypted cloud MCP copy soon")
                case .syncing:
                    Label("Syncing…", systemImage: "arrow.clockwise.icloud")
                        .help("Syncing to your encrypted cloud MCP copy")
                }
            } else {
                Label("On this Mac", systemImage: "internaldrive")
                    .help("Saved on this Mac only")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    /// Same filter as KnowledgeView.searchResults (which keeps its own copy for Search Return):
    /// note titles only, never body text, within the scope when there is one.
    private var results: [VaultNode] {
        guard let v = vault, !search.isEmpty else { return [] }
        return v.notes(in: scope?.url).filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    /// The parent folder's path under the vault root, "/"-joined; "Knowledge Base" at the top level.
    private func folder(of node: VaultNode) -> String {
        guard let root = vault?.root else { return "" }
        let parent = node.url.deletingLastPathComponent().standardizedFileURL.pathComponents
        let base = root.standardizedFileURL.pathComponents
        let rel = parent.count > base.count ? parent[base.count...].joined(separator: "/") : ""
        return rel.isEmpty ? "Knowledge Base" : rel
    }

    private var countText: String {
        let n = vault?.noteCount(in: scope?.url) ?? 0
        return "\(n) note\(n == 1 ? "" : "s")"
    }

    @ViewBuilder private func noteMenu(_ url: URL) -> some View {
        Button("Reveal in Finder") { onReveal(url) }
        if url != vault?.readme {
            Divider()
            Button("Move to Trash", role: .destructive) { onTrash(url) }
        }
    }
}

// MARK: - Tree rows

/// One outline node: a folder disclosing its children, or a selectable note (tagged by URL).
private struct KnowledgeTreeRow: View {
    let node: VaultNode
    @Binding var expanded: Set<URL>
    let onCreate: (_ folder: Bool, _ parent: URL?) -> Void
    let onTrash: (URL) -> Void
    let onReveal: (URL) -> Void

    var body: some View {
        if node.isFolder {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded.contains(node.url) },
                set: { open in if open { expanded.insert(node.url) } else { expanded.remove(node.url) } }
            )) {
                ForEach(node.children, id: \.url) { child in
                    KnowledgeTreeRow(node: child, expanded: $expanded,
                                     onCreate: onCreate, onTrash: onTrash, onReveal: onReveal)
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .lineLimit(1)
                    .contextMenu {   // create INSIDE this folder
                        Button("New Note…") { onCreate(false, node.url) }
                        Button("New Folder…") { onCreate(true, node.url) }
                        Divider()
                        revealAndTrash
                    }
            }
        } else {
            Label(node.name, systemImage: "doc.text")
                .lineLimit(1)
                .tag(node.url)
                .contextMenu { revealAndTrash }
        }
    }

    @ViewBuilder private var revealAndTrash: some View {
        Button("Reveal in Finder") { onReveal(node.url) }
        Divider()
        Button("Move to Trash", role: .destructive) { onTrash(node.url) }
    }
}

// MARK: - Scope helpers (NAV-SPEC 4)

extension KnowledgeVault {
    /// The folder at `url` anywhere in the tree (compared by standardized path), or nil.
    func folder(at url: URL) -> VaultNode? {
        let path = url.standardizedFileURL.path
        func find(_ nodes: [VaultNode]) -> VaultNode? {
            for node in nodes where node.isFolder {
                if node.url.standardizedFileURL.path == path { return node }
                if let hit = find(node.children) { return hit }
            }
            return nil
        }
        return find(nodes)
    }

    /// The notes inside `folder`'s subtree in `allNotes` order; every note when `folder` is nil.
    func notes(in folder: URL?) -> [VaultNode] {
        guard let folder else { return allNotes }
        return allNotes.filter { Self.url($0.url, isInside: folder) }
    }

    /// "<n> notes": the vault's titled notes unscoped (today's count), the subtree's notes scoped.
    func noteCount(in folder: URL?) -> Int {
        folder == nil ? titleIndex.count : notes(in: folder).count
    }

    /// The note a scoped page opens: a README or index directly in the folder, else the folder's
    /// first own note, else the first note deeper in it (list order); nil for an empty folder.
    func landingNote(in folder: VaultNode) -> URL? {
        let own = folder.children.filter { !$0.isFolder }
        let index = own.first { ["readme", "index"].contains($0.name.lowercased()) }
        if let url = (index ?? own.first)?.url { return url }
        for child in folder.children where child.isFolder {
            if let url = landingNote(in: child) { return url }
        }
        return nil
    }

    /// True when `url` lies anywhere below `folder`.
    static func url(_ url: URL, isInside folder: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
    }

    /// The same folder, however its URL was spelled (a trailing slash, `..`); nil equals nil.
    static func sameFolder(_ a: URL?, _ b: URL?) -> Bool {
        a?.standardizedFileURL.path == b?.standardizedFileURL.path
    }
}
