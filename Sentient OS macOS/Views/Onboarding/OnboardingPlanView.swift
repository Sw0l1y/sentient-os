//
//  OnboardingPlanView.swift
//  Sentient OS macOS
//
//  The plan crossroads — the step right behind the frontier-model step (before permissions),
//  and ONLY free/go ChatGPT accounts ever see it: a full plan (plus/pro/team/…, or anything we
//  can't read — fail open) auto-advances before a single pixel renders, and so does a CUSTOM
//  frontier engine (their own endpoint powers everything; the ChatGPT plan is irrelevant even
//  when a stale free/go codex login sits on disk). Free/go users get an honest fork: upgrade to
//  Plus (opens ChatGPT's pricing page, then this screen notices the upgrade on its own via
//  CodexAuth.refreshPlan — the same on-demand token re-mint codex does every 8 days), say they
//  ALREADY upgraded (a confirm, then we simply believe them — CodexAuth.assertedPlus; people
//  upgrade in their own browser and arrive here before any check could prove it), or continue
//  with just the knowledge base (sets CodexAuth.knowledgeBaseOnly, the app-wide limited-mode
//  gate). This screen sets expectations; the real conversion surface is the home's post-reveal
//  preview message, after they've seen the magic.
//

import SwiftUI
import AppKit

struct OnboardingPlanView: View {
    let onContinue: () -> Void
    /// Preview-only: skip the disk probe and render the crossroads for this plan.
    var previewPlan: CodexAuth.Plan? = nil

    private enum Phase { case checking, crossroads, waiting, unlocked }
    @State private var phase: Phase = .checking
    @State private var plan: CodexAuth.Plan?
    @State private var checkingUpgrade = false
    @State private var confirmingUpgrade = false
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    private var planName: String { plan?.displayName ?? "Free" }
    private var motion: Animation? {
        Motion.gated(Motion.standard, reduceMotion: motionOverride ?? systemReduced)
    }

    private static let crossroadsMessage = "Right now, Sentient uses your ChatGPT plan’s Codex frontier model for a small part of its compute. You can still build your private knowledge base from this Mac and offer it to your AIs."

    var body: some View {
        page
            .task {
                // A non-ChatGPT engine (Claude, or a custom endpoint) bypasses the ChatGPT plan
                // entirely (knowledgeBaseOnly already reads false there) — never show the
                // crossroads, whatever the disk claims.
                if previewPlan == nil, ModelBackend.current != .chatgpt {
                    onContinue()
                    return
                }
                // The silent gate: read the claim off disk (no network). Anything but a positive
                // free/go read means this screen isn't for them.
                let current = previewPlan ?? CodexAuth.currentPlan()
                plan = current
                if current?.tier == .limited {
                    Analytics.signal("PlanGate.shown", parameters: ["plan": current?.raw ?? "unknown"])
                    withAnimation(motion) { phase = .crossroads }
                } else {
                    CodexAuth.knowledgeBaseOnly = false
                    onContinue()
                }
            }
            .alert("Are you on ChatGPT Plus?", isPresented: $confirmingUpgrade) {
                Button("Yes, I’m on Plus") { acceptSelfAttestedUpgrade() }
                Button("Wait", role: .cancel) { }
            } message: {
                Text("Sentient will unlock the full experience and take your word for it.\n\nNote that the ChatGPT Go plan does not offer enough Codex use to unlock the full experience.")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // Back from the browser — quietly re-check, and auto-advance if the fresh claim
                // happens to read full. Always silent: the trust button is the real way forward.
                if phase == .waiting { check() }
            }
    }

