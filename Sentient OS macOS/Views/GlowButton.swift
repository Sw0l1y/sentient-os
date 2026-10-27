//
//  GlowButton.swift
//  Sentient OS macOS
//
//  The primary CTA ("Start Analysis", "Update Now", …): a large, full-width prominent push button.
//  It used to sit on a rotating rainbow halo; it is now the system's default-button look.
//

import SwiftUI

struct GlowButton: View {
    let title: String
    var systemImage: String = "sparkles"
    var active: Bool = true
    var reversed: Bool = false       // kept for call-site compatibility (the halo no longer spins)
    var colors: [Color]? = nil       // custom bloom color (first entry); nil = the accent
    var glowIntensity: Double = 0.85 // bloom opacity when active (lower = subtler)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle(prominent: true, tint: colors?.first))
        .controlSize(.large)
        .disabled(!active)
    }
}

/// The CTA's quiet sibling — a plain push button for the visible-but-subordinate choice
/// beside it (the crossroads' "continue with just the knowledge base", the free home's
/// "Reset Sentient…"). `large` matches the CTA's height and fills its container, for the one case
/// where the two sit side by side as a row rather than stacked.
struct QuietPillButton: View {
    let title: String
    var large: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: large ? .infinity : nil)
        }
        .buttonStyle(.sentientGlass)
        .controlSize(large ? .large : .regular)
    }
}

/// Formerly an accent bloom behind a capsule; draws nothing now (the native buttons need no glow).
/// Its parameters are accepted for call-site compatibility and ignored.
struct GlowHalo: View {
    let active: Bool
    var reversed: Bool = false
    var colors: [Color]? = nil
    var intensity: Double = 0.85     // bloom opacity when active
    var period: Double = 3.5
    var animating = true

    /// The old warm→cool "AI gradient" stops, now the accent's shades (same count and indices, so
    /// every caller that picked `stops[n]` gets a matching accent tone instead of a rainbow hue).
    static var stops: [Color] { Theme.accentRamp }

    var body: some View { EmptyView() }
}
