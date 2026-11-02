// SchoolFeedSource.swift
// The School source: the student's Schoology calendar feed (Settings › Account Settings ›
// Share Your Schoology Calendar › Enable › the iCal link). Sentient never signs in to Schoology,
// ALEKS or Savvas and never stores a school password; work posted with a due date reaches the
// feed, and the feed is all Sentient reads.
//  - The link is a bearer secret. It lives ONLY in the Keychain (service below, this device only,
//    never synced). UserDefaults holds non-secret state: connected, count, last refresh, issue.
//    No log line, report, note, prompt or error text carries it (SchoolFeedFetch, SchoolFeedLink).
//  - Each analysis reads the feed once (IterativeRun+School), saves a replaceable snapshot here,
//    replaces the School notes in the cycle store and the vault's School folder. A failed read
//    keeps the previous snapshot and is retried on the next analysis.
// Doc: Documentation - Sources - Local (Files, WhatsApp, iMessage, Notes).md

import Foundation
import Security
import LocalAuthentication

nonisolated enum SchoolFeedSource {
    /// The source's one name: the Knowledge Sources row, the run's issues and the report.
    static let name = "Schoology"
    static let bucketKey = "school-feed"
    static let connectedKey = "schoolFeed.schoology.connected"
    static let countKey = "schoolFeed.schoology.count"
    static let refreshedKey = "schoolFeed.schoology.refreshedAt"
    static let issueKey = "schoolFeed.schoology.issue"
    private static let service = "ai.sentient-os.app.school-feed.v1"
    private static let account = "schoology"

    /// Selected for analysis. Cheap (no Keychain read), so selection counts can use it freely.
    static var isConnected: Bool { UserDefaults.standard.bool(forKey: connectedKey) }

    enum ReadError: Error, Equatable {
        case missingLink
        case keychain(Int32)
        case storage
    }

    // MARK: Keychain (the link)

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The saved link, or nil when none is saved. Never shows a Keychain prompt.
    static func readLink() throws -> URL? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        // A background analysis must never put up a Keychain dialog: fail instead (reported as a
        // missing link, which the user fixes by pasting it again).
        let context = LAContext()
        context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ReadError.keychain(status) }
        guard let data = value as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        return SchoolFeedLink.normalize(text)
    }

    static func saveLink(_ link: URL) throws {
        let data = Data(link.absoluteString.utf8)
        var status = SecItemUpdate(query() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query()
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            q[kSecAttrSynchronizable as String] = false
            q[kSecAttrLabel as String] = "Sentient · Schoology calendar link"
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ReadError.keychain(status) }
    }

    @discardableResult
    static func deleteLink() -> Bool {
        let status = SecItemDelete(query() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: The saved snapshot

    private static var storeURL: URL {
        URL.sentientSupport.appendingPathComponent("School Feed", isDirectory: true)
            .appendingPathComponent("schoology-snapshot.json")
    }

    /// The last complete read (no link inside), or nil.
    static func savedSnapshot() -> SchoolSnapshot? {
        guard let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(SchoolSnapshot.self, from: data),
              snapshot.version == SchoolSnapshot.currentVersion else { return nil }
        return snapshot
    }

    static func saveSnapshot(_ snapshot: SchoolSnapshot) throws {
        let folder = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(snapshot).write(to: storeURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }

    static func clearSnapshot() {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }

    // MARK: Status (no link)

    /// Why the last read did not finish. "" or missing: it did.
    enum Issue: String {
        case revoked, unreachable, server, tooLarge, missingLink, storage

        /// The user must act (paste a new link, or tell the team); a network blip is not that.
        var needsAttention: Bool { self != .unreachable && self != .server }
    }

    static func issue(for error: Error) -> Issue {
        switch error {
        case let failure as SchoolFeedFetch.Failure:
            switch failure {
            case .invalidLink, .revoked, .notCalendar: return .revoked
            case .tooLarge: return .tooLarge
            case .server: return .server
            case .unreachable: return .unreachable
            }
        case ReadError.missingLink, ReadError.keychain: return .missingLink
        default: return .storage
        }
    }

    /// The sentence the Knowledge Sources sheet and the Analysis page show.
    static func issueMessage(_ code: String) -> String? {
        switch Issue(rawValue: code) {
        case .revoked: "Schoology stopped sharing your calendar. Turn sharing on again and paste the new link."
        case .unreachable: "Sentient couldn’t reach Schoology during the last analysis. Your last assignment list is kept and checked again next time."
        case .server: "Schoology had a problem sending your calendar. Your last assignment list is kept and checked again next time."
        case .tooLarge: "Your Schoology calendar is larger than 8 MB, so Sentient can’t read it."
        case .missingLink: "Sentient can’t find your Schoology link in the Keychain. Paste the link again."
        case .storage: "Sentient couldn’t save your assignments. Check available disk space, then analyze again."
        case nil: nil
        }
    }

    static func recordSuccess(_ snapshot: SchoolSnapshot, defaults: UserDefaults = .standard) {
        defaults.set(snapshot.assignments.count, forKey: countKey)
        defaults.set(snapshot.capturedAt.timeIntervalSince1970, forKey: refreshedKey)
        defaults.removeObject(forKey: issueKey)
    }

    static func recordIssue(_ issue: Issue, defaults: UserDefaults = .standard) {
        defaults.set(issue.rawValue, forKey: issueKey)
    }

    // MARK: Reading

    /// Read the feed once and build its snapshot. Throws SchoolFeedFetch.Failure for the network
    /// and the feed, CancellationError when stopped. Parsing runs off the main thread.
    static func read(link: URL, now: Date = Date()) async throws -> SchoolSnapshot {
        let text = try await SchoolFeedFetch.fetch(link)
        try Task.checkCancellation()
        return await Task.detached(priority: .utility) {
            SchoolSnapshot.build(ICSParser.parse(text).items, now: now, calendar: .current, feedLink: link)
        }.value
    }

    /// The Knowledge Sources sheet's Connect: check the pasted link by reading it once, then keep
    /// the link (Keychain), the snapshot and the status. Nothing is saved when the read fails.
    static func connect(_ input: String) async throws -> SchoolSnapshot {
        guard let link = SchoolFeedLink.normalize(input) else { throw SchoolFeedFetch.Failure.invalidLink }
        let snapshot = try await read(link: link)
        try saveLink(link)
        try? saveSnapshot(snapshot)
        UserDefaults.standard.set(true, forKey: connectedKey)
        recordSuccess(snapshot)
        return snapshot
    }

    /// Forget the link, the snapshot and the status. The caller also clears the cycle store's
    /// School notes and the vault's School notes (SchoolFeedSource.disconnect in the app).
    static func forget(defaults: UserDefaults = .standard) {
        deleteLink()
        clearSnapshot()
        for key in [connectedKey, countKey, refreshedKey, issueKey] { defaults.removeObject(forKey: key) }
    }

    /// The Connect sheet's sentence for a failed check. Never the link.
    static func connectMessage(_ error: Error) -> String {
        switch error {
        case SchoolFeedFetch.Failure.invalidLink:
            "That isn’t a calendar link. Paste the iCal link, which starts with webcal:// or https://."
        case SchoolFeedFetch.Failure.revoked:
            "Schoology isn’t sharing a calendar at this link. Turn sharing on in Schoology and copy the iCal link again."
        case SchoolFeedFetch.Failure.notCalendar:
            "This link didn’t return a calendar. Copy the iCal link from Share Your Schoology Calendar again."
        case SchoolFeedFetch.Failure.tooLarge:
            "This calendar is larger than 8 MB, so Sentient can’t read it."
        case SchoolFeedFetch.Failure.server:
            "Schoology had a problem sending the calendar. Try again in a few minutes."
        case SchoolFeedFetch.Failure.unreachable:
            "Couldn’t reach that address. Check your internet connection and the link, then try again."
        case ReadError.keychain:
            "Sentient couldn’t save the link in your Keychain. Try again."
        default:
            "Sentient couldn’t check this link. Try again."
        }
    }
}

// MARK: - App side: the vault and the cycle store

extension SchoolFeedSource {
    /// Write the School notes into the live knowledge base when one exists, and schedule its
    /// mirror push. A failure is logged by code only; the notes come back on the next swap.
    @MainActor static func publishToVault(_ snapshot: SchoolSnapshot?) {
        do {
            if try SchoolFeedVault.publish(snapshot, sourceName: name, root: VaultGenerator.vaultRoot) {
                VaultActivity.shared.markChanged()
            }
        } catch {
            Log("SchoolFeed: School notes not written to the knowledge base (\(String(describing: type(of: error))))")
        }
    }

    /// Disconnect: forget the link and everything read from it, and remove the School notes
    /// Sentient wrote (notes the user or the vault architect wrote stay).
    @MainActor static func disconnect() async {
        forget()
        await CycleStore.shared.clearBucket(bucketKey)
        publishToVault(nil)
        Log("SchoolFeed: disconnected")
    }
}
