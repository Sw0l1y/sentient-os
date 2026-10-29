//
//  PageSubtitle.swift
//  Sentient OS macOS
//
//  Pages publish their window subtitle into MainNavigation; the root shows the current page's
//  (SPEC-00 3.13, 5.3). No page sets `.navigationTitle` or `.navigationSubtitle` itself.
//

import SwiftUI

extension View {
    /// Publishes this page's window subtitle into MainNavigation (5.3). Safe on retained pages: it never
    /// clears on disappear, and the root reads only the current page's subtitle.
    func pageSubtitle(_ text: String?, page: MainNavigation.Page, pane: SettingsView.Pane? = nil) -> some View {
        onChange(of: text, initial: true) { _, newText in
            MainNavigation.shared.setSubtitle(newText, for: page, pane: pane)
        }
    }
}
