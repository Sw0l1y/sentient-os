// In-window navigation, shared by Home, menu commands, notifications, and setup recovery.
// The route is intentionally session-only: each normal launch starts at Home. Only the last
// Settings pane is remembered across launches (for Settings… ⌘,).

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
        case .knowledge: return "Knowledge"
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

    func show(_ page: Page, settingsPane: SettingsView.Pane? = nil) {
        let token = resetToken
        let proceed = { [self] in
            guard resetToken == token else { return }
            if let settingsPane { self.settingsPane = settingsPane }
            if page == .knowledge { hasOpenedKnowledge = true }
            if self.page != page { previousPage = self.page }
            self.page = page
        }
        if self.page == .knowledge, page != .knowledge, let leaveKnowledge {
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
    }

}
