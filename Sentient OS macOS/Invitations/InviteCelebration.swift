// The verified invitation's gift sheet: a 72 pt gift tile with one bounce, a bold title, one
// sentence, a flat pass once claimed, and Close / Continue. It follows the system appearance and
// sizes itself as a form sheet, so every caller presents it with `.sheet` and no frame of its own.
// Presentation only: claiming or dismissing never changes the server-confirmed entitlement.
// Doc: ../Views/Onboarding/Documentation - Onboarding.md

import SwiftUI

struct InviteCelebration: View {
    let ticketNamespace: Namespace.ID
    var lateGift = false
    var upgrade = false
    var continueTitle = "Continue setup"
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var arrived = false
    @State private var ready = false
    @State private var claimed = false
    @State private var bounceTick = 0
    @FocusState private var claimFocused: Bool

    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }

    var body: some View {
        VStack(spacing: Space.l) {
            ZStack(alignment: .bottomTrailing) {
                IconTile(.inviteCelebration, size: 72)
                    .symbolEffect(.bounce, value: bounceTick)
                if claimed || upgrade {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .offset(x: 6, y: 6)
                        .accessibilityHidden(true)
                }
            }
            .padding(.bottom, Space.xs)

            VStack(spacing: Space.s) {
                // The late gift's title already says its kicker, so it is not repeated above it.
                if !claimed && !lateGift {
                    Text(kicker)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The pass slot. Before the reveal settles, the onboarding ticket hands off into the
            // sheet through matched geometry; the claimed pass appears only after the claim.
            ZStack {
                if !reduceMotion && !ready {
                    InviteTicketFace()
                        .matchedGeometryEffect(id: "invite-ticket", in: ticketNamespace)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
                if claimed {
                    InviteTicketFace(claimed: true, lateGift: lateGift)
                        .transition(.opacity)
                }
            }
            .frame(width: 320)

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.m) {
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(closeLabel)
                Button(primaryTitle) {
                    if claimed { onClose() } else { claim() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .focused($claimFocused)
                .disabled(!ready)
            }
            .controlSize(.large)
            .padding(.top, Space.xs)
        }
        .opacity(arrived ? 1 : 0)
        .frame(maxWidth: 440)
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationSizing(.form)
        .onExitCommand(perform: onClose)
        .task { await reveal() }
    }

    // MARK: - Sequence

    private func reveal() async {
        if reduceMotion {
            arrived = true
            ready = true
            claimFocused = true
            return
        }
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reduceMotion)) { arrived = true }
        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reduceMotion)) { ready = true }
        // One bounce, only when motion is allowed (Reduce Motion, the override and Low Power Mode stop it).
        if Motion.gated(Motion.standard, reduceMotion: reduceMotion) != nil { bounceTick += 1 }
        claimFocused = true
    }

    private func claim() {
        guard ready, !claimed else { return }
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reduceMotion)) { claimed = true }
    }

    // MARK: - Copy

    private var kicker: String {
        upgrade ? "A gift for our early supporters" : "Some things are yours forever"
    }

    private var title: String {
        if lateGift { return claimed ? "Enjoy Sentient!" : "A Little Something, Just for You" }
        if claimed { return "All Yours. For Life." }
        return upgrade ? "You’ve Been Upgraded" : "Sentient OS, Yours for Life"
    }

    private var message: String {
        if lateGift {
            return claimed ? "A couple of weeks of unlimited Sidekick, on us."
                           : InviteLateUse.message + "\n— Jesai & Aditya"
        }
        if claimed {
            return upgrade ? "Your upgrade is already saved. Thanks for being here early."
                           : "Thanks for being here early."
        }
        return upgrade ? "Your lifetime access is already unlocked." : "Lifetime access, reserved for you."
    }

    private var primaryTitle: String {
        if claimed { return continueTitle }
        if lateGift { return "Enjoy Sentient!" }
        return upgrade ? "See My Lifetime Pass" : "Claim Lifetime Access"
    }

    private var caption: String {
        if lateGift { return "Your Sidekick gift is saved. Make yourself at home." }
        if claimed { return "Your lifetime pass is saved. Make yourself at home." }
        return upgrade ? "We’ve upgraded your earlier gift to free lifetime access."
                       : "Sentient OS, free for life. A gift from us to you."
    }

    private var closeLabel: String {
        lateGift ? "Close invitation. Your Sidekick gift is saved."
                 : "Close invitation. Lifetime access is saved."
    }
}

#if DEBUG
private struct InviteCelebrationPreview: View {
    @Namespace private var ticket
    var lateGift = false
    var body: some View {
        InviteCelebration(ticketNamespace: ticket, lateGift: lateGift, onClose: {})
            .frame(width: 520, height: 600)
    }
}
#Preview("Lifetime invitation") {
    HStack(spacing: 0) {
        InviteCelebrationPreview().environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor))
        InviteCelebrationPreview().environment(\.colorScheme, .dark)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
#Preview("Late gift") {
    HStack(spacing: 0) {
        InviteCelebrationPreview(lateGift: true).environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor))
        InviteCelebrationPreview(lateGift: true).environment(\.colorScheme, .dark)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
