#!/usr/bin/env python3
"""Exercise the production MainNavigation route state without launching the app.

Compiles App/MainNavigation.swift whole with a fixture that stubs only the Settings pane enum and
UserDefaults (so the remembered pane is checked in memory and no real preferences are written).
No user data, provider calls, UI automation, or copied routing logic.

The page-reveal geometry, HomePageEntrance and animates*Transition checks were retired with their
subjects: d29bd56 deleted Views/Settings/SettingsPageTransition.swift (the reveal, HomePageEntrance
and both animation flags) and the one-window shell has no page transition (ADDENDUM 12.3).
"""
from pathlib import Path
import subprocess
from swift_fixture import platform_plugin_flags
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "Sentient OS macOS"
FIXTURE = r'''
import Foundation

enum SettingsView {
    enum Pane: CaseIterable {
        case sources, frontierModel, doubleTap, proactive, shareKnowledge, system, health
        var title: String { "pane:" + String(describing: self) }
    }
}

/// Shadows Foundation.UserDefaults inside this module, so MainNavigation's remembered pane lives in
/// memory for the run and never touches a real defaults domain.
final class UserDefaults {
    static let standard = UserDefaults()
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

@main @MainActor struct SettingsTransitionChecks {
    static var checks = 0
    static var failures: [String] = []
    static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
        checks += 1
        if !condition() { failures.append(description); print("FAIL: " + description) }
    }

    static func routingChecks() {
        let nav = MainNavigation()
        check(nav.page == .home && nav.previousPage == nil && !nav.hasOpenedKnowledge, "fresh route invented history")
        nav.show(.home)
        check(nav.page == .home && nav.previousPage == nil, "initial same-page request invented route history")
        nav.show(.settings, settingsPane: .proactive)
        check(nav.page == .settings && nav.previousPage == .home, "Home to Settings did not route")
        check(nav.settingsPane == .proactive, "Settings deep link lost its pane")
        nav.show(.settings, settingsPane: .health)
        check(nav.page == .settings && nav.previousPage == .home && nav.settingsPane == .health,
              "same-page Settings request changed prior route or lost pane")
        nav.show(.home)
        check(nav.previousPage == .settings && nav.page == .home, "Settings to Home did not route back")
        nav.show(.home)
        check(nav.previousPage == .settings, "same-page Home request overwrote actual previous route")
        nav.show(.knowledge)
        check(nav.page == .knowledge && nav.previousPage == .home && nav.hasOpenedKnowledge,
              "Home to Knowledge lost its route or the opened flag")
        nav.show(.settings, settingsPane: .frontierModel)
        check(nav.page == .settings && nav.previousPage == .knowledge && nav.settingsPane == .frontierModel,
              "Knowledge to Settings lost its route or pane")
        nav.show(.knowledge)
        check(nav.page == .knowledge && nav.previousPage == .settings, "Settings to Knowledge lost its route")
        nav.show(.home)
        check(nav.page == .home && nav.previousPage == .knowledge, "Knowledge to Home lost its route")

        var pending: ((Bool) -> Void)?
        var guardCalls = 0
        nav.show(.knowledge)
        nav.leaveKnowledge = { completion in guardCalls += 1; pending = completion }
        nav.show(.settings, settingsPane: .system)
        check(guardCalls == 1 && pending != nil, "Settings bypassed dirty Knowledge leave guard")
        check(nav.page == .knowledge && nav.previousPage == .home && nav.settingsPane == .frontierModel,
              "deferred request changed route or pane before approval")
        pending?(false); pending = nil
        check(nav.page == .knowledge && nav.previousPage == .home,
              "cancelled Knowledge navigation changed the route")
        check(nav.settingsPane == .frontierModel, "cancelled deep link changed Settings selection")
        nav.show(.settings, settingsPane: .system)
        pending?(true); pending = nil
        check(nav.page == .settings && nav.previousPage == .knowledge && nav.settingsPane == .system,
              "approved Knowledge navigation chose wrong route/pane")
        nav.show(.home)
        check(guardCalls == 2 && nav.page == .home && nav.previousPage == .settings,
              "Home return invoked an inactive Knowledge guard")
        var immediate: Bool?
        nav.confirmLeavingKnowledge { immediate = $0 }
        check(immediate == true && guardCalls == 2, "non-Knowledge close guard did not allow immediately")
        nav.show(.knowledge)
        nav.confirmLeavingKnowledge { immediate = $0 }
        check(guardCalls == 3 && pending != nil && nav.page == .knowledge, "close confirmation bypassed Knowledge guard")
        pending?(false); pending = nil
        check(immediate == false && nav.page == .knowledge, "cancelled close confirmation mutated navigation")
        nav.show(.knowledge)
        check(guardCalls == 3 && nav.previousPage == .home, "Knowledge no-op requested destructive leave confirmation")

        // A Save/Discard sheet can outlive teardown. Its retained completion must not
        // resurrect the destination or mutate the new session's selected Settings pane.
        nav.show(.settings, settingsPane: .health)
        let staleApproval = pending
        check(staleApproval != nil && nav.page == .knowledge, "reset fixture did not retain a deferred Knowledge approval")
        nav.reset()
        staleApproval?(true); pending = nil
        check(nav.page == .home && nav.previousPage == nil, "reset or stale approval preserved route history")
        check(nav.settingsPane == .sources && !nav.hasOpenedKnowledge && nav.leaveKnowledge == nil,
              "reset or stale approval kept previous pane or Knowledge guard")
        nav.show(.settings, settingsPane: .proactive)
        staleApproval?(true)
        check(nav.page == .settings && nav.previousPage == .home && nav.settingsPane == .proactive,
              "stale approval rewrote a new post-reset navigation")
        nav.reset()
        nav.show(.knowledge)
        check(nav.page == .knowledge && nav.previousPage == .home && nav.hasOpenedKnowledge,
              "explicit Knowledge entrance lost its route")
        nav.reset()
        nav.show(.settings, settingsPane: .health)
        nav.show(.settings)
        check(nav.page == .settings && nav.settingsPane == .health && nav.previousPage == .home,
              "reopening Settings replaced its selected deep link")
        nav.reset()
        nav.show(.home, settingsPane: .doubleTap)
        check(nav.page == .home && nav.previousPage == nil && nav.settingsPane == .doubleTap,
              "pane-only request invented navigation or ignored selection")

        // Reversal is entirely route state, with no delayed completion able to navigate.
        for _ in 0..<20 {
            nav.show(.knowledge)
            check(nav.page == .knowledge && nav.previousPage == .home, "rapid Knowledge opening lost its route")
            nav.show(.home)
            check(nav.page == .home && nav.previousPage == .knowledge, "rapid Knowledge reversal lost its route")
            nav.show(.settings)
            check(nav.page == .settings && nav.previousPage == .home, "rapid Settings opening lost its route")
            nav.show(.home)
            check(nav.page == .home && nav.previousPage == .settings, "rapid Settings reversal lost its route")
        }
        let pages: [MainNavigation.Page] = [.home, .settings, .knowledge, .analysis, .setup]
        for from in pages {
            for to in pages where from != to {
                nav.reset(); nav.show(from); nav.show(to)
                check(nav.page == to && nav.previousPage == from,
                      "route pair \(from) -> \(to) recorded the wrong page or previous page")
                check(nav.hasOpenedKnowledge == (from == .knowledge || to == .knowledge),
                      "route pair \(from) -> \(to) set the Knowledge opened flag wrongly")
            }
        }
    }

    /// The current shell's per-page state: titles, subtitles and the remembered Settings pane.
    static func shellStateChecks() {
        UserDefaults.standard.values = [:]
        let nav = MainNavigation()
        let key = "nav.lastSettingsPane"
        check(nav.lastSettingsPane == .sources, "no stored pane did not fall back to Sources")
        nav.show(.settings, settingsPane: .proactive)
        check(UserDefaults.standard.string(forKey: key) == "proactive" && nav.lastSettingsPane == .proactive,
              "choosing a Settings pane was not remembered")
        nav.show(.home)
        check(nav.lastSettingsPane == .proactive, "leaving Settings forgot the remembered pane")
        nav.reset()
        check(UserDefaults.standard.string(forKey: key) == "sources" && nav.lastSettingsPane == .sources,
              "reset did not remember Sources")
        UserDefaults.standard.set("noSuchPane", forKey: key)
        check(nav.lastSettingsPane == .sources, "an unknown stored pane did not fall back to Sources")

        let titles: [(MainNavigation.Page, String)] = [
            (.home, "Home"), (.knowledge, "Knowledge"), (.analysis, "Analysis"), (.setup, "Finish Setup")
        ]
        for (page, title) in titles {
            nav.reset(); nav.show(page)
            check(nav.title == title, "\(page) title is \(nav.title), expected \(title)")
        }
        nav.show(.settings, settingsPane: .health)
        check(nav.title == SettingsView.Pane.health.title, "Settings title is not its pane's title")

        nav.reset()
        check(nav.subtitle == "", "a page with no subtitle did not read empty")
        nav.setSubtitle("12 notes", for: .knowledge)
        nav.setSubtitle("All settings", for: .settings)
        nav.setSubtitle("Wake at 2 AM", for: .settings, pane: .system)
        check(nav.subtitle == "", "another page's subtitle leaked onto Home")
        nav.show(.knowledge)
        check(nav.subtitle == "12 notes", "Knowledge subtitle was not read back")
        nav.show(.settings, settingsPane: .system)
        check(nav.subtitle == "Wake at 2 AM", "a pane's own subtitle did not win")
        nav.show(.settings, settingsPane: .health)
        check(nav.subtitle == "All settings", "a pane without a subtitle did not fall back to the Settings one")
        nav.setSubtitle(nil, for: .settings)
        check(nav.subtitle == "", "clearing a subtitle left it showing")
    }

    static func main() {
        routingChecks()
        shellStateChecks()
        print("\(checks - failures.count)/\(checks) main navigation route checks passed")
        if !failures.isEmpty { exit(1) }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="sentient-settings-transition-") as temporary:
    root = Path(temporary)
    source = root / "SettingsTransitionChecks.swift"
    source.write_text(FIXTURE)
    binary = root / "checks"
    subprocess.run([
        "xcrun", "swiftc", *platform_plugin_flags(), "-swift-version", "5", "-default-isolation", "MainActor",
        "-strict-concurrency=complete", "-warnings-as-errors", "-parse-as-library",
        str(APP / "App/MainNavigation.swift"), str(source), "-o", str(binary),
    ], check=True, timeout=60)
    subprocess.run([str(binary)], check=True, timeout=30)
