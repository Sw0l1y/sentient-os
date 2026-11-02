// The computer-use gate's page and the permission rows for native OpenAI and CUA computer use.
// The page is a Setup Assistant privacy page; the rows are the same StatusRows Permissions &
// Health shows, grouped in Sections, with the floating macOS permission guide behind "Allow…".
// Doc: Documentation - Permission Gate & Guide.md

import SwiftUI
import AppKit
import AVFoundation

struct ComputerUseGateView: View {
    let gate: ComputerUseGate

    var body: some View {
        PermissionSetupView(tile: gate.showingVoiceRepair ? .microphone : .gateComputerUse,
                            title: gate.showingVoiceRepair ? "Set Up Voice Input" : "Allow Sidekick to Use Your Computer",
                            continueTitle: continueTitle,
                            canContinue: gate.showingVoiceRepair || gate.allRequiredGranted,
                            primaryID: "computerUseGate.continue",
                            onContinue: gate.continueNow) {
            if gate.showingVoiceRepair {
                GateForm {
                    Section("Voice Input") {
                        GatePermissionRow("Microphone & Speech", tile: .microphone, detail: micSpeechNote,
                                          tone: gate.micSpeech == .granted ? .ok : .warning,   // optional: never red
                                          info: ComputerUseGate.micSpeechTip,
                                          fixTitle: micSpeechFixTitle,
                                          fix: fixMicSpeech)
                    }
                }
            } else {
                GateForm { SentientPermissionRows(gate: gate) }
                if !gate.sentientScreen, SafeAppRelaunch.shared.canRelaunchPermissionWait {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("If macOS asks you to restart, keep this request as a draft. Send it again after relaunching.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Save Request & Relaunch") { _ = SafeAppRelaunch.shared.relaunchPermissionWait() }
                            .buttonStyle(.bordered)
                    }
                }
                if let failure = SafeAppRelaunch.shared.failure {
                    StatusLabel(failure, tone: .error)
                }
            }
        }
        .frame(width: PageMetrics.setupPage, height: gate.showingVoiceRepair ? 440 : 640)
        .task {
            while !Task.isCancelled {
                gate.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            gate.refresh()   // the user may just have flipped a switch in System Settings
        }
    }

    // MARK: Sentient's grants — native prompts first, the guide as the fallback

    private var continueTitle: String {
        if gate.showingVoiceRepair { return "Done" }
        if gate.allRequiredGranted { return "Continue" }
        if gate.backend == .openAI {
            return gate.checkingAutomation ? "Checking Computer Use…" : "Finish Setup to Continue"
        }
        return "Grant Permissions to Continue"
    }

    private var micSpeechNote: String {
        switch gate.micSpeech {
        case .granted:  return "Granted"
        case .notAsked: return "Not requested"
        case .denied:   return "Off"
        }
    }

    private var micSpeechFixTitle: String? {
        switch gate.micSpeech {
        case .granted:  return nil
        case .notAsked: return "Allow…"
        case .denied:   return "Fix…"
        }
    }

    private func fixMicSpeech() {
        switch gate.micSpeech {
        case .granted:
            break
        case .notAsked:
            Task { _ = await VoiceCapture.requestPermissions(); gate.refresh() }
        case .denied:
            // Deep-link to whichever grant is actually the blocker (mic first — it gates speech).
            if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                Permissions.openMicrophoneSettings()
            } else {
                Permissions.openSpeechRecognitionSettings()
            }
        }
    }

}

/// The selected computer-use runtime's required grants. Sentient's own rows are also reused by
/// Double Tap; the native helper's rows remain specific to computer use.
/// `gate` is the one probe source; call `gate.refresh()` around presentation.
/// Emits Sections only, so they join the enclosing Form.
struct SentientPermissionRows: View {
    let gate: ComputerUseGate