    /// An offer page in the manner of Setup Assistant's iCloud+ and Apple Arcade pages: a tile,
    /// the plan as the title, the benefits as rows, and the choices in the footer.
    @ViewBuilder private var page: some View {
        switch phase {
        case .checking:
            Color.clear.frame(height: 1)   // invisible: full plans skip this screen entirely

        case .crossroads:
            SetupAssistantPage(tile: .setupChooseAI, title: "You’re on ChatGPT \(planName)",
                               message: Self.crossroadsMessage) {
                VStack(alignment: .leading, spacing: Space.l) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: Space.s) {
                            Label("Proactive mornings: things worth doing, already done", systemImage: "sunrise")
                            Label("Sidekick anywhere: tap right \u{2318} and tell it what to do", systemImage: "command")
                            Label("Gmail, Calendar, and a knowledge base that keeps learning", systemImage: "moon.stars")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.xs)
                    } label: {
                        Text("With ChatGPT Plus").font(.headline)
                    }
                    OnboardingTrustFooter()
                }
            } footer: {
                SetupAssistantFooter(primaryTitle: "Upgrade on ChatGPT…") {
                    HStack(spacing: Space.m) {
                        Button("I’ve Upgraded…") { confirmingUpgrade = true }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        continueFreeButton
                    }
                } primary: {
                    openUpgrade()
                }
            }
            .transition(.opacity)

        case .waiting:
            SetupAssistantPage(tile: .setupChooseAI, title: "Finish Upgrading in Your Browser",
                               message: "This screen notices on its own.") {
                VStack(alignment: .leading, spacing: Space.l) {
                    MonoWaitLine("Waiting for your upgrade…")
                    OnboardingTrustFooter()
                }
            } footer: {
                // The trust path, not a check: the account can read Free here long after a
                // real payment (the refreshed token re-mints from the same stale session),
                // so the button takes the user's word — same confirm as the crossroads'.
                SetupAssistantFooter(primaryTitle: "I’ve Upgraded…") {
                    continueFreeButton
                } primary: {
                    confirmingUpgrade = true
                }
            }
            .transition(.opacity)

        case .unlocked:
            SetupAssistantPage(tile: .setupChooseAI, title: "\(planName) Unlocked") {
                VStack(alignment: .leading, spacing: Space.l) {
                    OnboardingDoneLine("Welcome to the full Sentient.")
                    OnboardingTrustFooter()
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: Actions

    private func openUpgrade() {
        NSWorkspace.shared.open(CodexAuth.upgradeURL)
        withAnimation(motion) { phase = .waiting }
    }

    /// "I've upgraded", confirmed — the trust path, and the ONLY user-driven way forward from
    /// either phase. A real payment can read Free here indefinitely (the refresh POST re-mints
    /// a token from the same stale session — only OpenAI's server knows the truth, and it checks
    /// at exec time), so we take the user's word and move on immediately: full mode, same as a
    /// verified Plus account. The refresh still fires, unawaited — if it lands, the claim on
    /// disk becomes true too and nothing downstream has to lean on the assertion.
    private func acceptSelfAttestedUpgrade() {
        CodexAuth.assertedPlus = true
        CodexAuth.knowledgeBaseOnly = false
        Analytics.signal("PlanGate.selfAttested", parameters: ["plan": plan?.raw ?? "unknown"])
        Task { _ = try? await CodexAuth.refreshPlan() }
        onContinue()
    }

    /// The silent focus-return check — CodexAuth.refreshPlan re-mints the token, and IF the
    /// fresh claim reads full the screen auto-advances. Best-effort only (the claim often stays
    /// stale after a real payment); the user's own way forward is the trust button above, so
    /// this never reports failure. Single in-flight.
    private func check() {
        guard !checkingUpgrade else { return }
        checkingUpgrade = true
        Task {
            defer { checkingUpgrade = false }
            let fresh: CodexAuth.Plan?
            do { fresh = try await CodexAuth.refreshPlan() }
            catch { return }   // network/refresh failure — stay quiet, the trust button carries
            if let fresh { plan = fresh }
            // Fail open like every other gate: an unreadable fresh claim counts as full.
            if fresh?.tier != .limited {
                CodexAuth.knowledgeBaseOnly = false
                Analytics.signal("PlanGate.upgraded")
                withAnimation(motion) { phase = .unlocked }
                try? await Task.sleep(for: .seconds(1.4))
                onContinue()
            }
        }
    }

    /// The escape hatch: an inline link in the footer, visible without competing with the
    /// page's one primary.
    private var continueFreeButton: some View {
        Button("Continue with Knowledge Base Only", action: continueFree)
            .buttonStyle(.link)
    }

    private func continueFree() {
        CodexAuth.knowledgeBaseOnly = true
        Analytics.signal("PlanGate.continuedFree")
        onContinue()
    }
}

#if DEBUG
#Preview("Onboarding — plan crossroads (Free)") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingPlanView(onContinue: {}, previewPlan: CodexAuth.Plan(raw: "free"))
                .frame(width: 900, height: 760)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Onboarding — plan crossroads (Go)") {
    OnboardingPlanView(onContinue: {}, previewPlan: CodexAuth.Plan(raw: "go"))
        .frame(width: 900, height: 760)
}
#endif
