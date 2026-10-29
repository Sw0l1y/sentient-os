// Onboarding's gift entry, App Store "Redeem Gift Card or Code…" style (SPEC-D6 S11): a
// footnote link in Choose Your AI's footer opens a small code-entry popover; a verified
// redemption presents the gift celebration as a sheet, after which a small saved-pass badge
// replaces the link. Only a verified submission presents the gift; restored receipts show the
// corresponding saved pass.
// Doc: ../Views/Onboarding/Documentation - Onboarding.md

import SwiftUI
import AppKit

struct OnboardingInviteView: View {
    @Binding var isPresentingGift: Bool
    @State private var program = InviteProgram.shared
    @State private var code = ""
    @State private var expanded = false
    @State private var redemption: Task<Void, Never>?
    @FocusState private var codeFocused: Bool
    @Namespace private var ticket
#if DEBUG
    // Replay the entry and reveal on a developer's Mac without discarding its permanent grant.
    @AppStorage("dev.invites.replay") private var replayInvitation = false
#endif

    private var hasAccess: Bool {
#if DEBUG
        if replayInvitation { return false }
#endif
        return program.snapshot?.hasLifetimeAccess == true
    }
    private var showsLateGift: Bool { program.snapshot?.showsLateGift == true }

    var body: some View {
        // One container (not a Group), so the sheet, task and disappear handlers belong to the
        // footer slot and do not re-run when the link turns into the badge.
        HStack(spacing: 0) {
            if hasAccess && !isPresentingGift {
                // The saved pass: a small badge, and the matched-geometry source for the gift.
                // The compact face (no perforation or footer) fits the 28 pt slot at 0.35 without
                // clipping the value line (WP10 S11 open issue 4 / WP13 deviation 2).
                InviteTicketFace(claimed: true, lateGift: showsLateGift, compact: true)
                    .frame(width: 332)
                    .scaleEffect(0.35, anchor: .leading)
                    .frame(width: 120, height: 28, alignment: .leading)
                    .clipped()
                    .matchedGeometryEffect(id: "invite-ticket", in: ticket)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(showsLateGift ? "Your Sidekick gift is saved" : "Sentient OS lifetime access is saved")
            } else {
                HStack(spacing: Space.s) {
                    if showsLateGift {
                        // A gift granted earlier: saved, and a lifetime code can still be redeemed.
                        Label("Gift saved", systemImage: "gift.fill")
                            .labelStyle(.titleAndIcon)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Your Sidekick gift is saved")
                    }
                    Button("Have a gift code?") {
                        program.clearError()
                        expanded = true
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(Color(nsColor: .linkColor))
                    .accessibilityLabel("Have a gift code? Enter your code.")
                    .help("Redeem your invitation")
                    .matchedGeometryEffect(id: "invite-ticket", in: ticket)
                    .popover(isPresented: $expanded, arrowEdge: .top) { entryForm }
                }
                .font(.footnote)
            }
        }
        .sheet(isPresented: $isPresentingGift) {
            InviteCelebration(ticketNamespace: ticket) {
                isPresentingGift = false
                expanded = false
            }
            // Onboarding disables itself while the gift shows; the sheet's own buttons stay live.
            .environment(\.isEnabled, true)
            .presentationSizing(.form)
        }
        .task {
            await program.refresh(createIfNeeded: false)
            if showsLateGift, code.isEmpty {
                expanded = false
            }
        }
        .onDisappear {
            redemption?.cancel()
            redemption = nil
            isPresentingGift = false
        }
    }

    /// The code-entry form inside the popover. Esc or a click outside closes it.
    private var entryForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Redeem a Gift Code", systemImage: "gift")
                .font(.headline)
            HStack(spacing: Space.s) {
                TextField("Enter invite code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($codeFocused)
                    .onSubmit(redeem)
                    .onChange(of: code) { program.clearError() }
                    .accessibilityLabel("Invite code")
                Button(action: redeem) {
                    if program.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Redeem")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(program.isBusy || !InviteSnapshot.isValidCode(code))
                .accessibilityLabel("Redeem invite code")
            }
            .disabled(program.isRedeeming)

            if let error = program.errorMessage {
                StatusLabel(error, tone: .error)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(program.isRedeeming ? "Checking your invitation…" : "Redeem your invitation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: PageMetrics.popover, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Close invite code field") {
            codeFocused = false
            expanded = false
        }
        .onAppear { codeFocused = true }
    }

    private func redeem() {
        guard redemption == nil, !program.isBusy, InviteSnapshot.isValidCode(code) else { return }
        codeFocused = false
        let submittedCode = code
        redemption = Task {
            defer { redemption = nil }
            let redeemed = await program.redeem(submittedCode)
            guard !Task.isCancelled else { return }
            if redeemed {
                expanded = false
                isPresentingGift = true
#if DEBUG
                replayInvitation = false
#endif
            } else {
                codeFocused = true
            }
        }
    }
}
