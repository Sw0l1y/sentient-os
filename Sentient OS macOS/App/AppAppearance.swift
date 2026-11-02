//
//  AppAppearance.swift
//  Sentient OS macOS
//
//  The app's light/dark choice (Settings › General › Appearance). Dark unless the user picks
//  Light or Auto (follow macOS). The notch is always black and ignores this.
//

import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case auto, light, dark

    static let key = "appearance.mode"
    static let defaultValue: AppAppearance = .dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var current: AppAppearance {
        UserDefaults.standard.string(forKey: key).flatMap(AppAppearance.init(rawValue:)) ?? defaultValue
    }

    /// Applies the stored choice to every window. The QA hook (ADDENDUM 12.6) still wins:
    /// `defaults write <bundle id> dbg.appearance light|dark` forces one for screenshots.
    static func apply() {
        let name: NSAppearance.Name?
        switch UserDefaults.standard.string(forKey: "dbg.appearance") {
        case "light": name = .aqua
        case "dark": name = .darkAqua
        default:
            switch current {
            case .auto: name = nil
            case .light: name = .aqua
            case .dark: name = .darkAqua
            }
        }
        NSApplication.shared.appearance = name.flatMap(NSAppearance.init(named:))
    }
}