    var body: some View {
        if gate.backend == .openAI, !gate.setup.ready || !CodexSetup.shared.computerUseReady {
            Section {
                GatePermissionRow("Computer Use", tile: .computerUse,
                                  detail: gate.setup.isInstalling ? "Setting up…" : "Not set up",
                                  tone: gate.setup.isInstalling ? .working : .error,
                                  info: "Prepares the computer-use tools for your selected AI engine.",
                                  fixTitle: "Set Up…",
                                  fix: gate.setup.isInstalling ? nil : { Task { await gate.setup.install() } })
            } header: {
                Text("Computer Use")
            } footer: {
                if let line = gate.setup.status {
                    Text(line)
                }
            }
        }
        if gate.backend == .openAI { NativeComputerUsePermissionRows(gate: gate) }
        SentientAppPermissionRows(accessibility: gate.backend == .cua ? gate.sentientAccessibility : nil,
                                  screen: gate.sentientScreen)
    }
}

/// Native helper grants are shared by the first-use gate, upgrade flow and Settings.
/// One Section ("Computer Use Helper"): three permission rows, the "already allowed" check row,
/// and the status sentence with its one retry button in the footer.
/// Accessibility and Screen Recording are proven only by a live check. Between checks a saved,
/// display-only proof (NativePermissionProof) shows "Verified <date>"; with none, the rows say a
/// task start checks them, in a neutral tone. Only a real denial or error warns, and only a denial
/// offers System Settings.
struct NativeComputerUsePermissionRows: View {
    let gate: ComputerUseGate
    private var proofs: NativePermissionProofStore { .shared }

    var body: some View {
        let accessibility = helperRow(gate.helperPermissionState.accessibility)
        let screen = helperRow(gate.helperPermissionState.screenRecording)
        Section {
            GatePermissionRow("Accessibility", tile: .accessibility,
                              detail: helperDetail(accessibility),
                              tone: helperTone(accessibility),
                              info: "Allows clicking and typing in your apps.",
                              fixTitle: "Open Settings",
                              fix: !gate.setup.ready || !accessibility.offersSettingsFix ? nil : {
                PermissionGuide.shared.guide(.accessibility, dragging: OpenAIComputerUse.appURL)
            })
            // The probe and the auto-request live on one row (always shown), so they run once;
            // a modifier on the Section would be applied to every row.
            .task(id: gate.setup.ready) { await gate.prepareNativePermissions() }
            .onChange(of: gate.automation) { _, state in
                // Never auto-ask while another helper copy runs: asking would close it unannounced.
                if state == .notAsked, gate.setup.ready, !gate.nativeHelperConflict { gate.requestAutomation() }
            }
            GatePermissionRow("Screen Recording", tile: .screenRecording,
                              detail: helperDetail(screen),
                              tone: helperTone(screen),
                              info: "Allows computer use to see the app it is working in.",
                              fixTitle: "Open Settings",
                              fix: !gate.setup.ready || !screen.offersSettingsFix ? nil : {
                PermissionGuide.shared.guide(.screenRecording, dragging: OpenAIComputerUse.appURL)
            })
            GatePermissionRow("Automation", tile: .automation,
                              detail: automationDetail,
                              tone: automationTone,
                              info: "Allows Sentient OS to control its computer-use helper. This is separate from Screen Recording and Accessibility.",
                              fixTitle: gate.automation == .denied ? "Open Settings" : (gate.automation == .notAsked ? "Allow…" : "Check Again"),
                              fix: !automationOffersFix ? nil : {
                if gate.automation == .denied { Permissions.openAutomationSettings() }
                else { gate.requestAutomation() }
            })
            if showsAlreadyAllowed(accessibility, screen) {
                LabeledContent {
                    Button("Check Computer Use") { gate.requestAutomation() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(gate.checkingAutomation)
                } label: {
                    Text("Already Allowed These Permissions?")
                    Text("Check them using a temporary Sentient window. Full Disk Access is not needed.")
                }
            }
        } header: {
            Text("Computer Use Helper")
        } footer: {
            if let status = statusText {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(status)
                    if let retry = retryAction {
                        Button(retry.title, action: retry.run)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(gate.checkingAutomation)
                    }
                }
            }
        }
    }

    // MARK: State

    /// Accessibility or Screen Recording: the live snapshot first, then a saved proof for this
    /// helper install and Sentient build. A recorded check error outranks an old proof.
    private func helperRow(_ live: NativePermissionReadiness.State) -> NativePermissionProof.Row {
        proofs.row(live: live, checkFailed: gate.setup.ready && gate.nativePermissionError != nil)
    }

