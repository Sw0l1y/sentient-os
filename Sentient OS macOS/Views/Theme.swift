//
//  Theme.swift
//  Sentient OS macOS
//
//  Retired vocabulary (SPEC-00 4.3). The design language now lives in Views/Design (tokens, tiles,
//  rows) and in the SwiftUI text styles and semantic colors. After the final cleanup (SPEC-00 4.1)
//  only the names that Views/Dev (out of scope) or a lab still reads remain: the deprecated colors
//  and the `Ink` palette, plus `Theme.bg`, `verdictColor`, `GlassCard` /
//  `glassCard` and `Date.glanceStamp`, which may stay. Nothing here forces an appearance: every
//  color is a dynamic system color.
//

import SwiftUI
import AppKit

enum Theme {
    /// The window background. Usually draw nothing instead (the window has it); reading surfaces use
    /// `Color(nsColor: .textBackgroundColor)`. May stay (a lab reads it).
    static let bg = Color(nsColor: .windowBackgroundColor)
    /// The separator.
    @available(*, deprecated, message: "Use Color(nsColor: .separatorColor) or Divider()")
    static let stroke = Color(nsColor: .separatorColor)
    /// Secondary text.
    @available(*, deprecated, message: "Use .secondary")
    static let secondary = Color(nsColor: .secondaryLabelColor)
    /// Tertiary text and placeholders.
    @available(*, deprecated, message: "Use Color(nsColor: .tertiaryLabelColor)")
    static let faint = Color(nsColor: .tertiaryLabelColor)
    /// The accent (AccentColor.colorset, or the user's own accent).
    @available(*, deprecated, message: "Use Color.accentColor")
    static let accent = Color.accentColor

    /// May stay for Views/Dev. Remade files use StatusTone (survivor .ok, junk .off, sensitive .error).
    static func verdictColor(_ v: Verdict) -> Color {
        switch v {
        case .survivor:  return Color(nsColor: .systemGreen)
        case .junk:      return Color(nsColor: .tertiaryLabelColor)
        case .sensitive: return Color(nsColor: .systemRed)
        }
    }

    /// Text and status inks, mapped onto the system's semantic colors (names kept for callers).
    @available(*, deprecated, message: "Use the SPEC-00 2.2 color roles (.primary, .secondary, separatorColor, StatusTone)")
    enum Ink {
        static let cardBG = Color(nsColor: .controlBackgroundColor)
        static let statusInk = Color(nsColor: .labelColor)
        static let body = Color(nsColor: .secondaryLabelColor)
        static let label = Color(nsColor: .tertiaryLabelColor)
        static let deepMuted = Color(nsColor: .quaternaryLabelColor)
        static let bright = Color(nsColor: .labelColor)
        static let green = Color(nsColor: .systemGreen)
        static let amber = Color(nsColor: .systemOrange)
        static let gold = Color(nsColor: .systemYellow)
        static let red = Color(nsColor: .systemRed)
        static let chipInk = Color(nsColor: .secondaryLabelColor)
        static let chipBorder = Color(nsColor: .separatorColor)
    }
}

extension Date {
    /// The glanceable time stamp: today → "3:18 AM" · yesterday → "yesterday 3:18 AM" ·
    /// older → "Jul 12". A formatter, not a look; it stays.
    var glanceStamp: String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(self) { f.dateFormat = "h:mm a"; return f.string(from: self) }
        if Calendar.current.isDateInYesterday(self) { f.dateFormat = "h:mm a"; return "yesterday \(f.string(from: self))" }
        f.dateFormat = "MMM d"
        return f.string(from: self)
    }
}

/// The grouped container fill. `radius` is accepted for call-site compatibility; the corner is
/// `Radius.group`. May stay (dev-only callers); remade files use GroupBox or a Form section.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }
}

extension View {
    func glassCard(radius: CGFloat = 14) -> some View { modifier(GlassCard(radius: radius)) }
}
