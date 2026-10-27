//
//  Theme.swift
//  Sentient OS macOS
//
//  The Sentient OS visual language — one place so the app stays consistent. It is macOS's own:
//  system window and control backgrounds, semantic label colors, SF type, the user's accent color,
//  standard controls. The app runs in dark appearance; every token below is a dynamic system color,
//  so nothing here hard-codes a black or a gray.
//

import SwiftUI

enum Theme {
    static let bg = Color(nsColor: .windowBackgroundColor)
    /// The Knowledge sidebar surface — moonlit slate: near-neutral graphite with a whisper of cool
    /// blue (b > g > r), so the folder panel reads as night-sky chrome and recedes behind the
    /// reading pane. (The old warm-orange panel read as a Claude-ism.)
    static let panel = Color(nsColor: .underPageBackgroundColor)
    static let elevated = Color(nsColor: .quaternarySystemFill)
    static let stroke = Color(nsColor: .separatorColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let faint = Color(nsColor: .tertiaryLabelColor)
    /// The ONE accent: the Mac's own accent color (System Settings › Appearance), so the app reads
    /// as part of macOS. Every glow, tint, selection and prominent control derives from it.
    static let accent = Color.accentColor
    /// The Knowledge window's interactive accent — the same single accent (selected rows, tints,
    /// carets). Color means "alive/tappable" here; everything else stays neutral ink.
    static let knowledgeAccent = accent

    /// Shades of the accent, light → base → deep → back, for anything that used to cycle through a
    /// rainbow. Index-compatible with the old 7–8 stop palettes so callers keep working.
    static let accentRamp: [Color] = {
        let base = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        func shade(_ f: CGFloat) -> Color {
            Color(nsColor: (f >= 0 ? base.blended(withFraction: f, of: .white)
                                   : base.blended(withFraction: -f, of: .black)) ?? base)
        }
        return [shade(0.45), shade(0.25), shade(0), shade(-0.12), shade(-0.25), shade(-0.12), shade(0.12), shade(0.45)]
    }()

    /// The wikilink color — a plain, minimalist sky blue (#6fb6ff). Deliberately a solid, honest
    /// web-link blue: gradient text reads as AI-generated, single claimed hues read as other
    /// brands; sky blue on a night-sky surface reads as ours.
    static let knowledgeLink = Color(nsColor: .linkColor)

    /// The sky's "changed last night" shimmer — dawn cyan.
    static let dawnCyan = Color(nsColor: .systemTeal)

    /// The vault CTA glow — formerly a teal→purple rainbow, now the single accent's shades.
    static var magicGlow: [Color] { Array(accentRamp.prefix(7)) }

    static func verdictColor(_ v: Verdict) -> Color {
        switch v {
        case .survivor:  return Ink.green
        case .junk:      return Color(nsColor: .tertiaryLabelColor)
        case .sensitive: return Color(nsColor: .systemRed)
        }
    }

    static func verdictLabel(_ v: Verdict) -> String {
        switch v {
        case .survivor:  return "kept"
        case .junk:      return "junk"
        case .sensitive: return "sensitive"
        }
    }

    /// Text and status inks, mapped onto the system's semantic colors (names kept for callers).
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

/// A small section label — SF semibold in the given color, written as the string is cased.
/// (Formerly a monospaced all-caps "whisper"; the name stays for its many callers.)
struct MonoCaps: View {
    let text: String
    let size: CGFloat
    let color: Color
    let weight: Font.Weight

    init(_ text: String, size: CGFloat, tracking: CGFloat = 0, color: Color, weight: Font.Weight = .semibold) {
        self.text = text
        self.size = size
        self.color = color
        self.weight = weight == .medium || weight == .regular ? .semibold : weight
    }

    var body: some View {
        Text(text)
            .font(Font.textStyle(near: max(size + 1.5, 11)).weight(weight))
            .foregroundStyle(color)
    }
}

extension Font {
    /// The system text style nearest a legacy point size, so old call sites land on Dynamic Type
    /// styles (macOS sizes: largeTitle 26 · title 22 · title2 17 · title3 15 · body 13 ·
    /// callout 12 · subheadline 11 · caption 10).
    static func textStyle(near size: CGFloat) -> Font {
        switch size {
        case 24...: .largeTitle
        case 20..<24: .title
        case 16.5..<20: .title2
        case 14.5..<16.5: .title3
        case 12.5..<14.5: .body
        case 11.5..<12.5: .callout
        case 10.5..<11.5: .subheadline
        case 9.5..<10.5: .caption
        default: .caption2
        }
    }
}

extension Date {
    /// The whisper voice's glanceable time stamp — today → "3:18 AM" · yesterday →
    /// "yesterday 3:18 AM" · older → "Jul 12". Rides the home's "Last run:" line and the
    /// Connect-AIs pill's synced time (MonoCaps uppercases it in place).
    var glanceStamp: String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(self) { f.dateFormat = "h:mm a"; return f.string(from: self) }
        if Calendar.current.isDateInYesterday(self) { f.dateFormat = "h:mm a"; return "yesterday \(f.string(from: self))" }
        f.dateFormat = "MMM d"
        return f.string(from: self)
    }
}

/// Press feedback for custom (non-bordered) buttons: the system's dim-on-press, not a bounce.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    /// Titles — the nearest system text style in bold, the way macOS sets a pane title.
    func display(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        font(Font.textStyle(near: size).weight(weight == .medium ? .bold : weight))
    }
}

/// The grouped-content surface (System Settings' rounded row group) used by cards across the app.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(.quinary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func glassCard(radius: CGFloat = 14) -> some View { modifier(GlassCard(radius: radius)) }
}

/// Small color-coded verdict badge (kept / junk / sensitive).
struct VerdictBadge: View {
    let verdict: Verdict
    var body: some View {
        Text(Theme.verdictLabel(verdict).uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Theme.verdictColor(verdict))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.verdictColor(verdict).opacity(0.14), in: Capsule())
    }
}

/// "Sensitive" — red pill for items that must never leave the device.
struct SensitivePill: View {
    private static let red = Color(red: 1.0, green: 0.45, blue: 0.45)
    var body: some View {
        Label("Sensitive", systemImage: "lock.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Self.red)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Self.red.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Self.red.opacity(0.45), lineWidth: 1))
    }
}

/// "Junk" — a clear (but neutral) flag for low-value files that won't be kept.
struct JunkPill: View {
    var body: some View {
        Label("Junk", systemImage: "trash")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.10)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
    }
}
