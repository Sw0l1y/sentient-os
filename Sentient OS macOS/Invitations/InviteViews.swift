// InviteViews.swift
// The invitation rows in Settings › General › Invitations (a code with Copy, the accepted count,
// "Have an Invite Code?"), the Copy button with its verify-then-copy states, and Home's invite
// notice. Every surface reads InviteProgram; the rows are Form rows, so they look like the rest
// of Settings and follow the system appearance.
// Doc: Views/Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI
import AppKit

/// "Have an Invite Code?" in the App Store's Redeem style: one field with an inline submit arrow
/// and an error line under it. The body is a group of rows, so inside a Form (Settings) each
/// branch reads as a Form row, and outside one it is a plain stack.
struct InviteRedemptionView: View {
    var startsCollapsed = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var program = InviteProgram.shared
    @State private var code = ""
    @State private var showingGift = false
    @Namespace private var giftTicket
    @State private var hasExpanded = false
    @FocusState private var codeFocused: Bool

    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }

    private var isCollapsed: Bool {
        startsCollapsed && !hasExpanded && program.snapshot?.hasRecordedGift != true
    }

    private var hasLifetimeAccess: Bool { program.snapshot?.hasLifetimeAccess == true }
    private var showsSavedLateGift: Bool { program.snapshot?.lateUse != nil && !hasExpanded }
    private var showsField: Bool { !hasLifetimeAccess && !showsSavedLateGift && !isCollapsed }

    var body: some View {
        Group {
            // The modifiers below sit on this one row (not on the Group), so the refresh task
            // and the gift sheet exist once, whichever branch is showing.
            primaryRow
                .onChange(of: code) { program.clearError() }
                .task { await program.refresh(createIfNeeded: false) }
                .sheet(isPresented: $showingGift) {
                    InviteCelebration(ticketNamespace: giftTicket, continueTitle: "Continue") {
                        showingGift = false
                    }
                }
            if showsField, let error = program.errorMessage {
                StatusLabel(error, tone: .warning)
            }
        }
    }

    @ViewBuilder private var primaryRow: some View {
        if hasLifetimeAccess {
            StatusRow("Lifetime Access Unlocked", detail: "Your Sentient OS access is saved.", tone: .ok)
        } else if showsSavedLateGift {
            LabeledContent {
                Button("Redeem Lifetime Access") {
                    code = InviteLateUse.code
                    hasExpanded = true
                }
                .controlSize(.small)
            } label: {
                Text("Your Sidekick Gift Is Saved")
                Text("Redeem FINAL_1000 to unlock lifetime access.")
            }
        } else if isCollapsed {
            Button("Have an Invite Code?") { expand() }
                .buttonStyle(.link)
                .accessibilityHint("Show the invite code field")
        } else {
            LabeledContent("Have an Invite Code?") {
                HStack(spacing: Space.s) {
                    TextField("Invite Code", text: $code, prompt: Text("Enter invite code"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                        .frame(width: 180)
                        .focused($codeFocused)
                        .onSubmit(redeem)
                        .accessibilityLabel("Invite code")
                    Button(action: redeem) {
                        if program.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.right.circle.fill").imageScale(.large)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(program.isBusy || !InviteSnapshot.isValidCode(code))
                    .help("Redeem invite code")
                    .accessibilityLabel("Redeem invite code")
                }
            }
            .disabled(program.isRedeeming)
        }
    }

    private func expand() {
        guard let animation = Motion.gated(Motion.quick, reduceMotion: reduceMotion) else {
            hasExpanded = true
            codeFocused = true
            return
        }
        withAnimation(animation) {
            hasExpanded = true
        } completion: {
            codeFocused = true
        }
    }

    private func redeem() {
        guard !program.isBusy, InviteSnapshot.isValidCode(code) else { return }
        let submittedCode = code
        Task {
            if await program.redeem(submittedCode) {
                hasExpanded = false
                if InviteLateUse.matches(submittedCode) { showingGift = true }
            }
        }
    }
}

/// Settings › General › Invitations, in the System Settings "share with family" shape: a labelled
/// code with a trailing Copy button, the accepted count, the redemption rows, and a footer.
struct InviteSettingsSection: View {
    @State private var program = InviteProgram.shared

    private var shareableCode: String? {
        guard let snapshot = program.snapshot, snapshot.canShare else { return nil }
        return snapshot.code
    }

    var body: some View {
        Section {
            primaryRow
                .task {
                    // Friends can redeem while this pane stays open. Refresh only existing identities.
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                        await program.refresh(createIfNeeded: false, quietly: true)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await program.refresh(createIfNeeded: false, quietly: true) }
                }
            if shareableCode != nil, let count = program.snapshot?.redemptionCount, count > 0 {
                LabeledContent("Accepted", value: count == 1 ? "1 invitation" : "\(count) invitations")
            }
            InviteRedemptionView(startsCollapsed: true)
        } header: {
            Text("Invitations")
        } footer: {
            if shareableCode != nil {
                Text("Share Sentient OS free\u{00A0}for\u{00A0}life with just 5\u{00A0}people you choose.")
            }
        }
    }

    @ViewBuilder private var primaryRow: some View {
        if let code = shareableCode {
            LabeledContent {
                InviteCopyButton(code: code)
            } label: {
                Text("Your Invite Code")
                Text("5 invitations, reserved for you")
            }
        } else if let snapshot = program.snapshot, !snapshot.canShare {
            Text("This invitation offer has closed.")
                .foregroundStyle(.secondary)
        } else {
            LabeledContent("Your Invitations") {
                Button(program.isBusy ? "Preparing…" : "View Invitations") {
                    Task { await program.refresh() }
                }
                .disabled(program.isBusy)
            }
        }
    }
}

/// A Copy button with checkmark feedback (Passwords › Copy). It re-verifies the invite before
/// writing the current code to the pasteboard, and shows Checking / Copied / Try Again.
struct InviteCopyButton: View {
    let code: String
    var showsCode = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var program = InviteProgram.shared
    @State private var copied = false
    @State private var copying = false
    @State private var copyFailed = false

    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }
    private var showsCodeNow: Bool { showsCode && !copying }

    var body: some View {
        Button(action: copy) {
            Label {
                Text(showsCodeNow ? code : actionTitle)
                    .font(showsCodeNow ? .system(.callout, design: .monospaced) : nil)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(copied ? AnyShapeStyle(Color.green) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.bordered)
        .disabled(copying || program.isBusy)
        .help(copyFailed ? "Couldn’t verify this invite. Click to retry." : (copied ? "Invite code copied" : "Copy invite code"))
        .accessibilityLabel(copyFailed ? "Retry copying invite code" : (copied ? "Invite code copied" : "Copy invite code"))
        .onChange(of: code) { copied = false; copyFailed = false }
    }

    private var icon: String {
        copied ? "checkmark" : (copyFailed ? "arrow.clockwise" : "doc.on.doc")
    }

    private var actionTitle: String {
        if copying { return "Checking Invite…" }
        if copyFailed { return "Try Again" }
        return copied ? "Copied" : "Copy Invite Code"
    }

    private func copy() {
        guard !copying else { return }
        copying = true
        copied = false
        copyFailed = false
        Task {
            let verified = await program.refresh()
            var didCopy = false
            if verified, program.snapshot?.canShare == true, let currentCode = program.snapshot?.code {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                didCopy = pasteboard.setString(currentCode, forType: .string)
            }
            withAnimation(Motion.gated(Motion.quick, reduceMotion: reduceMotion)) {
                copied = didCopy
                copyFailed = !didCopy
                copying = false
            }
        }
    }
}

/// Home's invite notice: the shared NoticeBar with a pink gift tile and "Copy Invite Code".
/// It sets no width, frame or color scheme; HomeNotices gives it the column.
struct InviteBannerView: View {
    let code: String
    let dismiss: () -> Void

    var body: some View {
        NoticeBar(tile: .noticeInvite, title: InviteProgram.offerTitle, message: InviteProgram.offerMessage,
                  dismissLabel: "Dismiss invitation", onDismiss: dismiss) {
            InviteCopyButton(code: code, showsCode: false)
        }
    }
}

#if DEBUG
#Preview("Invite notice") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            InviteBannerView(code: "A7K2M9", dismiss: {})
                .frame(width: 420).padding(20)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
        }
    }
}
#Preview("Invitations section") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            Form {
                InviteSettingsSection()
            }
            .formStyle(.grouped)
            .frame(width: 480, height: 320)
            .environment(\.colorScheme, scheme)
        }
    }
}
#endif
