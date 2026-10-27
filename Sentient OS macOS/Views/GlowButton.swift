//
//  GlowButton.swift
//  Sentient OS macOS
//
//  The primary CTA ("Start Analysis", "Update Now", …) — an accent-tinted Liquid Glass capsule
//  (GlassButtonStyle, prominent). It used to sit on a rotating rainbow conic halo; the halo is now
//  a still, soft accent bloom (GlowHalo) so the app speaks one design language and the CTA costs
//  no per-frame rendering. Inactive = plain glass, dimmed, no bloom.
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
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GlassButtonStyle(prominent: active, tint: colors?.first))
        .controlSize(.large)
        .background(GlowHalo(active: active, colors: colors, intensity: glowIntensity * 0.5))
        .disabled(!active)
        .animation(.easeInOut(duration: 0.4), value: active)
    }
}

/// The glow CTA's quiet sibling — a plain glass capsule for the visible-but-subordinate choice
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

/// A still, soft accent bloom behind a capsule. Formerly a 30fps rotating rainbow; `period`,
/// `reversed` and `animating` are accepted for call-site compatibility and ignored.
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

    var body: some View {
        GeometryReader { geo in
            Capsule(style: .continuous)
                .fill(colors?.first ?? Theme.accent)
                .frame(width: geo.size.width + 24, height: geo.size.height + 24)
                .blur(radius: 22)
                .offset(x: -12, y: -12)
                .opacity(active ? intensity : 0)
                .animation(.easeInOut(duration: 0.6), value: active)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
