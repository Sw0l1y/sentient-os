//
//  UninstallView.swift
//  Sentient OS macOS
//
//  The uninstall sheet (Settings › General › Uninstall…), a Setup Assistant–style paged sheet
//  (`.presentationSizing(.page)`) of four SetupAssistantPages:
//   · farewell: the founders' note, the what-gets-removed manifest, Keep Sentient (Esc) and the
//     destructive Uninstall Sentient (Return), Email the Founders and the GitHub mark;
//   · working: the teardown, its Uninstall.Stage as the page message under a spinner;
//   · helperPrompt: the wake-helper cleanup interstitial (Cancel Uninstall / Skip for Now / Try Again);
//   · gone: Show App in Finder, then Quit via Uninstall.finishAndQuit.
//  Drives System/Uninstall.swift; the teardown itself lives there. It follows the appearance.
//

import SwiftUI
import AppKit

struct UninstallView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    fileprivate enum Phase { case farewell, working, helperPrompt, gone }
    @State private var phase: Phase = .farewell
    @State private var stage: Uninstall.Stage = .stopping
    /// Fulfilled by the interstitial's buttons while the teardown awaits a helper decision.
    @State private var helperResolver: ((Uninstall.HelperChoice) -> Void)?
    /// Feedback fallback: true briefly after the address was copied because no mail app answered.
    @State private var feedbackCopied = false
    @State private var failure: String?

    init() {}

    /// Preview-only: open the sheet directly in a later phase.
    fileprivate init(previewPhase: Phase) { _phase = State(initialValue: previewPhase) }

    private var reduceMotion: Bool { motionOverride ?? systemReduced }

    var body: some View {
        Group {
            switch phase {
            case .farewell:     farewell
            case .working:      working
            case .helperPrompt: helperPrompt
            case .gone:         gone
            }
        }
        .presentationSizing(.page)
        .interactiveDismissDisabled(phase != .farewell)   // mid-teardown there's no walking away
        .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: phase)
        .alert("Uninstall Needs Attention", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    // MARK: - Phase 1 · the farewell

    private var farewell: some View {
        SetupAssistantPage(tile: .setupUninstall, title: "Before You Go", message: nil) {
            VStack(alignment: .leading, spacing: Space.l) {
                GroupBox {
                    VStack(alignment: .leading, spacing: Space.m) {
                        prose("We’re two college students who built Sentient to push the bounds of what private, on-device LLM inference can do: understand your entire life, and proactively offer to help with anything you have going on. That future should be accessible to everyone, so Sentient is 100% open source and free forever.")
                        prose("Something here didn’t land for you, and we would love to hear what. We read every note.")
                    }
                    .padding(Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Uninstalling Includes")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: Space.s) {
                    GridRow {
                        Label("The on-device model", systemImage: "cpu")
                        Label("Your knowledge base", systemImage: "book.closed")
                    }
                    GridRow {
                        Label("Cloud-copy deletion request", systemImage: "cloud")
                        Label("The overnight wake helper", systemImage: "moon.zzz")
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Saved contact addresses and invitation or lifetime-access records are retained.")
                    Text("Any running analysis or Sidekick task will be stopped first.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            HStack(spacing: Space.m) {
                Button("Keep Sentient") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                feedbackLinks
                    .font(.footnote)
                Spacer()
                Button("Uninstall Sentient", role: .destructive) { beginUninstall() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, Space.xl)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Phase 2 · the teardown

    private var working: some View {
        SetupAssistantPage(tile: .setupUninstall, title: "Taking Sentient Apart, Gently",
                           message: stageLine(stage)) {
            VStack(alignment: .center, spacing: Space.l) {
                ProgressView()
                    .controlSize(.large)
                prose(stage == .stopping
                      ? "Stopping active work safely before removing Sentient’s data."
                      : "Give us a moment. We’re removing Sentient’s local data and saved connections.")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: stage)
        }
    }

    /// `Uninstall.Stage.whisper` is all caps, which the design forbids on screen, and
    /// System/Uninstall.swift is logic this view does not own: the sentence-case line lives here.
    private func stageLine(_ stage: Uninstall.Stage) -> String {
        switch stage {
        case .stopping:  return "Stopping active work"
        case .helper:    return "Standing down the wake helper"
        case .cloud:     return "Removing the cloud copy"
        case .keychain:  return "Clearing your Keychain key"
        case .knowledge: return "Erasing your knowledge base"
        case .model:     return "Removing the on-device model"
        case .traces:    return "Sweeping the last traces"
        }
    }

    // MARK: - Phase 3 · native helper cleanup needs attention

    private var helperPrompt: some View {
        SetupAssistantPage(tile: .overnight, title: "One More Step",
                           message: "The wake helper needs attention.") {
            prose("Sentient needs its wake helper to restore normal sleep and remove its system files. If System Settings opens, allow Sentient OS to run in the background, then try again. You can skip this step, but the helper and its system files may remain.")
        } footer: {
            HStack(spacing: Space.m) {
                Button("Cancel Uninstall") { helperResolver?(.cancel) }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Skip for Now") { helperResolver?(.skip) }
                    .buttonStyle(.bordered)
                Button("Try Again") { helperResolver?(.retry) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, Space.xl)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Phase 4 · gone

    private var gone: some View {
        SetupAssistantPage(tile: .noticeUpToDate,
                           title: Uninstall.helperWasSkipped ? "App Data Cleared" : "All Clear",
                           message: Uninstall.helperWasSkipped ? "The wake helper may remain." : "Sentient is gone from this Mac.") {
            prose(Uninstall.helperWasSkipped
                  ? "The wake helper and its system files may remain because you skipped that step. Turn off Sentient OS in System Settings → General → Login Items & Extensions, then drag the app to the Trash."
                  : "Everything Sentient made here has been removed. To finish, drag the Sentient OS app from your Applications folder to the Trash. Thank you for giving Sentient a try; it meant a lot to the two of us.")
        } footer: {
            SetupAssistantFooter(primaryTitle: "Quit Sentient", leading: {
                HStack(spacing: Space.m) {
                    Button("Show App in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                    .buttonStyle(.link)
                    feedbackLinks
                }
            }) {
                Uninstall.finishAndQuit()
            }
        }
    }

    // MARK: - The run

    private func beginUninstall() {
        phase = .working
        stage = .stopping
        Task { @MainActor in
            let finished = await Uninstall.run(
                appState: appState,
                progress: { stage = $0 },
                helperDecision: {
                    await withCheckedContinuation { cont in
                        phase = .helperPrompt
                        helperResolver = { choice in
                            helperResolver = nil
                            phase = .working
                            cont.resume(returning: choice)
                        }
                    }
                })
            phase = finished ? .gone : .farewell   // a cancel backs out with nothing removed
            failure = Uninstall.lastFailure
        }
    }

    // MARK: - Shared bits

    private func prose(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Email the Founders and the GitHub mark (the receipt for the "100% open source" line).
    private var feedbackLinks: some View {
        HStack(spacing: Space.m) {
            Button(feedbackCopied ? "feedback@sentient-os.ai copied" : "Email the Founders…",
                   systemImage: feedbackCopied ? "checkmark" : "envelope") {
                shareFeedback()
            }
            .buttonStyle(.link)
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/Sentient-OS-Labs/sentient-os")!)
            } label: {
                Image("GitHubMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Sentient OS on GitHub")
            .accessibilityLabel("Sentient OS on GitHub")
        }
    }

    /// Open a pre-addressed compose in a real mail app. The naive `open(mailto:)` is not enough:
    /// when a BROWSER owns the mailto scheme (Chrome et al., field-seen 2026-07-11), it reports
    /// success and then silently swallows the link unless the user once opted into its webmail
    /// handling. So: a dedicated mail app as handler → the default route; the handler is the web
    /// browser (or nothing) → Apple Mail directly; Mail missing too → copy the address and say so
    /// on the button. The click must never silently do nothing.
    private func shareFeedback() {
        let mailto = URL(string: "mailto:feedback@sentient-os.ai?subject=Sentient%20OS%20feedback")!
        let mailtoHandler = NSWorkspace.shared.urlForApplication(toOpen: mailto)
        let webHandler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)

        if let mailtoHandler, mailtoHandler != webHandler {
            Log("UninstallView: feedback compose via the default mail app (\(mailtoHandler.lastPathComponent))")
            NSWorkspace.shared.open(mailto)
        } else if let mailApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") {
            Log("UninstallView: mailto handler is the web browser — opening Apple Mail directly")
            NSWorkspace.shared.open([mailto], withApplicationAt: mailApp,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { Task { @MainActor in copyFeedbackAddress() } }
            }
        } else {
            copyFeedbackAddress()
        }
    }

    private func copyFeedbackAddress() {
        Log("UninstallView: no mail app answered — copied the feedback address instead")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("feedback@sentient-os.ai", forType: .string)
        feedbackCopied = true
        Task { try? await Task.sleep(for: .seconds(4)); feedbackCopied = false }
    }
}

#Preview("Farewell") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            UninstallView()
                .frame(width: 640, height: 640)
                .environment(\.colorScheme, scheme)
        }
    }
}
#Preview("Working") { UninstallView(previewPhase: .working).frame(width: 640, height: 560) }
#Preview("Helper prompt") { UninstallView(previewPhase: .helperPrompt).frame(width: 640, height: 560) }
#Preview("Gone") { UninstallView(previewPhase: .gone).frame(width: 640, height: 560) }
