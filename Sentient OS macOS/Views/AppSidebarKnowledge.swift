// The sidebar's Knowledge section data (NAV-SPEC 1.3): one row per top-level vault folder, with
// the number of notes in its subtree and a monochrome symbol picked by keyword. Scanned off the
// main thread and published on it; publishing only when the list changed, so a refresh that finds
// nothing new costs no re-render.
//
// The scan mirrors KnowledgeVault.load()'s rules (Views/Knowledge/VaultTree.swift): hidden entries
// and Double Tap's writing-samples file are skipped, folders sort by localizedStandardCompare, and
// a note is a `.md` file. It is a separate walk only because KnowledgeVault is main-actor isolated
// under this target's default isolation (and that file is compiled standalone by
// test_knowledge_retention.py, so it is not edited here). Folder URLs come from the same
// `contentsOfDirectory` call, so they equal KnowledgeVault's node URLs and can be compared with
// `MainNavigation.knowledgeScope`.

import Foundation
import Observation

/// One top-level vault folder, as the sidebar shows it.
nonisolated struct AppSidebarDomain: Hashable, Identifiable, Sendable {
    let url: URL
    let name: String
    /// Notes (`.md` files) anywhere in the folder's subtree.
    let noteCount: Int

    var id: URL { url }

    /// The row's symbol: the first keyword group (in NAV-SPEC order) that the folder name contains,
    /// case-insensitively; `folder` otherwise.
    var symbol: String { Self.symbol(for: name) }

    static let keywordSymbols: [(keywords: [String], symbol: String)] = [
        (["people", "relationship", "family", "friends"], "person.2"),
        (["project", "work", "job", "career"], "briefcase"),
        (["education", "school", "study", "learning", "class"], "graduationcap"),
        (["health", "medical", "fitness"], "heart"),
        (["cooking", "food", "recipe"], "fork.knife"),
        (["travel", "trip"], "airplane"),
        (["money", "finance"], "creditcard"),
        (["home", "house"], "house.lodge"),
        (["logistics", "calendar", "schedule"], "calendar"),
        (["code", "software", "dev"], "chevron.left.forwardslash.chevron.right"),
    ]

    static func symbol(for name: String) -> String {
        let lowered = name.lowercased()
        for group in keywordSymbols where group.keywords.contains(where: { lowered.contains($0) }) {
            return group.symbol
        }
        return "folder"
    }
}

/// The file walk. Pure and nonisolated, so it runs on a background task.
nonisolated enum AppSidebarVaultScan {
    /// Top-level folders of `root` in the vault's order, each with its subtree's note count.
    /// Empty when the vault does not exist yet.
    static func domains(root: URL, skippingFile skipped: String) -> [AppSidebarDomain] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return [] }

        func entries(_ dir: URL) -> [(url: URL, isFolder: Bool)] {
            let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles])) ?? []
            return items.compactMap { url in
                let name = url.lastPathComponent
                if name.hasPrefix(".") { return nil }
                if name.caseInsensitiveCompare(skipped) == .orderedSame { return nil }
                let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return (url, isFolder)
            }
        }

        func noteCount(_ dir: URL) -> Int {
            entries(dir).reduce(0) { total, entry in
                if entry.isFolder { return total + noteCount(entry.url) }
                return total + (entry.url.pathExtension.lowercased() == "md" ? 1 : 0)
            }
        }

        return entries(root)
            .filter { $0.isFolder }
            .map { AppSidebarDomain(url: $0.url, name: $0.url.lastPathComponent, noteCount: noteCount($0.url)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// The published list the sidebar reads. One shared instance: the sidebar is the only reader.
@MainActor
@Observable
final class AppSidebarKnowledge {
    static let shared = AppSidebarKnowledge()

    private(set) var domains: [AppSidebarDomain] = []

    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var pending = false

    /// Rescans the vault off the main thread. Calls made while a scan runs coalesce into one
    /// more scan after it, so the last change is never missed.
    func refresh() {
        guard !scanning else { pending = true; return }
        scanning = true
        pending = false
        let root = VaultGenerator.vaultRoot
        let skipped = WritingStyle.fileName
        Task {
            let found = await Task.detached(priority: .utility) {
                AppSidebarVaultScan.domains(root: root, skippingFile: skipped)
            }.value
            if found != domains { domains = found }
            scanning = false
            if pending { refresh() }
        }
    }
}
