// In-window navigation, shared by Home, menu commands, notifications, and setup recovery.
// The route is intentionally session-only: each normal launch starts at Home. Only the last
// Settings pane is remembered across launches (for Settings… ⌘,). Knowledge can be scoped to one
// top-level vault folder (a sidebar domain row, NAV-SPEC 3); the Knowledge page reads
// `knowledgeScope`.

import SwiftUI

@MainActor
@Observable
final class MainNavigation {
    static let shared = MainNavigation()

    enum Page: Equatable { case home, settings, knowledge, analysis, setup }
    private(set) var page: Page = .home
    private(set) var previousPage: Page?
    var settingsPane: SettingsView.Pane = .sources {
        didSet { if settingsPane != oldValue { rememberSettingsPane(settingsPane) } }
    }
    private(set) var hasOpenedKnowledge = false

    /// The vault folder Knowledge is scoped to (a sidebar domain row), or nil for All Knowledge.
    /// Set only by a Knowledge route: `showKnowledge(scope:)` sets it, plain `show(.knowledge)`
    /// (⌘2, All Knowledge) clears it, other pages leave it as it was (the retained Knowledge view
    /// keeps its scope while hidden), and `reset()` clears it.
    private(set) var knowledgeScope: URL?

    /// Count of problems Permissions & Health would show; drives the sidebar badge. Written by
    /// HomeView after its HealthCaution probe (1 or 0) and by HealthPane with its bad-row count;
    /// the last writer wins.
    var healthIssueCount: Int = 0

    /// Developer Tools sheet flag (only DEBUG builds set it).
    var showDevTools = false

    /// The window title for the current page.
    var title: String {
        switch page {
        case .home: return "Home"
        case .knowledge: return knowledgeScope?.lastPathComponent ?? "Knowledge"
        case .analysis: return "Analysis"
        case .setup: return "Finish Setup"
        case .settings: return settingsPane.title
        }
    }

    // MARK: Subtitles

    /// Subtitles keyed by page, or by "settings.<pane>" for a Settings pane. Not observed itself:
    /// a write bumps `subtitleRevision`, so only a reader of `subtitle` (the root) re-renders.
    @ObservationIgnored private var subtitles: [String: String] = [:]
    private var subtitleRevision = 0

    /// Window subtitle per page (and per Settings pane). Written by pages through .pageSubtitle(_:page:pane:).
    func setSubtitle(_ text: String?, for page: Page, pane: SettingsView.Pane? = nil) {
        let key = Self.subtitleKey(page, pane: pane)
        guard subtitles[key] != text else { return }
        subtitles[key] = text
        subtitleRevision &+= 1
    }

    /// The current page's (and pane's) subtitle, or "".
    var subtitle: String {
        _ = subtitleRevision
        if page == .settings, let text = subtitles[Self.subtitleKey(.settings, pane: settingsPane)] {
            return text
        }
        return subtitles[Self.subtitleKey(page, pane: nil)] ?? ""
    }

    private static func subtitleKey(_ page: Page, pane: SettingsView.Pane?) -> String {
        if page == .settings, let pane { return "settings.\(String(describing: pane))" }
        return String(describing: page)
    }

    // MARK: Last Settings pane

    private static let lastSettingsPaneKey = "nav.lastSettingsPane"

    /// Last Settings pane, persisted under "nav.lastSettingsPane" as String(describing: pane); read
    /// back by matching SettingsView.Pane.allCases. Updated whenever settingsPane changes.
    var lastSettingsPane: SettingsView.Pane {
        guard let raw = UserDefaults.standard.string(forKey: Self.lastSettingsPaneKey) else { return .sources }
        return SettingsView.Pane.allCases.first { String(describing: $0) == raw } ?? .sources
    }

    private func rememberSettingsPane(_ pane: SettingsView.Pane) {
        UserDefaults.standard.set(String(describing: pane), forKey: Self.lastSettingsPaneKey)
    }

    // MARK: Routing

    /// Knowledge owns its editor and decides whether Save / Discard / Cancel is needed.
    /// External navigation (Dock, menu bar, notifications) uses the same guard as its Home button.
    @ObservationIgnored var leaveKnowledge: ((@escaping (Bool) -> Void) -> Void)?
    @ObservationIgnored private var resetToken = UUID()

    /// Routes to `page`. A plain `.knowledge` request is All Knowledge: it clears the scope.
    func show(_ page: Page, settingsPane: SettingsView.Pane? = nil) {
        route(page, settingsPane: settingsPane, scope: nil)
    }

    /// Opens Knowledge scoped to one vault folder (nil = All Knowledge). Changing the scope while
    /// Knowledge is showing goes through the same unsaved-edit guard as leaving it, because the
    /// page then opens another note.
    func showKnowledge(scope: URL?) {
        route(.knowledge, settingsPane: nil, scope: scope)
    }

    /// Leaves Settings mode (the sidebar's Back row, Esc, ⌘[): back to the page Settings was
    /// opened from, with its Knowledge scope intact, or Home when there is none.
    func leaveSettings() {
        guard page == .settings else { return }
        switch previousPage {
        case .knowledge?: showKnowledge(scope: knowledgeScope)
        case let previous? where previous != .settings: show(previous)
        default: show(.home)
        }
    }

    private func route(_ page: Page, settingsPane: SettingsView.Pane?, scope: URL?) {
        let token = resetToken
        let proceed = { [self] in
            guard resetToken == token else { return }
            if let settingsPane { self.settingsPane = settingsPane }
            if page == .knowledge {
                hasOpenedKnowledge = true
                if knowledgeScope != scope { knowledgeScope = scope }
            }
            if self.page != page { previousPage = self.page }
            self.page = page
        }
        let leavesKnowledge = page != .knowledge || scope != knowledgeScope
        if self.page == .knowledge, leavesKnowledge, let leaveKnowledge {
            leaveKnowledge { approved in if approved { proceed() } }
        } else {
            proceed()
        }
    }

    func confirmLeavingKnowledge(_ completion: @escaping (Bool) -> Void) {
        if page == .knowledge, let leaveKnowledge { leaveKnowledge(completion) }
        else { completion(true) }
    }

    func reset() {
        resetToken = UUID()
        leaveKnowledge = nil
        previousPage = nil
        page = .home
        settingsPane = .sources
        hasOpenedKnowledge = false
        knowledgeScope = nil
    }

}
