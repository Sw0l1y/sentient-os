// SchoolFeedVault.swift
// Writes the School snapshot into the knowledge base as the "School" folder: one note per class
// and a "School" overview (SchoolVaultNotes). Sentient owns only the notes it wrote, listed in a
// hidden manifest in that folder, so a School folder the vault architect or the user already has
// keeps its own notes: a name that is taken gets " (Schoology)" instead of replacing it.
// Three entry points:
//  - publish: after a read, into the live vault, only when a vault already exists (creating the
//    vault folder would make the next analysis update a vault that was never built);
//  - preserve: just before every vault swap (VaultGenerator.swapStagingIntoVault), so a rebuilt
//    or updated vault always carries the current notes and never the architect's edits of them;
//  - ownedPaths: the notes VaultGenerator.vaultFingerprint ignores, so refreshing them never
//    looks like a user edit and never cancels a knowledge base update.
// Foundation only (plus SchoolAssignments.swift), so Scripts/test_school_feed.py compiles it alone.
// Doc: Documentation - Sources - Local (Files, WhatsApp, iMessage, Notes).md

import Foundation

nonisolated enum SchoolFeedVault {
    static let manifestName = ".sentient-school-feed.json"

    nonisolated struct Manifest: Codable, Equatable, Sendable {
        var version = 1
        /// File names (with ".md") inside the School folder that Sentient wrote.
        var files: [String]
    }

    /// Write the notes into `root`/School. Returns false (and writes nothing) when `root` is not
    /// an existing folder. A nil snapshot removes Sentient's notes and keeps everything else.
    @discardableResult
    static func publish(_ snapshot: SchoolSnapshot?, sourceName: String = "Schoology", root: URL,
                        now: Date = Date(), calendar: Calendar = .current) throws -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        try write(snapshot, sourceName: sourceName, folder: root.appendingPathComponent(SchoolVaultNotes.folder, isDirectory: true),
                  now: now, calendar: calendar)
        return true
    }

    /// Make a staged vault carry the current notes: drop the copies it holds (the architect may
    /// have edited them), then write fresh ones from `snapshot`. Never throws: a School problem
    /// must not block the knowledge base swap.
    static func preserve(in staging: URL, snapshot: SchoolSnapshot?, sourceName: String = "Schoology",
                         now: Date = Date(), calendar: Calendar = .current) {
        let folder = staging.appendingPathComponent(SchoolVaultNotes.folder, isDirectory: true)
        try? write(snapshot, sourceName: sourceName, folder: folder, now: now, calendar: calendar)
    }

    /// Vault-relative paths of Sentient's School notes ("School/Algebra II.md").
    static func ownedPaths(in root: URL) -> Set<String> {
        let folder = root.appendingPathComponent(SchoolVaultNotes.folder, isDirectory: true)
        return Set((manifest(in: folder)?.files ?? []).map { SchoolVaultNotes.folder + "/" + $0 })
    }

    static func manifest(in folder: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(manifestName)),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.version == 1 else { return nil }
        // A manifest only ever names plain notes directly in the folder.
        return Manifest(files: manifest.files.filter { isPlainName($0) })
    }

    private static func isPlainName(_ name: String) -> Bool {
        name.hasSuffix(".md") && !name.contains("/") && !name.hasPrefix(".") && name != ".md"
    }

    private static func write(_ snapshot: SchoolSnapshot?, sourceName: String, folder: URL,
                              now: Date, calendar: Calendar) throws {
        let fm = FileManager.default
        let owned = Set(manifest(in: folder)?.files ?? [])
        // The vault's volume is normally case-insensitive: "algebra ii.md" is the owned "Algebra II.md".
        let ownedLower = Set(owned.map { $0.lowercased() })
        guard let snapshot else {
            for name in owned { try? fm.removeItem(at: folder.appendingPathComponent(name)) }
            try? fm.removeItem(at: folder.appendingPathComponent(manifestName))
            if (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? fm.removeItem(at: folder) }
            return
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // Choose every name first, so the overview's [[links]] match the files written.
        var taken = Set<String>()
        func available(_ base: String) -> String {
            var candidate = base, index = 1
            while true {
                let file = candidate + ".md"
                let lower = file.lowercased()
                let occupied = fm.fileExists(atPath: folder.appendingPathComponent(file).path) && !ownedLower.contains(lower)
                if !occupied && !taken.contains(lower) { taken.insert(lower); return candidate }
                index += 1
                candidate = index == 2 ? "\(base) (\(sourceName))" : "\(base) (\(sourceName) \(index - 1))"
            }
        }
        let overview = available(SchoolVaultNotes.overview)
        var names: [String: String] = [:]
        for course in snapshot.courses { names[course] = available(SchoolVaultNotes.baseName(course)) }

        let files = SchoolVaultNotes.render(snapshot, sourceName: sourceName, now: now, calendar: calendar,
                                            overviewName: overview, names: names)
        var written: [String] = []
        for file in files {
            let name = file.name + ".md"
            try Data(file.markdown.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
            written.append(name)
        }
        let writtenLower = Set(written.map { $0.lowercased() })
        for name in owned where !writtenLower.contains(name.lowercased()) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
        let data = try JSONEncoder().encode(Manifest(files: written))
        try data.write(to: folder.appendingPathComponent(manifestName), options: .atomic)
    }
}
