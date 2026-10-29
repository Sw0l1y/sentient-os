//
//  DesignTokens.swift
//  Sentient OS macOS
//
//  The design tokens (SPEC-00 Part 2): spacing, radii, page metrics, motion, status tones and the
//  icon-tile palette. Text styles are SwiftUI's own; there are no font tokens.
//  The value types are `nonisolated` so they can be read from any context (a Shape's path, a
//  background task); `Motion` stays on the main actor because `AnyTransition` is not Sendable.
//

import SwiftUI
import AppKit

/// Spacing scale. Page margins are `xl` horizontal and `l` under the toolbar.
nonisolated enum Space {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32, xxxl: CGFloat = 48
}

nonisolated enum Radius {
    static let group: CGFloat = 10      // inset groups outside Forms, RecoveryCard, code boxes
    static let bubble: CGFloat = 18     // user message bubbles
    static let thumbnail: CGFloat = 6   // file thumbnails, video frames
    static let keycap: CGFloat = 8
    /// The continuous corner radius of an icon tile: 20→5 (4.5), 22→5, 30→7, 40→9, 64→14, 72→16.
    static func tile(_ size: CGFloat) -> CGFloat { (size * 0.225).rounded() }
}

/// Page sizes. Not "Layout": that name is SwiftUI's Layout protocol.
nonisolated enum PageMetrics {
    static let readingColumn: CGFloat = 680   // Home, Settings forms
    static let documentColumn: CGFloat = 720  // Knowledge reader
    static let setupPage: CGFloat = 560       // Setup Assistant pages, gates
    static let sidebarMin: CGFloat = 200, sidebarIdeal: CGFloat = 232, sidebarMax: CGFloat = 280
    static let popover: CGFloat = 320
}

/// The only animations the app uses. Every animation goes through `gated`, so Reduce Motion, the
/// Sidekick override and Low Power Mode all turn it off.
enum Motion {
    static let standard = Animation.smooth(duration: 0.25)
    static let quick = Animation.smooth(duration: 0.15)
    static let barInsert = AnyTransition.move(edge: .top).combined(with: .opacity)
    /// nil when Reduce Motion, the Sidekick override, or Low Power Mode asks for stillness.
    /// Callers pass `reduceMotion: motionOverride ?? systemReduced` (the override is a `Bool?`).
    static func gated(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled ? nil : animation
    }
}

/// A status, always shown with its symbol so color is never the only signal.
/// Optional items (Microphone & Speech, Notifications) never use `.error`; their worst is `.warning`.
nonisolated enum StatusTone: Hashable, Sendable {
    case ok, warning, error, info, working, off

    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .error: return .red
        case .info, .working: return .secondary
        case .off: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    /// nil for `.working`: callers show `ProgressView().controlSize(.small)` instead.
    var symbol: String? {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle"
        case .working: return nil
        case .off: return "minus.circle"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .ok: return "OK"
        case .warning: return "Warning"
        case .error: return "Error"
        case .info: return "Information"
        case .working: return "In Progress"
        case .off: return "Off"
        }
    }
}

/// The icon-tile palette: system colors, so tiles adapt to light and dark by themselves.
nonisolated enum TileColor: Hashable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, gray, brown, accent

    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .gray: return .gray
        case .brown: return .brown
        case .accent: return .accentColor
        }
    }
}

#Preview("Status tones") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach([StatusTone.ok, .warning, .error, .info, .working, .off], id: \.self) { tone in
                    HStack(spacing: Space.s) {
                        if let symbol = tone.symbol {
                            Image(systemName: symbol).foregroundStyle(tone.color)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Text(tone.accessibilityLabel)
                    }
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 360)
}
