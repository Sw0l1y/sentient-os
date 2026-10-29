// Passive presentation of app-owned analysis: progress, waiting, pause/resume and retry.
// Production windows never start work on appearance or cancel it on disappearance.
// Developer callers can submit a selected request through the same coordinator.
// Laid out like System Settings › Software Update: a status header (tile, headline, status
// line, the one inline action), grouped sections below it, and the fine print as footers.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI

struct ProcessingView: View {
    private let request: ProcessingRequest?
    let showPrompt: Bool
    let onExitEarly: (() -> Void)?
    var onDone: () -> Void
    @State private var session: ProcessingCoordinator
    private var connectors: [any Connector] { (session.activeRequest ?? request)?.connectors ?? [] }
    private var runGmail: Bool { (session.activeRequest ?? request)?.runGmail ?? false }
    private var runCalendar: Bool { (session.activeRequest ?? request)?.runCalendar ?? false }

    /// Production windows only observe. Creating or closing one never starts or stops work.
    init(onDone: @escaping () -> Void = {}) {
        self.init(session: .shared, onDone: onDone)
    }

    private init(session: ProcessingCoordinator, onDone: @escaping () -> Void = {}) {
        request = nil; showPrompt = false; onExitEarly = nil; self.onDone = onDone
        _session = State(initialValue: session)
    }

    /// Developer callers retain their selected fixture/source configuration, using the same owner.
    init(modelPath: String, connectors: [any Connector], mode: IterativeRun.Mode,
         runGmail: Bool = false, runCalendar: Bool = false, mcpSlugs: [String] = [],
         showPrompt: Bool = false, fullCycle: Bool = false,
         onExitEarly: (() -> Void)? = nil, onDone: @escaping () -> Void) {
        request = ProcessingRequest(modelPath: modelPath, connectors: connectors, mode: mode,
            runGmail: runGmail, runCalendar: runCalendar, mcpSlugs: mcpSlugs, fullCycle: fullCycle)
        self.showPrompt = showPrompt; self.onExitEarly = onExitEarly; self.onDone = onDone
        _session = State(initialValue: .shared)
    }

    /// Developer recordings can resize the production analysis window freely.
    static let resizableDemoKey = "dev.processing.resizableDemo"

    /// Dev Tools → "Demo bar baseline". While `total` > 0, the bar RENDERS as if a big run were
    /// already mid-flight — `baseDone + real done` of `baseTotal`, with the kept/junk counts seeded
    /// proportionally so a 70% bar never sits over "0 kept · 0 junk" — letting a website screen
    /// recording open at "290 of 416" instead of 0. Display-only: the pipeline, marks, and
    /// lifetime counters are untouched.
    static let demoBaseDoneKey = "dev.processing.demoBaseDone"
    static let demoBaseTotalKey = "dev.processing.demoBaseTotal"
    @AppStorage(ProcessingView.demoBaseDoneKey) private var demoBaseDone = 0
    @AppStorage(ProcessingView.demoBaseTotalKey) private var demoBaseTotal = 0

    /// What the bar and counts SHOW — real progress plus the demo baseline (when set).
    private var shownDone: Int { progress.done + (demoBaseTotal > 0 ? demoBaseDone : 0) }
    private var shownTotal: Int { demoBaseTotal > 0 ? demoBaseTotal : progress.total }
    private var shownSurvivors: Int { progress.survivors + (demoBaseTotal > 0 ? demoBaseDone * 58 / 100 : 0) }
    private var shownJunk: Int { progress.junk + (demoBaseTotal > 0 ? demoBaseDone * 36 / 100 : 0) }

    private var state: ProcessingCoordinator.State { session.state }
    private var progress: RunProgress { session.progress }
    private var prepStatus: String { session.prepStatus }
    private var prepSubtext: String? { session.prepSubtext }
    private var updatingExistingKnowledge: Bool { session.updatingExistingKnowledge }
    private var paused: Bool { state == .paused }
    /// The failed screen's inline engine login (the "isn't logged in" fix) — the same shared
    /// setup engines Settings drives, picked by the live backend; `loginStarted` scopes the
    /// auto-notice poll + auto-retry to a login WE opened from that screen.
    @State private var codex = CodexSetup.shared
    @State private var claude = ClaudeSetup.shared
    @State private var loginStarted = false
    /// The 10-minute patience flip for the cloud tail's footer (see `patienceFooter`).
    @State private var patienceLong = false
    /// The cloud tail's live "thoughts" — codex's reasoning/action lines (humanized by
    /// CodexCLI). `pending` updates freely as lines stream in; `trail` is what's actually on
    /// screen — the last three promoted lines, newest most prominent — advanced at a readable
    /// cadence so bursts never strobe. Cleared per phase.
    @State private var thoughtPending: String?
    @State private var thoughtTrail: [Thought] = []
    @State private var thoughtCounter = 0
    /// One promoted thought line. The counter id keeps the trail's ForEach stable even when
    /// codex repeats itself minutes apart.
    private struct Thought: Identifiable, Equatable { let id: Int; let text: String }

    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduce: Bool { motionOverride ?? systemReduced }

