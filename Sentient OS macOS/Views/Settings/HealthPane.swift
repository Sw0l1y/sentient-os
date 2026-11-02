//
//  HealthPane.swift
//  Sentient OS macOS
//
//  Settings › Permissions & Health, laid out like System Settings › Privacy & Security: tiled
//  status rows, each with its tone glyph, a fix button while it is not OK, and its explanation
//  in an ⓘ popover. Shared setup rows prepare native computer use for every backend; Claude
//  users see both CLIs and only their Claude login. Required grants remain separate from
//  optional voice and notifications (never red). Fixes use the existing setup engines.
//
//  Also here: HealthBoard, the counted checks and their issue count, kept once for the session.
//  The pane draws those rows from it and the sidebar badge reads its count, so the two agree.
//  Doc: Documentation - Settings.md
//

import SwiftUI
import AppKit
import AVFoundation
import Speech
import UserNotifications

struct HealthPane: View {
    /// Optional on purpose: the pane's #Preview renders without an AppState in the environment.
    @Environment(AppState.self) private var appState: AppState?
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var codex = CodexSetup.shared
    @State private var claude = ClaudeSetup.shared
    private var computerGate: ComputerUseGate { .shared }
    /// The counted checks (protected sources, overnight wake, login, the engine, sources to retry).
    private var board: HealthBoard { .shared }
    /// The live frontier-model choice, observed so switching engines re-renders the pane's
    /// engine section in place.
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue

    private var backend: ModelBackend { ModelBackend(rawValue: backendRaw) ?? .chatgpt }
    private var reduceMotion: Bool { motionOverride ?? systemReduced }

    // Sentient's own grants (the counted ones live on the board)
    @State private var micSpeech: MicSpeechState = .notAsked
    @State private var screenRec = Permissions.hasScreenRecording()   // Sentient's own grant: the driver's eyes
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined

    // ChatGPT plan (decoded from the user's own codex login: CodexAuth)
    @State private var plan: CodexAuth.Plan?
    @State private var planChecking = false

    @State private var codexExpanded = false
    @State private var checked = false        // first full probe done (codex login check is seconds)

    #if DEBUG
    init(expandEngine: Bool = false) { _codexExpanded = State(initialValue: expandEngine) }
    #endif

    private enum MicSpeechState { case granted, notAsked, denied }

    private var engineAllGreen: Bool { board.engineAllGreen }

    private var subtitle: String {
        if !checked { return "Checking…" }
        switch board.issueCount {
        case 0: return "All good"
        case 1: return "1 needs attention"
        default: return "\(board.issueCount) need attention"
        }
    }

    private var requiresOvernightSetup: Bool { HealthCaution.overnightRequested() }

    private var protectedAccessNote: String {
        if board.selectedProtectedSources.isEmpty { return "Not needed for your selected sources" }
        return board.unreadableProtectedSources.isEmpty ? "Selected sources are readable" : "Selected sources need access"
    }

