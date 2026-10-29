//
// WritingStyleSetupView.swift
// The introduction sheet for existing knowledge bases (a system "Preparing…" status sheet): runs
// the same collector as initial processing, with cancellation and an explicit retry after failures. Hidden for now: RootView
// runs the same setup silently in the background instead, and this sheet waits for the
// introduction to return.
// Doc: Documentation - Double Tap.md
//

import SwiftUI

struct WritingStyleSetupView: View {
    var runsSetup = true
    @Environment(\.dismiss) private var dismiss
    @State private var attempt = 0
    @State private var status = "Gathering examples of how you write…"
    @State private var failure: String?
    @State private var finished = false

    var body: some View {
        VStack(spacing: Space.l) {
            BrandMarkView(size: 40)
            Text(finished ? "Double Tap Is Ready" : "Setting Up Double Tap")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            stateLine
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            if !finished {
                Text(PrivacyCopy.writingSetup)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttonRow
                .padding(.top, Space.s)
        }
        .padding(Space.xxl)
        .frame(width: 460)
        .frame(minHeight: 320)
        .presentationSizing(.form)
        .task(id: attempt) {
            guard runsSetup else { return }
            failure = nil
            do {
                try await WritingStyle.generateIfNeeded { line in
                    Task { @MainActor in status = line }
                }
                try Task.checkCancellation()
                finished = true
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                if let known = (error as? WritingStyle.Failure)?.errorDescription {
                    failure = known
                } else {
                    failure = Self.engineFailure(await OvernightCaution.classify(error))
                }
                Log("WritingStyle: setup failed (\(ErrorLabel(error)))")
            }
        }
    }

    @ViewBuilder private var stateLine: some View {
        if finished {
            Text("Double-tap \(ShortcutPreferences.current.label) in a reply box to write in your own voice.")
                .font(.body)
                .foregroundStyle(.secondary)
        } else if let failure {
            StatusLabel(failure, tone: .error)
        } else {
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small)
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var buttonRow: some View {
        HStack(spacing: Space.s) {
            Spacer()
            if finished {
                escapeTwin
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if failure != nil {
                escapeTwin
                Button("Open Double Tap Settings") {
                    dismiss()
                    HomeWindowOpening.open(.settings, settingsPane: .doubleTap)
                }
                .buttonStyle(.bordered)
                Button("Try Again") { attempt += 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    /// Esc closes the finished and failed states too, which have no visible Cancel. It stays in
    /// the hierarchy (invisible, zero size) so its shortcut keeps working.
    private var escapeTwin: some View {
        Button("Close") { dismiss() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

extension WritingStyleSetupView {
    /// The processing screen's vocabulary: a classified engine problem is named, anything else
    /// gets the generic line.
    static func engineFailure(_ kind: OvernightCaution.Kind?) -> String {
        let claude = ModelBackend.current == .claude
        return switch kind {
        case .usageLimit: "We hit \(claude ? "Claude's" : "ChatGPT's") usage limit. It resets on its own; try again in a while."
        case .loggedOut: claude ? "Claude isn't signed in. Sign in from Settings, then try again."
                                : "Codex isn't logged in. Log in from Settings, then try again."
        case .noInternet: "No internet connection. Once you're back online, try again."
        case .connectorAuth: "A connected app needs a fresh sign-in. Reconnect it in Settings, then try again."
        default: "Setup couldn’t finish. Check your AI and source connections in Settings, then try again."
        }
    }
}

#Preview {
    HStack(spacing: 0) {
        WritingStyleSetupView(runsSetup: false).environment(\.colorScheme, .light)
        WritingStyleSetupView(runsSetup: false).environment(\.colorScheme, .dark)
    }
}