    var body: some View {
        // A ZStack (not a Group) so the tasks below attach once, not to whichever branch shows.
        ZStack {
            if case .failed(let failure) = state {
                failedForm(kind: failure.kind, message: failure.message)
            } else if state == .diskFull {
                failedForm(kind: .diskFull, message: "")
            } else {
                statusForm
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if let request, session === ProcessingCoordinator.shared { session.requestNow(request, trigger: .developer) }
        }
        .onChange(of: session.thought) { _, line in
            if let line, let text = Self.thought(line) { thoughtPending = text }
        }
        .onChange(of: session.prepStatus) { _, _ in thoughtPending = nil; thoughtTrail = [] }
        // The cloud tail's pump, alive only while preparing. Promotes the newest streamed line at
        // a readable pace — raw JSONL arrives in bursts that would strobe the rows into noise.
        // Dedup is free: identical consecutive lines (codex emits items as both .started and
        // .completed) never extend the trail. After 10 minutes the patience footer turns warmer.
        .task(id: state == .preparing) {
            guard state == .preparing else { return }
            let started = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.4))
                if Task.isCancelled { return }
                if !patienceLong, Date().timeIntervalSince(started) >= 600 {
                    withAnimation(Motion.gated(Motion.standard, reduceMotion: reduce)) { patienceLong = true }
                }
                if let next = thoughtPending, next != thoughtTrail.last?.text {
                    thoughtCounter += 1
                    thoughtTrail.append(Thought(id: thoughtCounter, text: next))
                    if thoughtTrail.count > 3 { thoughtTrail.removeFirst() }
                }
            }
        }
    }

    // MARK: Status form (every state except failed)

    private var statusForm: some View {
        PaneForm(maxWidth: PageMetrics.setupPage) {
            Section {
                statusHeader
            } footer: {
                if session.isBusy || paused || isWaiting { Text(footerCopy) }
            }
            switch state {
            case .idle, .scheduled, .waiting, .paused, .stopping:
                waitingSections
            case .processing:
                resultsSection(shown: true)
                if progress.lastPath != nil { justProcessedSection }   // files have a path; chat windows do too
            case .preparing:
                thinkingSection
            case .completed:
                if progress.total > 0 || progress.done > 0 { resultsSection(shown: false) }
                completedSections
            default:
                EmptyView()   // loading: the header carries it
            }
            if !progress.sourceReadFailures.isEmpty { retrySection }
            if showPrompt { devSections }
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconTile(.analysis, size: 40)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                statusLine
                if state == .preparing, let prepSubtext {
                    Text(prepSubtext).font(.caption).foregroundStyle(.secondary)
                }
                if state == .processing {
                    ProgressView(value: shownTotal > 0 ? min(1, Double(shownDone) / Double(shownTotal)) : 0)
                        .padding(.top, Space.xs)
                    Text("\(shownDone.formatted()) of \(shownTotal.formatted()) · \(percent)%")
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Space.m)
            trailingAction
        }
        .padding(.vertical, Space.xs)
    }

    /// The coordinator's own status sentence. Loading names its leg with the old hero symbol;
    /// completion carries its tone glyph so the result is never told by colour alone.
    @ViewBuilder private var statusLine: some View {
        if state == .loadingModel {
            Label(session.statusLine, systemImage: connectors.isEmpty ? cloudIcon : "cpu")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("processing.statusLine")
        } else if state == .completed {
            StatusLabel(session.statusLine, tone: needsAnotherPass ? .warning : .ok)
                .accessibilityIdentifier("processing.statusLine")
        } else {
            Text(session.statusLine)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("processing.statusLine")
        }
    }

    /// The header's trailing controls. At most one `.borderedProminent` at a time: Analyze Now
    /// (idle, scheduled) or Done (completed) — never both.
    private var trailingAction: some View {
        HStack(spacing: Space.s) {
            if state == .loadingModel || state == .preparing {
                ProgressView().controlSize(.small)
            }
            if session.isBusy || paused || isWaiting {
                Button(paused ? "Resume Analysis" : "Pause Analysis") {
                    if paused { session.retry() } else { session.pause() }
                }
                .buttonStyle(.bordered)
                .disabled(state == .stopping)
            }
            if state == .scheduled || state == .idle {
                Button("Analyze Now") { session.requestNow() }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isBusy || session.isSuspended)
                    .accessibilityIdentifier("analysis.startNow")
            }
            if state == .completed {
                if needsAnotherPass {
                    Button("Retry Analysis") { session.retry() }
                        .buttonStyle(.bordered)
                }
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .fixedSize()
    }

    private var headline: String {
        AnalysisStatusText.headline(state: state, progress: progress, needsAnotherPass: needsAnotherPass,
                                    prepStatus: prepStatus, onDevice: !connectors.isEmpty, cloudLabel: cloudLabel)
    }

    private var footerCopy: String {
        paused ? "Your progress is saved. Resume when you’re ready."
            : isWaiting ? "Keep Sentient open. Analysis will start when your Mac is ready."
            : "You can leave this page. Analysis continues in the background."
    }

    /// Cloud-only takeover (no on-device connectors): name the leg we're starting.
    private var cloudIcon: String { runGmail && !runCalendar ? "envelope" : (runCalendar && !runGmail ? "calendar" : "cloud") }
    private var cloudLabel: String {
        runGmail && !runCalendar ? "Connecting to Gmail"
            : (runCalendar && !runGmail ? "Connecting to Calendar" : "Connecting to the cloud")
    }

    private var isWaiting: Bool {
        if case .waiting = state { return true }
        return false
    }

    private var needsAnotherPass: Bool {
        AnalysisStatusText.needsAnotherPass(notice: session.record.notice, progress: progress)
    }

    private var percent: Int {
        shownTotal > 0 ? Int(Double(shownDone) / Double(shownTotal) * 100) : 0
    }

    // MARK: Waiting, scheduled, idle, paused, stopping

    @ViewBuilder private var waitingSections: some View {
        if state == .waiting(.model) {
            Section("On-Device Model") {
                OnboardingModelDownloadView(download: ModelDownload.shared, compact: true)
            }
        }
        let showsDetail = isWaiting && state != .waiting(.model)
        let notice = isWaiting ? nil : session.record.notice
        if showsDetail || notice != nil || state == .scheduled {
            Section {
                if showsDetail {
                    Text(session.waitingDetail).fixedSize(horizontal: false, vertical: true)
                } else if let notice {
                    StatusLabel(notice, tone: .info)
                }
                if state == .scheduled {
                    LabeledContent("Next Run", value: ProcessingCoordinator.scheduleLabel(
                        OvernightScheduler.nextOccurrence(minutesSinceMidnight: OvernightScheduler.configuredMinutes)))
                }
            } header: {
                Text("Details")
            } footer: {
                Text(readyLine)
            }
        } else {
            Section {} footer: { Text(readyLine) }
        }
    }

    private var readyLine: String {
        CodexAuth.knowledgeBaseOnly ? "Your main window is ready to use." : "Sidekick is ready to use in your main window."
    }

    // MARK: Processing: results and the item just processed

    /// `shown` adds the demo baseline (the live run); a finished run reports its real counts.
    private func resultsSection(shown: Bool) -> some View {
        Section("Results") {
            LabeledContent("Kept") { Text(shown ? shownSurvivors : progress.survivors, format: .number).monospacedDigit() }
            LabeledContent("Junk") { Text(shown ? shownJunk : progress.junk, format: .number).monospacedDigit() }
            if progress.quietReads > 0 {
                LabeledContent("Quiet") { Text(progress.quietReads, format: .number).monospacedDigit() }
            }
            if progress.failed > 0 {
                LabeledContent("Failed") { Text(progress.failed, format: .number).monospacedDigit() }
            }
            if shown, let last = progress.lastSeconds {
                LabeledContent("Time per Item") { Text(String(format: "%.1f s", last)).monospacedDigit() }
            }
        }
    }

    private var justProcessedSection: some View {
        Section(justProcessedTitle) {
            HStack(alignment: .top, spacing: Space.m) {
                thumbnail.frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        if let title = progress.lastTitle {
                            Text(title).font(.headline)
                                .foregroundStyle(progress.lastVerdict == .junk ? .secondary : .primary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        verdictLabel
                    }
                    summaryText
                    pathDateLine
                }
                .id(progress.done)
                .transition(.opacity)
            }
            .animation(Motion.gated(Motion.standard, reduceMotion: reduce), value: progress.done)
        }
    }

    /// "Reading Source", "Summary", "Source Checked", "Needs Attention", or "Just Processed".
    private var justProcessedTitle: String {
        guard let source = progress.sourceRead else { return "Just Processed" }
        return switch source.status {
        case .reading: "Reading Source"
        case .summarized: "Summary"
        case .quiet: "Source Checked"
        case .failed: "Needs Attention"
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let source = progress.sourceRead {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous).fill(.quaternary)
                if source.status == .reading {
                    Image(systemName: "arrow.down.doc")
                        .font(.title2).foregroundStyle(.secondary)
                        // A symbol effect is not an Animation, so Motion.gated cannot wrap it.
                        .symbolEffect(.pulse, isActive: !reduce && !ProcessInfo.processInfo.isLowPowerModeEnabled)
                } else if source.status == .failed {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2).foregroundStyle(.orange)
                        .accessibilityLabel("Failed")
                } else {
                    Image(systemName: "text.book.closed")
                        .font(.title2).foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(source.status != .failed)
        } else {
            FileThumbnail(path: progress.lastFilePath, size: 48)
                .id(progress.done)
                .transition(.opacity)
        }
    }

    /// Sensitive and junk get a status label; kept items get none.
    @ViewBuilder private var verdictLabel: some View {
        if progress.lastVerdict == .sensitive {
            StatusLabel("Sensitive", tone: .error, systemImage: "lock.fill")
        } else if progress.lastVerdict == .junk {
            StatusLabel("Junk", tone: .off)
        }
    }

    /// Survivors carry a summary; junk/sensitive often don't — show a graceful placeholder so the
    /// row never looks blank. Source content is redacted when sensitive; the app-authored
    /// explanation stays readable.
    @ViewBuilder private var summaryText: some View {
        let verdict = progress.lastVerdict
        let fallback = verdict == .sensitive ? "Held back: sensitive."
            : verdict == .junk ? "Nothing worth keeping here." : ""
        let body = progress.lastSummary ?? fallback
        if !body.isEmpty {
            Text(body)
                .font(.callout)
                .italic(progress.lastSummary == nil)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .blur(radius: verdict == .sensitive && progress.lastSummary != nil ? 6 : 0)
                .accessibilityHidden(verdict == .sensitive && progress.lastSummary != nil)
        }
    }

    @ViewBuilder private var pathDateLine: some View {
        if let path = progress.lastPath {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(path).lineLimit(1).truncationMode(.middle)
                if let date = progress.lastItemDate {
                    Spacer(minLength: 0)
                    Text(date, format: .dateTime.month(.abbreviated).day().year()).fixedSize()
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Preparing: the cloud tail

    /// Up to three live lines from codex, newest at the bottom and most prominent, older ones
    /// stepping down to secondary and tertiary. "Starting…" until the first thought lands.
    private var thinkingSection: some View {
        Section {
            if thoughtTrail.isEmpty {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Starting…").foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(thoughtTrail.enumerated()), id: \.element.id) { i, thought in
                    Text(thought.text)
                        .font(.subheadline)
                        .lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(trailStyle(age: thoughtTrail.count - 1 - i))
                }
            }
        } header: {
            Text("Thinking")
        } footer: {
            patienceFooter
        }
        .animation(Motion.gated(Motion.standard, reduceMotion: reduce), value: thoughtTrail)
    }

    private func trailStyle(age: Int) -> Color {
        switch age {
        case 0: Color.primary
        case 1: Color.secondary
        default: Color(nsColor: .tertiaryLabelColor)
        }
    }

    /// The expectation-setter under the cloud phases: how long it takes, that the app must stay
    /// open, and that the ask is first-run-only (later runs happen overnight).
    private var patienceFooter: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(patienceLong ? "Still working — keep Sentient open"
                 : (updatingExistingKnowledge ? "Updating your knowledge" : "Building your knowledge"))
                .font(.subheadline.weight(.semibold))
            Label("Keep Sentient open in your menu bar.", systemImage: "macbook")
            Text(updatingExistingKnowledge
                 ? "Your existing knowledge stays in place while this update is prepared. Large libraries can take several passes; completed work is kept."
                 : "The first analysis can take several passes for a large library. Completed work is kept, and future updates can run overnight while Sentient stays open in your menu bar.")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One streamed codex line → a clean single-line thought (nil = nothing showable). Shell
    /// commands and structured output are dropped outright — "$ /bin/zsh -lc …" and the research
    /// stage's closing JSON verdict ({"ready":…}) are machinery, not narration; reasoning,
    /// tool calls, and web searches make the cut. The humanized lines can carry markdown bold +
    /// multi-paragraph reasoning; a row wants one quiet line, so markup is stripped and
    /// paragraphs join with the house "·".
    private static func thought(_ raw: String) -> String? {
        guard !raw.hasPrefix("$ ") else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("{"), !trimmed.hasPrefix("[") else { return nil }
        let flat = raw.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return flat.isEmpty ? nil : flat
    }

    // MARK: Completed

    @ViewBuilder private var completedSections: some View {
        if progress.mailIncomplete || progress.mailDeferred > 0 || session.record.notice != nil {
            Section("Needs Attention") {
                if progress.mailIncomplete || progress.mailDeferred > 0 {
                    StatusLabel(UserDefaults.standard.string(forKey: AppleMailHealth.key)
                                ?? "Apple Mail will resume during the next analysis.", tone: .warning)
                }
                if let notice = session.record.notice {
                    StatusLabel(notice, tone: .warning)
                }
            }
        }
        if progress.sourceRead?.status == .summarized || progress.sourceRead?.status == .quiet {
            justProcessedSection
        }
    }

    // MARK: Failed

    /// The failed form for BOTH failure kinds the takeover can end in: the cloud tail's
    /// classified `CycleFailure` (kind + its own message) and the on-device read's disk-full stop
    /// (kind `.diskFull`, no message of its own). Each cause gets its own symbol, title and body
    /// and, where there's something to click, the fix next to Retry.
    private func failedForm(kind: OvernightCaution.Kind?, message: String) -> some View {
        PaneForm(maxWidth: PageMetrics.setupPage) {
            Section {
                ContentUnavailableView {
                    Label(AnalysisStatusText.failureTitle(kind), systemImage: AnalysisStatusText.failureSymbol(kind))
                } description: {
                    Text(AnalysisStatusText.failureBody(kind: kind, message: message))
                } actions: {
                    HStack(spacing: Space.s) {
                        Button { (onExitEarly ?? onDone)() } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.bordered)
                        failureActions(kind)
                    }
                }
                .frame(maxWidth: .infinity)
                if loginStarted, (ModelBackend.current == .claude ? claude.loggingIn : codex.loggingIn) {
                    Text("A browser window opened. Finish signing in there; I’ll retry on my own.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            if !progress.sourceReadFailures.isEmpty { retrySection }
            if showPrompt { devSections }
        }
        // The browser-login auto-notice, same as Settings → Health and onboarding: while our
        // login is out, poll the active engine's login status (the login process self-exits
        // once the sign-in lands, no confirm button); the moment it reads logged-in, retry the
        // cycle on our own. Leaving the failed state cancels the poll.
        .task(id: loginStarted) {
            guard loginStarted else { return }
            let isClaude = ModelBackend.current == .claude
            while !Task.isCancelled, !(isClaude ? claude.loggedIn : codex.loggedIn) {
                try? await Task.sleep(for: .seconds(1.5))
                if isClaude { await claude.refreshLoginStatus() }
                else { await codex.refreshLoginStatus() }
            }
            guard !Task.isCancelled, (isClaude ? claude.loggedIn : codex.loggedIn) else { return }
            loginStarted = false
            // Unstructured on purpose: the retry flips state out of .failed, which tears THIS
            // task down — the run must survive that.
            session.retry()
        }
    }

    /// Exactly one `.borderedProminent` per cause: the fix when there is one, otherwise Retry.
    @ViewBuilder private func failureActions(_ kind: OvernightCaution.Kind?) -> some View {
        switch kind {
        case .loggedOut:
            Button("Retry") { session.retry() }
                .buttonStyle(.bordered)
            if ModelBackend.current == .claude {
                Button("Sign In to Claude") { loginStarted = true; claude.startLogin(force: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(claude.loggingIn)
            } else {
                Button("Log In to Codex") { loginStarted = true; Task { await codex.startLogin(force: true) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(codex.loggingIn)
            }
        case .diskFull:
            Button("Retry") { session.retry() }
                .buttonStyle(.bordered)
            Button("Manage Storage…") { DiskSpace.openStorageSettings() }
                .buttonStyle(.borderedProminent)
        default:
            Button("Retry") { session.retry() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Sources to Retry, and the developer prompt

    private struct RetryRow: Identifiable {
        let name: String
        let problem: String
        var id: String { name }
    }

    private var retryRows: [RetryRow] {
        progress.sourceReadFailures.keys.sorted().map {
            RetryRow(name: $0, problem: progress.sourceReadFailures[$0] ?? "The read did not finish.")
        }
    }

    private var retrySection: some View {
        let rows = retryRows
        return Section {
            Table(rows) {
                TableColumn("Source", value: \.name).width(min: 100, ideal: 140)
                TableColumn("Problem", value: \.problem)
            }
            .tableStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: CGFloat(min(rows.count, 6)) * 24 + 28)
            .scrollDisabled(rows.count <= 6)
        } header: {
            Text("Sources to Retry")
        } footer: {
            Text("Run analysis again to retry these sources.")
        }
    }

    /// DEV-only: the EXACT prompt fed to the model for the item currently shown, and its path.
    @ViewBuilder private var devSections: some View {
        let prompt = progress.lastPrompt ?? ""
        Section {
            LabeledContent("Last Item") {
                Text(progress.lastPath ?? "—")
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
            }
            ScrollView {
                Text(prompt.isEmpty ? "—" : prompt)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(prompt.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
        } header: {
            HStack {
                Text("Prompt")
                Spacer()
                Text("\(prompt.count) characters").monospacedDigit()
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
/// Frozen presentation fixtures never submit work to the app-owned coordinator.
extension ProcessingView {
    static func appleMailPreview() -> ProcessingView {
        let preview = ProcessingCoordinator.preview(state: .processing)
        let view = ProcessingView(session: preview)
        var progress = RunProgress()
        progress.total = 600; progress.done = 63; progress.junk = 63
        progress.lastPath = "Apple Mail"
        progress.lastItemDate = ISO8601DateFormatter().date(from: "2026-09-06T12:00:00Z")
        progress.lastTitle = "Weekly reading digest"
        progress.lastSummary = "A roundup of articles and product updates for this week."
        progress.lastVerdict = .junk; progress.lastSeconds = 3.2
        preview.setPreviewProgress(progress)
        return view
    }

    static func connectorPreview(_ status: String) -> ProcessingView {
        let preview = ProcessingCoordinator.preview(state: status.hasPrefix("completed") ? .completed : .processing)
        let view = ProcessingView(session: preview)
        var progress = RunProgress()
        progress.total = 1
        progress.beginSourceRead(name: "Granola", label: "recent 30-day note sample", prompt: "")
        if status == "summary" || status == "completed-summary" {
            progress.done = 1; progress.survivors = 1
            progress.finishSourceRead(name: "Granola", label: "recent 30-day note sample",
                summary: "The user and their team agreed to review the prototype together next week.", items: 3)
        } else if status == "quiet" {
            progress.done = 1; progress.quietReads = 1
            progress.finishSourceRead(name: "Notion", label: "initial page sample", summary: nil, items: 6)
        } else if status == "failed" || status == "completed" {
            progress.done = 1
            progress.failSourceRead(name: "Granola", message: "The service returned a response Sentient couldn't verify.")
        }
        preview.setPreviewProgress(progress)
        return view
    }

    static func preparingPreview() -> ProcessingView {
        var view = ProcessingView(session: .preview(state: .preparing))
        view._thoughtPending = State(initialValue: "The corpus resolves into five durable domains: education, AI research, creative interests…")
        view._thoughtTrail = State(initialValue: [
            Thought(id: 1, text: "Reading the week's summaries for durable facts worth keeping long-term…"),
            Thought(id: 2, text: "Searched the web: \"YC S26 interview format\" — 6 results"),
            Thought(id: 3, text: "The corpus resolves into five durable domains: education, AI research, creative interests…"),
        ])
        view._thoughtCounter = State(initialValue: 3)
        return view
    }
}

#Preview("Connector reading") {
    ProcessingView.connectorPreview("reading").frame(width: 680, height: 720)
}
#Preview("Connector summary") {
    ProcessingView.connectorPreview("summary").frame(width: 680, height: 720)
}
#Preview("Connector needs another try") {
    ProcessingView.connectorPreview("completed").frame(width: 680, height: 720)
}

#Preview("Preparing — cloud tail") {
    ProcessingView.preparingPreview()
        .frame(width: 1160, height: 780)
}
#Preview("Apple Mail message date") {
    ProcessingView.appleMailPreview().frame(width: 1040, height: 800)
}
#endif