    /// A user-started check in progress shows on the rows it is about to prove.
    private func helperChecking(_ row: NativePermissionProof.Row) -> Bool {
        gate.requestingAutomation && row != .verified && row != .denied
    }

    private func helperDetail(_ row: NativePermissionProof.Row) -> String {
        helperChecking(row) ? "Checking…" : NativePermissionProof.detail(row)
    }

    private func helperTone(_ row: NativePermissionProof.Row) -> StatusTone {
        if helperChecking(row) { return .working }
        switch row {
        case .verified, .verifiedEarlier: return .ok
        case .pending: return .off
        case .failed: return .warning
        case .denied: return .error
        }
    }

    private var automationCheckFailed: Bool { gate.setup.ready && gate.nativePermissionError != nil }

    private var automationDetail: String {
        if gate.requestingAutomation || gate.checkingAutomation { return "Checking…" }
        switch gate.automation {
        case .granted: return "Granted"
        case .denied: return "Not allowed"
        case .notAsked: return "Not requested"
        case .unavailable: return automationCheckFailed ? "Couldn’t check" : "Checked when a task starts"
        }
    }

    private var automationTone: StatusTone {
        if gate.requestingAutomation || gate.checkingAutomation { return .working }
        switch gate.automation {
        case .granted: return .ok
        case .denied: return .error
        case .notAsked: return .warning
        case .unavailable: return automationCheckFailed ? .warning : .off
        }
    }

    /// Open Settings for a denial, Allow… for a first request, Check Again only after an error.
    private var automationOffersFix: Bool {
        guard gate.setup.ready, !gate.requestingAutomation, !gate.checkingAutomation else { return false }
        switch gate.automation {
        case .granted: return false
        case .denied, .notAsked: return true
        case .unavailable: return automationCheckFailed
        }
    }

    /// The status sentence, in today's priority order and words.
    private var statusText: String? {
        if gate.restartingNative {
            return "Restarting computer use…"
        } else if gate.requestingAutomation {
            return gate.automation == .granted ? "Checking computer use…" : "Choose Allow in the macOS permission prompt."
        } else if gate.automation == .denied {
            return "In System Settings → Privacy & Security → Automation, expand Sentient OS and turn on ChatGPT Computer Use (called Codex Computer Use in some versions)."
        } else if gate.setup.ready, let error = gate.nativePermissionError {
            return error
        } else if gate.setup.ready, gate.nativeHelperConflict {
            return "ChatGPT’s computer-use helper is running. Sentient takes it over when a task starts. Check Now closes ChatGPT’s helper and checks these permissions."
        } else if gate.setup.ready, gate.checkingAutomation, gate.automation != .granted {
            return "Checking permissions…"
        }
        return nil
    }

    /// The footer's one action: a retry under a helper error, or Check Now while another helper
    /// copy runs (it takes that copy over, as the status sentence says, then runs the live check).
    private var retryAction: (title: String, run: () -> Void)? {
        guard !gate.restartingNative, !gate.requestingAutomation, gate.automation != .denied,
              gate.setup.ready else { return nil }
        if gate.nativePermissionError != nil {
            if gate.nativeRestartRequired {
                return ("Restart Computer Use", { gate.restartComputerUse() })
            }
            return ("Try Again", { gate.requestAutomation() })
        }
        if gate.nativeHelperConflict {
            return ("Check Now", { gate.requestAutomation() })
        }
        return nil
    }

    /// The optional manual check, offered only while nothing has proven the helper yet and no
    /// other helper copy would be closed without the footer's explanation.
    private func showsAlreadyAllowed(_ accessibility: NativePermissionProof.Row,
                                     _ screen: NativePermissionProof.Row) -> Bool {
        gate.setup.ready && gate.automation == .granted && !gate.helperPermissionState.isReady
            && gate.nativePermissionError == nil && !gate.requestingAutomation && !gate.nativeHelperConflict
            && (accessibility == .pending || screen == .pending)
    }
}

#Preview("Computer-use gate") {
    ComputerUseGateView(gate: ComputerUseGate.shared)
}
