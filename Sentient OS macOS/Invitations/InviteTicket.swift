// Invitation pass: a flat, Wallet-style card that shows a gift code or a saved gift.
// Shared by onboarding's saved-gift badge and the InviteCelebration sheet. It follows the
// system appearance: the secondary background fill, a separator hairline, system text styles.
// Doc: ../Views/Onboarding/Documentation - Onboarding.md

import SwiftUI
import AppKit

/// The pass's colors. Kept as names because onboarding (WP10) still reads them while it migrates;
/// every value is a system color now, so a caller that still uses them follows light and dark.
enum InvitePaper {
    static let light = Color(nsColor: .textBackgroundColor)
    static let shade = Color(nsColor: .underPageBackgroundColor)
    static let ink = Color.primary
}

/// A flat pass: the app icon as its issuer logo (as a Wallet pass shows one) and the header title,
/// a hairline, the value line, then a footer.
/// It sets no width or height of its own, and uses only text styles, so a caller can size it
/// (`.frame(height: 28).scaledToFit()` for onboarding's badge). `compact` drops the footer.
/// A claimed full pass carries no success glyph: it shows only in InviteCelebration, whose gift
/// tile's seal says it once. The compact badge stands alone, so it keeps its seal.
struct InviteTicketFace: View {
    var claimed = false
    var lateGift = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                // 20 pt keeps the compact face inside onboarding's 28 pt badge slot at 0.35 scale.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(headerTitle).font(.headline)
                Spacer(minLength: Space.s)
                if !claimed || compact {
                    InviteStamp(claimed: claimed)
                }
            }
            if !compact {
                InvitePerforation()
            }
            Text(valueLine)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            if !compact {
                HStack(spacing: Space.s) {
                    Text(footerText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !claimed {
                        Spacer(minLength: Space.s)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(Space.l)
        .modifier(InviteTicketMaterial())
        .accessibilityElement(children: .combine)
    }

    private var headerTitle: String {
        guard claimed else { return "Gift Code" }
        return lateGift ? "Sidekick Gift" : "Lifetime Pass"
    }

    // A claimed pass holds facts, not confirmations: what it unlocks, then its term or who gave
    // it. InviteCelebration's title, message and caption around it say none of these.
    private var valueLine: String {
        guard claimed else { return "Have a gift code?" }
        return lateGift ? "Unlimited Sidekick" : "Sentient OS"
    }

    private var footerText: String {
        guard claimed else { return "Enter your code" }
        return lateGift ? "A couple of weeks, on us" : "From Jesai & Aditya"
    }
}

/// The pass's status glyph: a pink gift until claimed, then a green seal (on the compact badge only).
struct InviteStamp: View {
    var claimed = false

    var body: some View {
        Image(systemName: claimed ? "checkmark.seal.fill" : "gift.fill")
            .foregroundStyle(claimed ? Color.green : Color.pink)
            .accessibilityHidden(true)
    }
}

/// The hairline between the pass header and its value.
struct InvitePerforation: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// The pass surface: the system secondary background in the pass shape, with a separator hairline.
/// No gradient, grain or shadow.
struct InviteTicketMaterial: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background.secondary, in: InviteTicketShape())
            .overlay {
                InviteTicketShape()
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

/// The pass outline: a continuous rounded rectangle (the old punched notches are gone).
struct InviteTicketShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .path(in: rect.insetBy(dx: insetAmount, dy: insetAmount))
    }

    func inset(by amount: CGFloat) -> Self {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

#if DEBUG
#Preview("Invitation pass") {
    HStack(spacing: 24) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(spacing: 16) {
                InviteTicketFace()
                InviteTicketFace(claimed: true)
                InviteTicketFace(claimed: true, lateGift: true)
                InviteTicketFace(claimed: true, compact: true)
            }
            .frame(width: 320)
            .padding(24)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
        }
    }
}
#endif