    var body: some View {
        PaneForm {
            if !checked {
                checkingSection
            } else {
                onDeviceSection
                sidekickSection
                NativeComputerUsePermissionRows(gate: computerGate)   // Section "Computer Use Helper" (WP12)
                ComputerUseCheckRow()                                 // Section "Computer Use Check" (WP12)
                if !board.sourceIssues.isEmpty { retrySection }
                engineSection
                Section {} footer: {
                    Label(PrivacyCopy.trustRibbon, systemImage: "lock.shield")
                }
            }
        }
        .pageSubtitle(subtitle, page: .settings, pane: .health)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Check Again", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                .help("Check Again")
            }
        }
        // A finished analysis rewrites the source health; recount so the list and the badge follow.
        .onChange(of: sourceHealth) { board.recountSources() }
        .task { await refresh() }
        // Initial too: the board's wake setup outlives the pane, so a helper Home's refresh already
        // found ready reaches the scheduler on the next open, as each open's fresh probe did.
        .onChange(of: board.wakeSetup.ready, initial: true) { _, ready in
            if ready && requiresOvernightSetup {
                appState?.scheduler.reevaluate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }   // the user may just have fixed something in System Settings
        }
        .task(id: codex.loggingIn) {
            // The browser-login auto-notice, same as onboarding: while a login is out, poll
            // `codex login status` every 2s so the row turns OK the moment they finish,
            // with no "I'm done" button. The task re-keys (and cancels) with the loggingIn flag.
            while !Task.isCancelled, codex.loggingIn, !codex.loggedIn {
                try? await Task.sleep(for: .seconds(2))
                await codex.refreshLoginStatus()
            }
            if codex.loggedIn { plan = CodexAuth.currentPlan() }   // the plan row rides the login
        }
        .task(id: claude.loggingIn) {
            // The Claude twin of the auto-notice poll.
            while !Task.isCancelled, claude.loggingIn, !claude.loggedIn {
                try? await Task.sleep(for: .seconds(2))
                await claude.refreshLoginStatus()
            }
        }
        .onChange(of: backendRaw) {
            Task { await refresh() }   // a fresh engine choice re-probes its own rows
        }
    }

    /// A row's fix: shown by the caller only while the row is not OK (area rule 9).
    private func fixButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    // MARK: - First probe

    /// The first probe's stand-in: the codex login check shells out and takes seconds; without
    /// this the full board flashes and re-collapses.
    private var checkingSection: some View {
        Section {
            LabeledContent {
                ProgressView().controlSize(.small)
            } label: {
                Text("Checking your Sentient…")
            }
        }
    }

    // MARK: - Sources to Retry

    // Observed only to notice the analysis rewriting them; the board reads the values.
    @AppStorage(AppleCalendarSource.issueKey) private var calendarIssue = ""
    @AppStorage(AppleMailHealth.key) private var mailHealth = ""
    @AppStorage(AppleMailHealth.needsRetryKey) private var mailNeedsRetry = false
    @AppStorage(SourceHealth.readStatusKey) private var readStatusData = Data()

    private struct SourceHealthStamp: Equatable {
        let calendarIssue: String, mailHealth: String, mailNeedsRetry: Bool, readStatus: Data
    }

    private var sourceHealth: SourceHealthStamp {
        SourceHealthStamp(calendarIssue: calendarIssue, mailHealth: mailHealth,
                          mailNeedsRetry: mailNeedsRetry, readStatus: readStatusData)
    }

    private var retrySection: some View {
        Section("Sources to Retry") {
            ForEach(board.sourceIssues, id: \.self) { issue in
                StatusLabel(issue, tone: .warning)
            }
        }
    }

    // MARK: - On-Device Intelligence

    private var onDeviceSection: some View {
        Section("On-Device Intelligence") {
            StatusRow("Full Disk Access", tile: .fullDiskAccess, detail: protectedAccessNote,
                      tone: board.unreadableProtectedSources.isEmpty ? .ok : .error,
                      info: PrivacyCopy.fullDiskAccess) {
                if !board.unreadableProtectedSources.isEmpty {
                    fixButton("Grant…") {
                        PermissionGuide.shared.guide(.fullDiskAccess, dragging: Bundle.main.bundleURL)
                    }
                }
            }
            if !board.unreadableProtectedSources.isEmpty {
                LabeledContent {
                    Button("Relaunch Sentient") { Permissions.relaunch() }
                        .buttonStyle(.link)
                        .disabled(!SafeAppRelaunch.shared.canRelaunch)
                } label: {
                    Text("Check access for \(board.unreadableProtectedSources.map(\.title).joined(separator: ", ")). After changing Full Disk Access:")
                    if let reason = SafeAppRelaunch.shared.statusReason {
                        Text(reason)
                    }
                }
            }
            if requiresOvernightSetup {
                OvernightWakeRow(setup: board.wakeSetup)
            } else {
                StatusRow("Overnight Wake", tile: .overnight,
                          detail: "Overnight analysis is off. Wake setup is optional.", tone: .off)
            }
            StatusRow("Launch at Login", tile: .launchAtLogin, detail: loginNote, tone: loginTone,
                      info: "Starts Sentient quietly in your menu bar when you log in, so the overnight run can happen and your Sentient can stay alive.") {
                if loginTone != .ok {
                    fixButton(LoginItem.needsApproval ? "Approve…" : "Turn On") {
                        LoginItem.enableOrRequestApproval()
                        board.loginOn = LoginItem.isEnabled
                        if LoginItem.needsApproval {
                            PermissionGuide.shared.guide(.loginItems, dragging: nil)
                        }
                    }
                }
            }
        }
    }

    private var loginTone: StatusTone { board.loginOn || !requiresOvernightSetup ? .ok : .warning }

    private var loginNote: String {
        if board.loginOn { return "On" }
        if !requiresOvernightSetup { return "Off; optional" }
        return LoginItem.needsApproval ? "Approve in System Settings" : "Off"
    }

    // MARK: - Sidekick & Double Tap

    private var sidekickSection: some View {
        Section("Sidekick & Double Tap") {
            // Optional: Sidekick's voice; tap-to-type works without it. Yellow, never red.
            StatusRow("Microphone & Speech", tile: .microphone, detail: micSpeechNote + " · Optional",
                      tone: micSpeech == .granted ? .ok : .warning,
                      info: ComputerUseGate.micSpeechTip) {
                if micSpeech != .granted {
                    fixButton(micSpeech == .notAsked ? "Allow…" : "Fix…", action: fixMicSpeech)
                }
            }
            // The driver's eyes: computer use is off without it.
            StatusRow("Screen Recording", tile: .screenRecording, detail: screenRec ? "Granted" : "Not granted",
                      tone: screenRec ? .ok : .error, info: PrivacyCopy.screenCapture) {
                if !screenRec {
                    fixButton("Allow…", action: fixScreenRecording)
                }
            }
            StatusRow("Notifications", tile: .notifications, detail: notifNote + " · Optional",
                      tone: notifTone,
                      info: "Lets Sentient send a morning note when new suggestions are ready. Optional; everything works without it.") {
                if notifTone != .ok {
                    fixButton(notifStatus == .notDetermined ? "Allow…" : "Fix…", action: fixNotifications)
                }
            }
        }
    }

    // MARK: Microphone & Speech (one row: one call asks for both; optional, so yellow, never red)

    private var micSpeechNote: String {
        switch micSpeech {
        case .granted:  return "Granted"
        case .notAsked: return "Not asked yet"
        case .denied:   return "Off"
        }
    }

    private func fixMicSpeech() {
        switch micSpeech {
        case .granted:
            break
        case .notAsked:
            Task { _ = await VoiceCapture.requestPermissions(); await refresh() }
        case .denied:
            // Deep-link to whichever grant is actually the blocker (mic first: it gates speech).
            if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                Permissions.openMicrophoneSettings()
            } else {
                Permissions.openSpeechRecognitionSettings()
            }
        }
    }

    // MARK: Screen Recording (Sentient's own grant: the driver's eyes)

    /// The Screen Recording list is drag-authorizable, and Sentient may not be IN the list at all
    /// (on Tahoe, CGRequestScreenCaptureAccess doesn't reliably add it, field-verified), so the
    /// guide always carries Sentient itself as the drag card. Harmless when the row already
    /// exists; the user just flips the existing switch.
    private func fixScreenRecording() {
        guard !screenRec else { return }
        PermissionGuide.shared.guide(.screenRecording, dragging: Bundle.main.bundleURL)
    }

    private func refreshMicSpeech() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()
        if mic == .authorized && speech == .authorized {
            micSpeech = .granted
        } else if mic == .denied || mic == .restricted || speech == .denied || speech == .restricted {
            micSpeech = .denied
        } else {
            micSpeech = .notAsked
        }
    }

    // MARK: Notifications (yellow when off, never red: the morning briefing sleeps, the app works)

    private var notifTone: StatusTone {
        switch notifStatus {
        case .authorized, .provisional: return .ok
        default:                        return .warning
        }
    }

    private var notifNote: String {
        switch notifStatus {
        case .authorized:    return "On"
        case .provisional:   return "Quiet"   // the launch-banked provisional grant (no banners/sounds)
        case .notDetermined: return "Not asked yet"
        default:             return "Off"
        }
    }

    private func fixNotifications() {
        if notifStatus == .notDetermined {
            Task {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
                await refresh()
            }
        } else {
            // Modern Settings pane first (Ventura+), legacy anchor as fallback: same pattern as
            // Permissions.openFullDiskAccessSettings.
            let modern = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            let legacy = "x-apple.systempreferences:com.apple.preference.notifications"
            if let url = URL(string: modern), NSWorkspace.shared.open(url) { return }
            if let url = URL(string: legacy) { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: - Model Connection
    //
    // Everything OK = one summary row; "Show Details" REPLACES it (a one-way door per visit).
    // The fix buttons drive the shared CodexSetup / ClaudeSetup engines directly. While a step
    // runs, its row shows a spinner and the detail narrates; failures surface as an error line
    // under the row. The browser login is noticed automatically (the same 2s poll onboarding uses).

    private var engineSection: some View {
        Section("Model Connection") {
            if engineAllGreen && !codexExpanded {
                LabeledContent {
                    Button("Show Details") {
                        withAnimation(Motion.gated(Motion.standard, reduceMotion: reduceMotion)) {
                            codexExpanded = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } label: {
                    StatusLabel(backend == .claude ? "Claude is all good." : "Codex is all good.", tone: .ok)
                }
            } else {
                switch backend {
                case .chatgpt, .custom: codexRows
                case .claude:           claudeRows
                }
            }
        }
    }

    @ViewBuilder private var codexRows: some View {
        codexCLIRow
        if backend == .custom {
            // Codex is the harness for custom endpoints too (the vision probe and every run go
            // through `codex exec`): the CLI row stays, and the endpoint stands in for the account
            // rows. No ChatGPT login exists or is needed here.
            let usable = CustomProvider.current.isUsable
            StatusRow("Frontier Model", tile: .engineCustom,
                      detail: usable ? CustomProvider.current.modelName : "Not set up",
                      tone: usable ? .ok : .error,
                      info: "Sentient's cloud thinking runs through your own model endpoint instead of a ChatGPT login.\n\nPick and test it in AI Model.") {
                if !usable {
                    fixButton("Configure…") {
                        MainNavigation.shared.show(.settings, settingsPane: .frontierModel)
                    }
                }
            }
        } else {
            StatusRow("ChatGPT Account", tile: .codex,
                      detail: codex.loggedIn ? "Logged in"
                          : codex.loggingIn ? "Finish in your browser" : "Not logged in",
                      tone: codex.loggedIn ? .ok : codex.loggingIn ? .working : .error,
                      info: "Your own OpenAI login for Codex CLI.\n\n\u{201C}Log in\u{201D} asks Codex to open your browser to sign in. Your Codex login stays in Sentient’s private folder on this Mac.") {
                if !codex.loggedIn {
                    fixButton(codex.loggingIn ? "Reopen…" : "Log In…") {
                        Task { await codex.startLogin() }
                    }
                }
            }
            failureLine(codex.loginStatusLine)
            if codex.loggedIn, let plan {
                // The one deliberate exception to "fix only when not OK": Check Again re-mints the
                // account claim, which matters most on an OK row after an upgrade.
                StatusRow("ChatGPT Plan",
                          detail: planChecking ? "Checking…"
                              : plan.tier == .limited ? "\(plan.displayName) · provider usage limits apply"
                                                      : plan.displayName,
                          tone: planChecking ? .working : .ok,
                          info: "Try Sidekick with your connected ChatGPT account. Your provider determines which models and usage are available. A confirmed limit on Free or Go offers an upgrade to Plus.\n\nYour knowledge and source choices stay in place when your plan changes. Check Again refreshes the account claim. You can also choose another provider in AI Model.") {
                    fixButton(planChecking ? "Checking…" : "Check Again", action: recheckPlan)
                        .disabled(planChecking)
                }
            }
        }
        computerUseRow
    }

    @ViewBuilder private var claudeRows: some View {
        StatusRow("Claude Code CLI", tile: .codex,
                  detail: claude.installing ? (claude.installed ? "Updating…" : "Installing…")
                      : !claude.installed ? "Not installed"
                      : (claude.version.map { "Installed · \($0)" } ?? "Installed"),
                  tone: claude.installing ? .working : claude.installed ? .ok : .error,
                  info: "Anthropic's official Claude Code command line tool. Sentient runs its cloud thinking through it, using your own Claude subscription.\n\nSentient checks for updates quietly, at most once a day while you're away from the app. Existing installations use claude update and follow your release channel. Missing installations use Anthropic's official installer.") {
            if !claude.installed && !claude.installing {
                fixButton(claude.installed ? "Update…" : "Install…") {
                    Task { await claude.installClaude() }
                }
            }
        }
        failureLine(claude.installStatus)
        StatusRow("Claude Account",
                  detail: claude.loggedIn
                      ? (claude.plan.map { "Signed in · \($0.lowercased()) plan" } ?? "Signed in")
                      : claude.loggingIn ? "Finish in your browser" : "Not signed in",
                  tone: claude.loggedIn ? .ok : claude.loggingIn ? .working : .error,
                  info: "Sign in directly through Claude Code in your browser. Its login is kept in your Mac’s Keychain and shared with your existing Claude Code setup.") {
            if !claude.loggedIn {
                fixButton(claude.loggingIn ? "Reopen…" : "Sign In…") { claude.startLogin() }
            }
        }
        failureLine(claude.loginStatusLine)
        codexCLIRow
        computerUseRow
    }

    @ViewBuilder private var codexCLIRow: some View {
        let ok = codex.computerUseReady && !codex.outdated
        StatusRow(backend == .claude ? "Codex CLI for Computer Use" : "Codex CLI", tile: .codex,
                  detail: codex.installing ? "Preparing…" : !codex.installed ? "Not installed"
                      : codex.outdated || !codex.computerUseReady ? "Needs an update"
                      : (codex.version.map { "Installed · \($0)" } ?? "Installed"),
                  tone: codex.installing ? .working : ok ? .ok : .error,
                  info: backend == .claude
                      ? "Runs Sidekick's computer actions using your Claude subscription. A ChatGPT account is not required."
                      : "Sentient’s verified copy of Codex, using your selected frontier model. New versions arrive with Sentient updates. Repair preserves your login and saved tasks.") {
            if !ok && !codex.installing {
                fixButton(codex.installed ? "Repair…" : "Install…") {
                    Task { await codex.installCodex() }
                }
            }
        }
        failureLine(codex.installStatus)
    }

    /// The same signed native helper serves every model backend.
    @ViewBuilder private var computerUseRow: some View {
        let setup = ComputerUseSetup.current
        StatusRow("Computer Use", tile: .computerUse,
                  detail: setup.isInstalling ? "Setting up…" : (setup.ready ? "Ready" : "Not set up"),
                  tone: setup.ready ? .ok : setup.isInstalling ? .working : .error,
                  info: "Downloads and verifies OpenAI's signed computer-use helper. Your selected model powers its actions.") {
            if !setup.ready && !setup.isInstalling {
                fixButton("Set Up…") { Task { await ComputerUseSetup.current.install() } }
            }
        }
        // The download deserves live narration, not just a spinner.
        if setup.isInstalling, let line = setup.status {
            StatusLabel(line, tone: .working)
        } else {
            failureLine(setup.status)
        }
    }

    /// An error line under a row, shown only when the engine's last word was a failure ("✗…").
    /// Success is already the row's tone, and progress has its own treatment.
    @ViewBuilder
    private func failureLine(_ status: String?) -> some View {
        if let status, status.hasPrefix("✗") {
            StatusLabel(status, tone: .error)
        }
    }

    /// "Check Again" on the plan row: re-mints the token (CodexAuth.refreshPlan) so an upgrade
    /// shows up immediately instead of on codex's 8-day timer. Failure just keeps the current
    /// claim; the row never blocks anything.
    private func recheckPlan() {
        guard !planChecking else { return }
        planChecking = true
        Task {
            if let fresh = try? await CodexAuth.refreshPlan() { plan = fresh }
            planChecking = false
        }
    }

    // MARK: - Probes

    private func refresh() async {
        await board.refresh()
        refreshMicSpeech()
        // Match the effective permission used by capture and the setup gates.
        screenRec = Permissions.hasScreenRecording()
        notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if backend == .chatgpt { plan = CodexAuth.currentPlan() }   // pure file read (the JWT claim on disk)
        // First probe done → reveal.
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reduceMotion)) { checked = true }
    }
}

// MARK: - The board

/// The checks Permissions & Health counts, and the count, kept once for the app session. The pane
/// draws those rows from here and the sidebar badge (the Settings gear, the Permissions & Health
/// row) shows `badgeCount`, so the badge always counts exactly what the pane flags. The pane
/// refreshes it on appear, foreground and Check Again; Home refreshes it with its own health probe,
/// so the badge stays live while the pane is closed.
@MainActor @Observable
final class HealthBoard {
    static let shared = HealthBoard()

    private(set) var selectedProtectedSources: [ProtectedLocalSource] = []
    private(set) var unreadableProtectedSources: [ProtectedLocalSource] = []
    let wakeSetup = OvernightWakeSetup()
    /// Also set by the pane's Turn On, which takes effect at once.
    var loginOn = LoginItem.cachedIsEnabled
    private(set) var sourceIssues: [String] = []
    /// The first full check has finished; the badge shows nothing before it.
    private(set) var checked = false
    /// When the engine's CLI and login check last began. They shell out (seconds each), so a
    /// caller may reuse a recent check (`engineMaxAge`).
    @ObservationIgnored private var engineCheckedAt: Date?

    private init() {}

    private var codex: CodexSetup { .shared }
    private var claude: ClaudeSetup { .shared }

    /// The live engine's whole stack, healthy: what the pane's engine section collapses on and
    /// what the count judges. Per engine: ChatGPT = CLI + login; provider limits are enforced
    /// when a task runs, not by a local plan label.
    /// Claude = Claude Code + its login + Codex for computer tasks; custom = CLI + a proven endpoint (codex is the
    /// harness there too). The computer-use driver rides every engine.
    /// Computer use counts only when something is actually missing, denied or failing; helper
    /// grants that are merely unverified since launch (proven when a task starts) are not issues.
    var engineAllGreen: Bool {
        guard ComputerUseSetup.current.ready, !ComputerUseGate.shared.hasConfirmedProblem else { return false }
        switch ModelBackend.current {
        case .chatgpt: return codex.installed && !codex.outdated
                           && codex.loggedIn
        case .claude:  return claude.installed && claude.loggedIn && codex.installed && !codex.outdated
        case .custom:  return codex.installed && !codex.outdated
                           && CustomProvider.current.isUsable
        }
    }

    /// Exactly the terms of the old all-clear, so "All good" shows exactly when it did. Screen
    /// Recording, Microphone & Speech and Notifications are not counted.
    var issueCount: Int {
        let overnight = HealthCaution.overnightRequested()
        return (unreadableProtectedSources.isEmpty ? 0 : 1)
            + (overnight && !wakeSetup.ready ? 1 : 0)
            + (overnight && !loginOn ? 1 : 0)
            + (engineAllGreen ? 0 : 1)
            + sourceIssues.count
    }

    /// The sidebar badge: the count once checked, else nothing.
    var badgeCount: Int { checked ? issueCount : 0 }

    /// Probe every counted check. `engineMaxAge` > 0 reuses an engine check younger than that
    /// (Home's frequent triggers pass five minutes, as HealthCaution caches its login verdict);
    /// the pane always checks afresh.
    func refresh(engineMaxAge: TimeInterval = 0) async {
        ComputerUseGate.shared.refresh()
        selectedProtectedSources = SourceSelection.selectedProtectedSources
        unreadableProtectedSources = selectedProtectedSources.filter { !$0.isReadable }
        loginOn = await LoginItem.refreshedIsEnabled()
        if HealthCaution.overnightRequested() { await wakeSetup.refresh() }
        ComputerUseSetup.current.refresh()
        if engineCheckedAt.map({ Date().timeIntervalSince($0) >= engineMaxAge }) ?? true {
            // Stamped before the shell-outs, so a refresh that starts while this one waits reuses
            // it instead of running the same CLIs again.
            engineCheckedAt = Date()
            // Only the LIVE engine's rows are probed (the login checks shell out, seconds each).
            // Custom backends keep the codex CLI probe (codex is their harness) but skip the login
            // check: no ChatGPT account is needed there.
            switch ModelBackend.current {
            case .chatgpt:
                await codex.refreshInstalled()
                await codex.refreshLoginStatus()   // last: it shells out to `codex login status`
            case .claude:
                await codex.refreshInstalled()
                await claude.refreshInstalled()
                await claude.refreshLoginStatus()  // shells out to `claude auth status`
            case .custom:
                await codex.refreshInstalled()
            }
        }
        recountSources()
        checked = true
    }

    /// Re-read Sources to Retry from what the last analysis wrote, publishing only a change.
    func recountSources() {
        let issues = Self.currentSourceIssues()
        if issues != sourceIssues { sourceIssues = issues }
    }

    private static func currentSourceIssues() -> [String] {
        let defaults = UserDefaults.standard
        var issues: [String] = []
        if AppleCalendarSource.isEnabled,
           let message = AppleCalendarSource.issueMessage(defaults.string(forKey: AppleCalendarSource.issueKey) ?? "") {
            issues.append("Apple Calendar: " + message)
        }
        let mailHealth = defaults.string(forKey: AppleMailHealth.key) ?? ""
        if !AppleMailSelection.accounts.isEmpty, defaults.bool(forKey: AppleMailHealth.needsRetryKey), !mailHealth.isEmpty {
            issues.append(mailHealth)
        }
        let statuses = SourceHealth.readStatuses()
        for slug in MCPSource.kbSlugs() {
            guard let status = statuses[Diagnostics.source(slug)], status != "ok" else { continue }
            let name = ConnectorRegistry.displayName(slug: slug)
            issues.append(status == "connector_auth" ? "\(name): reconnect this source in Knowledge Sources."
                : "\(name): the last analysis did not finish. Run analysis to retry; saved knowledge is retained.")
        }
        let filesEnabled = !CustomRoots.urls.isEmpty || ["desktop", "documents", "downloads"].contains {
            defaults.bool(forKey: "dbg.run." + $0)
        }
        for (source, name, enabled) in [("file", "Files", filesEnabled),
            ("whatsapp", "WhatsApp", defaults.bool(forKey: "dbg.run.whatsapp")),
            ("imessage", "iMessage", defaults.bool(forKey: "dbg.run.imessage")),
            ("notes", "Notes", defaults.bool(forKey: "dbg.run.notes"))] {
            guard enabled, let status = statuses[source], status != "ok" else { continue }
            issues.append(status == "time_cap" ? "\(name): more items remain. Run analysis to continue from saved progress."
                : "\(name): the last analysis did not finish. Check access and run analysis again.")
        }
        return issues
    }
}

#if DEBUG
#Preview("Permissions & Health pane") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            NavigationStack { HealthPane(expandEngine: true) }
                .frame(width: 720, height: 760)
                .environment(\.colorScheme, scheme)
        }
    }
}
#endif
