//
//  HomeView.swift
//  Sentient OS macOS
//
//  HOME — the app's main surface, and the product itself: Proactive Intelligence. It is a
//  conversation with Sentient, laid out the way Messages lays out a conversation (SPEC-D1 S1):
//    · a notice row docked at the top (HomeNotices: one notice, most severe first)
//    · the page itself, one reading column on the text background:
//        Today (HomeToday) — the opening of the conversation: the greeting, the day's status
//          and the suggestion list the morning run prepared (each one the AI already did the
//          work for; clicking is the user's fire — Privacy Constitution: we offer, they fire),
//          then quick replies;
//        or the conversation (SidekickTranscript);
//        or a Finish Setting Up example opened from the inspector (a drill-in with Back).
//    · the Ask field floating at the bottom (HomeAskBar)
//    · an inspector on the right: "Finish Setting Up" while personal setup is pending,
//      otherwise the day's suggestions beside the conversation.
//  `SidekickPresentation.surface` is the only switch between Today and the conversation, so the
//  notch, "View in Chat", the attention policy and the labs keep driving it.
//
//  The chrome is the window's own: the sidebar navigates, the root titles the window, and Home's
//  toolbar carries Analysis, Double Tap, Search and the More menu — only while Home is showing.
//
//  LEGACY KNOWLEDGE-BASE-ONLY DIAGNOSTIC (previewKBOnly): cards never come and the Ask field is
//  disabled; Today shows the preview group (upgrade CTA + Reset jump), with the gift row above it
//  when there is one. Once the plan claim reads Plus it becomes the reset-and-rebuild note.
//
//  The model half (ForYouModel: deal · run · dismiss) is below the view, unchanged.
//
//  Doc: Views/Documentation - Views - Home, Processing & Shared UI.md · cards + the CodexCLI seam:
//  Briefing.swift.
//

import SwiftUI
import AppKit

struct HomeView: View {
    var isPresented = true

    // Live context from RootView (the analyze/source switchboard).
    var thingsUnderstood: Int = 0
    var sources: HomeSources = .init()
    var customRoots: [URL] = []        // session folders from RootView — shown in the Analysis popover, like Dev Tools
    var deck: BriefingDeck = .jesai    // .real → real proactive cards from latest(); .jesai/.launch → a demo deck
    var previewKBOnly = false          // preview-only: force the knowledge-base-only state
    var onAnalyze: () -> Void = {}
    var onShowDevTools: () -> Void = {}   // kept for callers; Developer Tools now opens from the sidebar and Debug menu
    var onFinishSetup: () -> Void = {}

    /// Retained diagnostic/legacy mode. Normal Free/Go users receive full Home; account labels
    /// never imply that Sidekick is unavailable. Migration clears the historical mode flag.
    private var kbOnly: Bool { previewKBOnly || CodexAuth.knowledgeBaseOnly }
    var previewUpgraded: Bool? = nil   // preview-only: force the upgraded/not-upgraded note
    /// A kbOnly user whose claim now reads full — they upgraded (codex's own 8-day refresh, the
    /// Health pane's Re-check, or the crossroads all re-mint it). Re-read every appearance, so
    /// the preview note flips to the "reset & rebuild" note without any push machinery.
    @State private var planUpgraded = false

    @Environment(AppState.self) private var appState

    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reducedMotion: Bool { motionOverride ?? systemReducedMotion }
    private var standardMotion: Animation? { Motion.gated(Motion.standard, reduceMotion: reducedMotion) }
    private var presentation: SidekickPresentation { appState.sidekickPresentation }
    private var model: ForYouModel { presentation.cards }
    private var conversation: SidekickConversation { appState.commandCoordinator.run.conversation }
    private var inConversation: Bool { !kbOnly && presentation.surface == .conversation }
    private var personalSetupPending: Bool {
        !appState.hasCompletedPersonalSetup && !appState.processing.initialComplete
    }
    private var needsPersonalSetup: Bool {
        !kbOnly && deck == .real && personalSetupPending
    }
    @State private var selectedPersonalFeature: HomePersonalFeature?
    @State private var previewAreaHeight: CGFloat = 520
    @State private var composerFocusRequest = 0
    @State private var searchFocus = 0
    /// The inspector's two wishes: Finish Setting Up opens by default; Suggestions on request.
    @State private var inspectorWanted = true
    @State private var suggestionsWanted = false
    // The opened card's sheet.
    @State private var letter: Briefing?
    @State private var letterShown = false
    @State private var showAnalysis = false
    @State private var showDoubleTap = false
    @State private var showWhatsAppPicker = false
    @State private var showIMessagePicker = false
    @State private var showGmailConnect = false
    @State private var showCalendarConnect = false
    @State private var showAppleMailPicker = false
    @State private var codex = CodexSetup.shared
    @State private var showCodexSignIn = false
    @State private var dismissedCodexSignInReminder = false
    /// The morning-after caution (last night's scheduled run hit a known snag) — nil = no notice.
    @State private var caution: OvernightCaution.Record?
    /// Kept separately from whole-cycle failures: successfully processing the other sources
    /// must not erase a skipped connector. AppStorage also updates a visible home after 3 AM.
    @AppStorage(ConnectorCaution.key) private var connectorCautionData = Data()
    /// The LIVE health issue (essential perms · codex · computer use) — HealthCaution's ladder;
    /// nil = healthy or muted. Outranks the morning-after caution in the notice slot.
    @State private var liveIssue: HealthCaution.Issue?
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    private var computerSetup: ComputerUseSetup {
        .instance(for: .selected(for: ModelBackend(rawValue: backendRaw) ?? .chatgpt))
    }

    // Chat selections the Analysis popover's WhatsApp/iMessage chips pick into (same keys as SourceSelection).
    @AppStorage("dbg.whatsapp.chats") private var whatsappCSV = ""
    @AppStorage("dbg.run.whatsapp")   private var runWhatsApp = false
    @AppStorage("dbg.imessage.chats") private var imessageCSV = ""
    @AppStorage("dbg.run.imessage")   private var runIMessage = false

    // MARK: The page

    /// The middle of the page (Today, the conversation, or an example), with the notice row
    /// docked above it and the Ask field floating below it.
    ///
    /// The notice row is stacked above the page, not a top safe-area inset of it: as an inset it
    /// made the scroll view's top edge the bottom of the notice row, and the system's top scroll
    /// edge effect draws its dividing line along that edge (the row is opaque, so nothing ever
    /// scrolled under it anyway). Without a notice the page meets the toolbar like every other page.
    private var homePage: some View {
        VStack(spacing: 0) {
            notices
            Group {
                if let feature = selectedPersonalFeature {
                    featurePreview(feature)
                } else if inConversation {
                    transcript
                        .transition(pageSwap)
                } else {
                    today
                        .transition(pageSwap)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewAreaHeight = $0 }
            .floatingBar(edge: .bottom) { askBar }
            .softScrollEdge(.bottom)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .pageSubtitle(subtitle, page: .home)
        .animation(standardMotion, value: presentation.surface)
        .animation(standardMotion, value: selectedPersonalFeature)
    }

    /// Switching what the page shows (Today, the conversation, an example) is a swap, not a
    /// crossfade: the outgoing page fades out first and the incoming one fades in after it, the way
    /// Messages changes conversations, so no frame shows both texts at once. Each half carries its
    /// own animation, so the swap is the same whichever transaction triggered it; Reduce Motion
    /// (or Low Power Mode) makes it an instant swap.
    private var pageSwap: AnyTransition {
        guard let fadeOut = Motion.gated(Motion.quick, reduceMotion: reducedMotion),
              let fadeIn = Motion.gated(Motion.standard.delay(Self.pageSwapFadeOut), reduceMotion: reducedMotion)
        else { return .identity }
        return .asymmetric(insertion: .opacity.animation(fadeIn), removal: .opacity.animation(fadeOut))
    }

    /// `Motion.quick`'s duration: the incoming page waits until the outgoing one has faded out.
    private static let pageSwapFadeOut: TimeInterval = 0.15

    /// The window subtitle: what this page is and its state, never an action.
    private var subtitle: String {
        if let feature = selectedPersonalFeature { return "\(feature.title) Example" }
        if inConversation { return appState.commandCoordinator.run.isRunning ? "Working…" : "Conversation" }
        return Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var observedHome: some View {
        homePage
        .background(SidekickWindowPresence { active in
            presentation.windowActive = active
            updateConversationVisibility()
        })
        .onAppear {                        // every appearance starts fresh: sealed envelope, full deal
            letter = nil
            letterShown = false
            model.coordinator = appState.commandCoordinator
            let cards = model
            appState.commandCoordinator.run.proactiveCards = { [weak cards] in
                cards?.sidekickActions ?? []
            }
            if !appState.isUninstalling { model.ensureVisit(deck: deck) }
            presentation.visit(conversation: conversation, running: appState.commandCoordinator.run.isRunning,
                               pending: appState.commandCoordinator.run.recovery.isPending)
            updateConversationVisibility()
            planUpgraded = previewUpgraded ?? (kbOnly && CodexAuth.currentPlan()?.tier == .full)
            caution = OvernightCaution.latest()
            probeHealth()
        }
        .onDisappear { conversation.isVisible = false }
        .onChange(of: presentation.surface) { _, surface in
            // Leaving the conversation closes its search (the field only searches the transcript).
            if surface == .suggestions && presentation.searchShown { endSearch() }
            updateConversationVisibility()
        }
        .onChange(of: selectedPersonalFeature) { _, _ in updateConversationVisibility() }
        .onChange(of: needsPersonalSetup) { _, needed in
            if !needed { selectedPersonalFeature = nil }
        }
        .onChange(of: conversation.navigationRequest) { _, id in
            if id != nil { showConversation() }
        }
        .onChange(of: appState.commandCoordinator.run.recovery.content?.id) { _, id in
            if id != nil && isPresented && presentation.windowActive { showConversation() }
        }
        .onChange(of: appState.commandCoordinator.run.isRunning) { _, running in
            if !running { model.reconcileFinishedRuns() }
            else { showConversation() }
        }
        .onChange(of: isPresented) { _, visible in
            updateConversationVisibility()
            if !visible { presentation.clearChatConfirmationShown = false }
            if visible {
                model.ensureVisit(deck: deck)
                presentation.visit(conversation: conversation, running: appState.commandCoordinator.run.isRunning,
                                   pending: appState.commandCoordinator.run.recovery.isPending)
                planUpgraded = previewUpgraded ?? (kbOnly && CodexAuth.currentPlan()?.tier == .full)
                caution = OvernightCaution.latest()
                probeHealth()
            } else {
                showAnalysis = false
                showDoubleTap = false
                showCodexSignIn = false
                selectedPersonalFeature = nil
            }
        }
    }

    private var lifecycleHome: some View {
        observedHome
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if ProcessInfo.processInfo.environment["SENTIENT_SELFTEST"] == nil {
                Task { await MailAccountCloud.shared.retryPendingSync() }
            }
            // The user may just have fixed something in System Settings (or a cycle cleared last
            // night's caution) — re-probe so the notice melts away the moment they return.
            withAnimation(standardMotion) { caution = OvernightCaution.latest() }
            probeHealth()
            Task { await refreshCodexSignIn() }
        }
        .task(id: canCheckCodexSignIn) { await refreshCodexSignIn() }
        .onChange(of: canOfferCodexSignIn) { _, _ in offerCodexSignInIfNeeded() }
        .onChange(of: codex.loggedIn) { _, signedIn in
            if signedIn {
                showCodexSignIn = false
                dismissedCodexSignInReminder = false
                probeHealth(forceCodexRecheck: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            guard !appState.isUninstalling else { return }
            model.ensureVisit(deck: deck)
        }
        .onChange(of: deck) { _, v in
            // The teardown's defaults wipe re-publishes the deck key — never re-deal mid-uninstall.
            guard !appState.isUninstalling else { return }
            model.beginVisit(deck: v)                               // mode flip → re-deal
        }
        .onChange(of: computerSetup.ready) { _, _ in probeHealth() }
        .onChange(of: computerSetup.isInstalling) { _, _ in probeHealth() }
        .onChange(of: ComputerUseGate.shared.automation) { _, _ in probeHealth() }
        .onChange(of: backendRaw) { _, _ in
            if backendRaw != ModelBackend.chatgpt.rawValue { showCodexSignIn = false }
            probeHealth()
        }
        .onChange(of: appState.isUninstalling) { _, tearing in
            // Uninstall began → take every suggestion off the page; a cancel deals them back in.
            if tearing {
                showCodexSignIn = false
                withAnimation(standardMotion) { model.clear() }
            }
            else { model.beginVisit(deck: deck) }
        }
        .animation(standardMotion, value: model.entries.isEmpty)
    }

    var body: some View {
        lifecycleHome
        .toolbar { toolbarActions }
        .inspector(isPresented: inspectorBinding) {
            inspectorContent
                .inspectorColumnWidth(min: 240, ideal: 260, max: 320)
        }
        // "Clear Chat?" is hosted once, here, because the More menu item that raises it is torn
        // down with the menu.
        .sidekickClearChatConfirmation(coordinator: appState.commandCoordinator, presentation: presentation)
        .sheet(isPresented: $showWhatsAppPicker) {
            ChatPicker(sourceName: "WhatsApp", loadChats: { try WhatsAppSource().listChats() },
                       initialSelection: Set(whatsappCSV.split(separator: ",").map(String.init))) { sel in
                whatsappCSV = sel.sorted().joined(separator: ","); runWhatsApp = !sel.isEmpty
            }
        }
        .sheet(isPresented: $showAppleMailPicker) {
            AppleMailPicker(initialSelection: AppleMailSelection.accounts) { accounts in
                UserDefaults.standard.set(accounts.sorted().joined(separator: ","), forKey: AppleMailSelection.key)
            }
        }
        .sheet(isPresented: $showIMessagePicker) {
            ChatPicker(sourceName: "iMessage", loadChats: { try iMessageSource().listChats() },
                       initialSelection: Set(imessageCSV.split(separator: ",").map(String.init))) { sel in
                imessageCSV = sel.sorted().joined(separator: ","); runIMessage = !sel.isEmpty
            }
        }
        // Gmail / Calendar connect sheets — the SAME sheets Dev Tools opens (connect / select / remove).
        .sheet(isPresented: $showGmailConnect) { CloudConnectSheet(.gmail) }
        .sheet(isPresented: $showCalendarConnect) { CloudConnectSheet(.calendar) }
        .sheet(isPresented: $letterShown) { letterSheet }
        .sheet(isPresented: $showCodexSignIn, onDismiss: {
            Task { await refreshCodexSignIn() }
        }) { ChatGPTSignInSheet() }
    }

    // MARK: Today

    private var today: some View {
        HomeToday(greeting: greeting,
                  kbOnly: kbOnly,
                  needsPersonalSetup: needsPersonalSetup,
                  initialComplete: appState.processing.initialComplete,
                  conversation: conversation,
                  entries: visibleEntries,
                  row: { suggestionRow($0, inInspector: false) },
                  analysisBlock: showsAnalysisBlock ? AnyView(analysisBlock) : nil,
                  kbOnlyBlock: kbOnly ? AnyView(kbOnlyBlock) : nil,
                  reduceMotion: reducedMotion,
                  onShowConversation: showConversation,
                  onStarter: fillStarter)
    }

    /// The suggestions on the page: dealt (the deal stagger drives insertion) and not dismissed.
    private var visibleEntries: [ForYouModel.Entry] {
        model.entries.filter { $0.dealt && $0.flight == nil }
    }

    /// One suggestion row, wired to the model exactly as the old card was. In the inspector the
    /// conversation is already on screen, so "View in Chat" returns the transcript to its latest
    /// messages, where the task's live work is.
    private func suggestionRow(_ entry: ForYouModel.Entry, inInspector: Bool) -> HomeSuggestionRow {
        let openConversation: (() -> Void)?
        if entry.action == nil {
            openConversation = nil
        } else if inInspector {
            let presentation = presentation, conversation = conversation
            openConversation = { Task { await presentation.load(.latest, conversation: conversation) } }
        } else {
            openConversation = showConversation
        }
        return HomeSuggestionRow(
            briefing: entry.b, action: entry.action, phase: entry.phase, liveLines: entry.liveLines,
            fireDimmed: appState.commandCoordinator.run.isRunning
                && entry.action.map { ProactiveExecutor.isFireable($0) } == true,
            onOpen: { openLetter(entry.b) },
            onOffer: { model.run(entry.id) },
            onOpenEnvelope: {
                // A dismissal in flight must not reopen the removed card's letter.
                guard let current = model.entry(entry.id), current.flight == nil else { return }
                model.unsealWelcome()
                openLetter(current.b)
            },
            onStop: entry.action != nil ? { model.stopRun(entry.id) } : nil,
            onOpenConversation: openConversation,
            onDismiss: { model.dismiss(entry.id, toward: CGSize(width: 0, height: -1)) })
    }

    /// A starter fills the Ask field and focuses it; it never sends.
    private func fillStarter(_ prompt: String) {
        guard !appState.commandCoordinator.run.isRunning, !appState.commandCoordinator.run.recovery.isPending else { return }
        conversation.draft = prompt
        composerFocusRequest &+= 1
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 5 ? "Up late" : hour < 12 ? "Good morning"
                 : hour < 18 ? "Good afternoon" : "Good evening"
        let name = Self.macFirstName
        return name.isEmpty ? "\(part)." : "\(part), \(name)."
    }

    /// The user's first name from their macOS account — full name's first word (e.g. "Jesai
    /// Tarun" → "Jesai"), falling back to the (capitalized) short login name, then to nothing
    /// (the greeting just drops the name). Resolved once per launch; no account, no network.
    static let macFirstName: String = {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = full.split(separator: " ").first, !first.isEmpty { return String(first) }
        let login = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? "" : login.capitalized
    }()

    /// Today's analysis status group: while the first analysis is not done, or one is running
    /// or needs attention.
    private var showsAnalysisBlock: Bool {
        !kbOnly && !needsPersonalSetup
            && (!appState.processing.initialComplete || appState.processing.isBusy || appState.processing.needsAttention)
    }

    private var analysisBlock: some View {
        HomeInsetGroup {
            VStack(alignment: .leading, spacing: Space.s) {
                Button { MainNavigation.shared.show(.analysis) } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    } label: {
                        Label(appState.processing.statusLine,
                              systemImage: appState.processing.needsAttention ? "exclamationmark.triangle.fill" : "waveform.path")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("analysis.home.status")
                .accessibilityHint("Opens Analysis")
                if !appState.processing.initialComplete && model.entries.isEmpty {
                    Text(personalContextStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HomeAnalysisSummary(thingsUnderstood: thingsUnderstood, sources: sources, lastRun: lastRunLabel,
                                    nextWakeAt: appState.scheduler.nextWakeAt,
                                    schedulerEnabled: appState.scheduler.isEnabled,
                                    schedulerNeedsSetup: appState.scheduler.needsSchedulerSetup,
                                    customRoots: customRoots)
                if !appState.processing.initialComplete {
                    Button("Check Analysis Status") { showAnalysis = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("analysis.home.checkStatus")
                        .accessibilityHint("Opens the Analysis popover")
                }
            }
            .padding(Space.l)
        }
    }

    private var personalContextStatus: String {
        if appState.processing.paused {
            return "Your personal setup is saved. Analysis is paused. Sidekick is ready; personal context and Double Tap follow your first analysis."
        }
        if appState.processing.needsAttention {
            return "Your personal setup is saved. Analysis needs attention. Sidekick is ready; check analysis to finish building your context."
        }
        return "Your personal setup is saved. Personal context and Double Tap will be ready after your first analysis."
    }

    // MARK: The knowledge-base-only preview (free/go plans)

    /// The free-plan Home: an honest note where the suggestions would be — the knowledge base is
    /// real and theirs; the LIVING Sentient needs Plus. Once the claim reads Plus, it becomes the
    /// reset-and-rebuild note. The gift row, when there is one, sits above it.
    private var kbOnlyBlock: some View {
        HomeInsetGroup(footer: planUpgraded ? nil
                       : "Upgraded? Reset rebuilds your knowledge with Gmail, Calendar, and the full engine.") {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(planUpgraded ? "You’re on Plus. Time to go live." : "This is a preview of Sentient.")
                    .font(.headline)
                Text(planUpgraded
                     ? "Reset Sentient and it rebuilds your knowledge with Gmail and Calendar, then keeps it alive: proactive mornings, Sidekick, learning night after night."
                     : appState.processing.initialComplete
                        ? "Your knowledge base is built, private, and yours to explore. The living Sentient uses your ChatGPT Plus."
                        : "Your first analysis will build your private knowledge base. The living Sentient uses your ChatGPT Plus.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !planUpgraded {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Label("Mornings where things worth doing arrive already done", systemImage: "sun.horizon")
                        Label("Sidekick anywhere: tap right \u{2318} and tell it what to do", systemImage: "command")
                        Label("A knowledge base that keeps learning, night after night", systemImage: "moon.stars")
                    }
                    .padding(.vertical, Space.xs)
                }
                HStack(spacing: Space.s) {
                    if planUpgraded {
                        Button("Reset & Rebuild…", action: openSystemPane)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Get ChatGPT Plus") { NSWorkspace.shared.open(CodexAuth.upgradeURL) }
                            .buttonStyle(.borderedProminent)
                        Button("Reset Sentient…", action: openSystemPane)
                            .buttonStyle(.bordered)
                    }
                    Spacer(minLength: Space.s)
                    if personalSetupPending {
                        Button("Finish Personal Setup", action: finishPersonalSetup)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("personalSetup.knowledgeOnly.finish")
                    } else if !appState.processing.initialComplete {
                        Button("Check Analysis Status") { showAnalysis = true }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("analysis.home.checkStatus")
                            .accessibilityHint("Opens the Analysis popover")
                    }
                }
                .padding(.top, Space.xs)
            }
            .padding(Space.l)
        }
    }

    private func openSystemPane() {
        HomeWindowOpening.open(.settings, settingsPane: .system)
    }

    // MARK: The conversation

    private var transcript: some View {
        SidekickTranscript(conversation: conversation, coordinator: appState.commandCoordinator,
                           presentation: presentation,
                           active: isPresented && presentation.windowActive && inConversation && selectedPersonalFeature == nil)
    }

    private func showConversation() {
        withAnimation(standardMotion) {
            selectedPersonalFeature = nil
            presentation.surface = .conversation
        }
    }

    /// The toolbar's Back "Today": ends an open search, then closes an example if one is open,
    /// else returns from the conversation to Today.
    private func goBack() {
        if presentation.searchShown { endSearch() }
        if selectedPersonalFeature != nil {
            closePersonalFeature()
        } else {
            withAnimation(standardMotion) { presentation.surface = .suggestions }
        }
    }

    /// More › Show Suggestions / Show Conversation.
    private func toggleSurface() {
        if inConversation { goBack() } else { showConversation() }
    }

    private func beginSearch() {
        withAnimation(standardMotion) {
            selectedPersonalFeature = nil
            presentation.surface = .conversation
            presentation.searchShown = true
        }
        searchFocus &+= 1
    }

    private func endSearch() {
        presentation.search = ""
        withAnimation(standardMotion) { presentation.searchShown = false }
    }

    private func updateConversationVisibility() {
        let visible = isPresented && presentation.windowActive && inConversation && selectedPersonalFeature == nil
        if conversation.isVisible != visible { conversation.isVisible = visible }
        if visible && appState.commandCoordinator.run.recovery.isVisible { appState.commandCoordinator.run.recovery.dismiss() }
    }

    // MARK: Finish Setting Up (inspector) and its examples (drill-in)

    private var inspectorBinding: Binding<Bool> {
        Binding(get: { isPresented && (needsPersonalSetup ? inspectorWanted : (inConversation && suggestionsWanted)) },
                set: { if needsPersonalSetup { inspectorWanted = $0 } else { suggestionsWanted = $0 } })
    }

    @ViewBuilder private var inspectorContent: some View {
        if needsPersonalSetup {
            HomePersonalSetupPanel(selectedFeature: selectedPersonalFeature,
                                   emphasizeSetup: appState.hasCompletedFirstSidekickTask && !inConversation
                                       && !appState.commandCoordinator.run.isRunning,
                                   active: isPresented && presentation.windowActive,
                                   previewEnabled: !appState.commandCoordinator.run.isRunning
                                       && !appState.commandCoordinator.run.recovery.isPending,
                                   onSelectFeature: selectPersonalFeature,
                                   onFinishSetup: finishPersonalSetup)
        } else {
            HomeSuggestionsInspector(entries: visibleEntries, row: { suggestionRow($0, inInspector: true) })
        }
    }

    private func featurePreview(_ feature: HomePersonalFeature) -> some View {
        HomePersonalFeaturePreview(feature: feature, onClose: closePersonalFeature,
                                   isActive: isPresented && presentation.windowActive,
                                   availableHeight: previewAreaHeight)
            .transition(pageSwap)          // also between two examples: one leaves, then the next appears
            .id(feature)                   // a different feature starts from its first page
    }

    private func selectPersonalFeature(_ feature: HomePersonalFeature) {
        guard !appState.commandCoordinator.run.isRunning, !appState.commandCoordinator.run.recovery.isPending else { return }
        withAnimation(standardMotion) {
            selectedPersonalFeature = selectedPersonalFeature == feature ? nil : feature
        }
    }

    private func closePersonalFeature() {
        withAnimation(Motion.gated(Motion.quick, reduceMotion: reducedMotion)) { selectedPersonalFeature = nil }
    }

    private func finishPersonalSetup() {
        selectedPersonalFeature = nil
        onFinishSetup()
    }

    // MARK: Ask bar

    private var askBar: some View {
        HomeAskBar(coordinator: appState.commandCoordinator, presentation: presentation,
                   isPresented: isPresented, kbOnly: kbOnly, inConversation: inConversation,
                   focusRequest: composerFocusRequest, onAccepted: showConversation)
    }

    // MARK: Toolbar

    private var discoveryActive: Bool {
        isPresented && presentation.windowActive && !letterShown && !showAnalysis
            && !showCodexSignIn && !showWhatsAppPicker && !showIMessagePicker
            && !showGmailConnect && !showCalendarConnect && !showAppleMailPicker
            && !presentation.clearChatConfirmationShown && !appState.commandCoordinator.run.recovery.isPending
    }

    /// Home's window-toolbar items. Empty while another page is showing: Home stays mounted
    /// behind the other pages, and its items must not leak into their toolbars.
    @ToolbarContentBuilder private var toolbarActions: some ToolbarContent {
        if isPresented && (inConversation || selectedPersonalFeature != nil) {
            ToolbarItem(placement: .navigation) {
                Button(action: goBack) { Label("Today", systemImage: "chevron.left") }
                    .help("Back to Today")
            }
        }
        if isPresented {
            ToolbarItemGroup(placement: .primaryAction) {
                analysisButton
                if !kbOnly {
                    HomeDoubleTapButton(active: discoveryActive, presented: $showDoubleTap,
                                        needsPersonalSetup: needsPersonalSetup,
                                        onFinishSetup: finishPersonalSetup) {
                        MainNavigation.shared.show(.analysis)
                    }
                    searchItem
                }
                if inConversation && !needsPersonalSetup {
                    Button { suggestionsWanted.toggle() } label: {
                        Label(model.entries.isEmpty ? "Suggestions" : "Suggestions \(model.entries.count)",
                              systemImage: "sparkles.rectangle.stack")
                    }
                    .help("Show or hide suggestions")
                    .accessibilityIdentifier("sidekick.proactive")
                }
                if needsPersonalSetup {
                    Button { inspectorWanted.toggle() } label: {
                        Label("Finish Setting Up", systemImage: "checklist")
                    }
                    .help("Show or hide Finish Setting Up")
                }
                if !kbOnly { moreMenu }
            }
        }
    }

    private var analysisButton: some View {
        Button { showAnalysis = true } label: {
            Label(appState.processing.isBusy ? "Analyzing" : "Analysis",
                  systemImage: appState.processing.needsAttention ? "exclamationmark.triangle" : "waveform.path")
        }
        .help("Analysis Status")
        .accessibilityIdentifier("analysis.toolbar")
        .popover(isPresented: $showAnalysis, arrowEdge: .bottom) { analysisPopover }
    }

    /// Search: a button that becomes the search field (Mail's toolbar search), on either surface.
    @ViewBuilder private var searchItem: some View {
        if presentation.searchShown {
            ToolbarSearchField(text: Bindable(presentation).search, prompt: "Search Conversation",
                               identifier: "sidekick.history.search", width: 200,
                               focusRequest: searchFocus, onCancel: endSearch)
        } else {
            Button(action: beginSearch) { Label("Search", systemImage: "magnifyingglass") }
                .help("Search Conversation")
                .accessibilityLabel("Search conversation")
                .accessibilityIdentifier("sidekick.search")
                .keyboardShortcut("f", modifiers: .command)
        }
    }

    private var moreMenu: some View {
        Menu {
            SidekickClearChatMenuItem(coordinator: appState.commandCoordinator, presentation: presentation)
            Divider()
            Button(inConversation ? "Show Suggestions" : "Show Conversation", action: toggleSurface)
            Button("Open Notch") { appState.commandCoordinator.openNotchFromHome() }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .help("More")
    }

    @ViewBuilder private var analysisPopover: some View {
        if personalSetupPending && deck == .real {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Your personal context starts here.")
                    .font(.headline)
                Text(kbOnly
                     ? "Connect three sources, then choose when Sentient builds your knowledge."
                     : "Connect three sources, then choose when Sentient builds your knowledge. Sidekick is ready to use now.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Finish Setup…") { showAnalysis = false; finishPersonalSetup() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("analysis.home.finishSetup")
                }
            }
            .padding(Space.l)
            .frame(width: PageMetrics.popover)
        } else {
            AnalysisPopover(thingsUnderstood: thingsUnderstood, sources: sources,
                            lastRun: lastRunLabel,
                            nextWakeAt: appState.scheduler.nextWakeAt,
                            schedulerEnabled: appState.scheduler.isEnabled,
                            schedulerNeedsSetup: appState.scheduler.needsSchedulerSetup,
                            onAnalyze: { showAnalysis = false; onAnalyze() },
                            onPickWhatsApp: { showAnalysis = false; showWhatsAppPicker = true },
                            onPickIMessage: { showAnalysis = false; showIMessagePicker = true },
                            onPickGmail: { showAnalysis = false; showGmailConnect = true },
                            onPickAppleMail: { showAnalysis = false; showAppleMailPicker = true },
                            onPickCalendar: { showAnalysis = false; showCalendarConnect = true },
                            customRoots: customRoots)
        }
    }

    /// The Analysis "Last run" value — the real last-cycle stamp (day spelled out once it's no
    /// longer today's); demo mode: the showcase string.
    private var lastRunLabel: String {
        guard deck == .real else { return Demo.lastRun }
        guard let d = UserDefaults.standard.object(forKey: ProactiveCycle.lastCycleKey) as? Date else {
            return "not yet"
        }
        return d.glanceStamp
    }

    // MARK: Notices (one slot, most severe first)
    //
    // A LIVE issue outranks history: HealthCaution's ladder (an essential permission off · codex
    // gone/signed out · computer use regressed) shows first, because the product is broken RIGHT
    // NOW; otherwise the morning-after caution (last night's UNATTENDED run hit a knowable snag —
    // OvernightCaution recorded it at ProactiveCycle's choke point; the next fully successful
    // cycle clears it on its own). Live issues re-probe on foreground and melt away when fixed;
    // ✕ mutes a live issue's kind for the session (a lower rung may then surface), while the
    // overnight ✕ clears the record. Below both: skipped-connector warnings from the last
    // completed KB pass, then the just-updated notice and the invite. Good news never outranks
    // something broken, and stays out of the conversation and the setup flow.

    private var hasCriticalCaution: Bool {
        (needsCodexSignIn && !dismissedCodexSignInReminder) || liveIssue != nil
            || computerSetup.updateNotice == .failed || caution != nil
            || !ConnectorCaution.items(from: connectorCautionData).isEmpty
    }

    private var notices: some View {
        HomeNotices(visible: (!inConversation && !needsPersonalSetup) || hasCriticalCaution,
                    signedOut: needsCodexSignIn && !dismissedCodexSignInReminder,
                    liveIssue: liveIssue,
                    caution: caution,
                    connector: ConnectorCaution.items(from: connectorCautionData).first,
                    computerNotice: computerSetup.updateNotice,
                    computerProgress: computerSetup.progress,
                    showsInvite: isPresented && deck == .real && !letterShown && !showAnalysis,
                    reduceMotion: reducedMotion,
                    actions: noticeActions)
    }

    private var noticeActions: HomeNoticeActions {
        HomeNoticeActions(
            signIn: presentCodexSignIn,
            dismissSignedOut: {
                dismissedCodexSignInReminder = true
                HealthCaution.dismiss(.codexSignedOut)
                if case .codexSignedOut? = liveIssue { liveIssue = nil }
            },
            openHealth: openHealthSettings,
            dismissIssue: { issue in
                HealthCaution.dismiss(issue)
                withAnimation(standardMotion) { liveIssue = nil }
                probeHealth()   // the muted kind may have been hiding a lower rung
            },
            retryComputerUse: {
                let setup = computerSetup
                Task { await setup.install(force: true) }
            },
            dismissComputerUse: computerSetup.dismissUpdateNotice,
            cautionAction: caution.flatMap { cautionAction($0.kind) },
            dismissCaution: {
                OvernightCaution.clear()
                withAnimation(standardMotion) { caution = nil }
            },
            openSources: openSourceSettings,
            dismissConnector: { slug in
                withAnimation(standardMotion) { ConnectorCaution.dismiss(slug) }
            })
    }

    /// The overnight caution's one-click fix, where there is one: a signed-out codex is fixed in
    /// Permissions & Health; a full disk in System Settings' Storage pane. Weather kinds (offline,
    /// usage limit) have nothing to click.
    private func cautionAction(_ kind: OvernightCaution.Kind) -> (title: String, run: () -> Void)? {
        switch kind {
        case .loggedOut: return ("Open Settings", openHealthSettings)
        case .diskFull:  return ("Manage Storage…", { DiskSpace.openStorageSettings() })
        case .connectorAuth:   // the fix lives on the engine's own connectors page
            return ("Sign In Again…", { NSWorkspace.shared.open(ConnectorCensus.directoryURL) })
        case .noInternet, .usageLimit, .inputTooLarge, .stalled: return nil
        }
    }

    /// Land directly on Permissions & Health — every notice's fix lives there; never strand the
    /// user on the default pane.
    private func openHealthSettings() {
        HomeWindowOpening.open(.settings, settingsPane: .health)
    }

    private func openSourceSettings() {
        HomeWindowOpening.open(.settings, settingsPane: .sources)
    }

    /// Run HealthCaution's ladder off the main thread of thought: cheap sync probes, plus a
    /// cached codex login check (forced fresh while a codex notice is up, so a fix clears on the
    /// very next foreground). Quiet on pitch decks (demo cards must never share the stage with a
    /// health notice) and on the free home (HealthCaution guards kbOnly too — defense in depth).
    /// The result also drives the sidebar's Permissions & Health badge.
    private func probeHealth(forceCodexRecheck: Bool = false) {
        guard deck == .real, !kbOnly, ProcessInfo.processInfo.environment["SENTIENT_SELFTEST"] == nil else { return }
        Task {
            let issue = await HealthCaution.probe(forceCodexRecheck: forceCodexRecheck || liveIssue?.kindKey == "codex")
            MainNavigation.shared.healthIssueCount = issue == nil ? 0 : 1
            withAnimation(standardMotion) { liveIssue = issue }
        }
    }

    // A private login starts unknown. Wait for Codex installation before checking it,
    // then offer sign-in once per app session; closing and reopening Home never re-prompts.
    private var canCheckCodexSignIn: Bool {
        appState.hasCompletedOnboarding && !appState.isUninstalling && isPresented && deck == .real
            && backendRaw == ModelBackend.chatgpt.rawValue
            && codex.installed && !codex.preparing && !codex.installing
            && ProcessInfo.processInfo.environment["SENTIENT_SELFTEST"] == nil
    }

    private var needsCodexSignIn: Bool {
        canCheckCodexSignIn && codex.loginStatusChecked && !codex.loggedIn
    }

    private var canOfferCodexSignIn: Bool {
        needsCodexSignIn && !appState.hasOfferedCodexSignIn
            && !letterShown && !showAnalysis
            && !showWhatsAppPicker && !showIMessagePicker && !showGmailConnect && !showCalendarConnect && !showAppleMailPicker
    }

    private func refreshCodexSignIn() async {
        guard canCheckCodexSignIn else { return }
        await codex.refreshLoginStatus()
        guard !Task.isCancelled, canCheckCodexSignIn else { return }
        offerCodexSignInIfNeeded()
    }

    private func offerCodexSignInIfNeeded() {
        guard canOfferCodexSignIn, NSApplication.shared.isActive else { return }
        presentCodexSignIn()
    }

    private func presentCodexSignIn() {
        guard needsCodexSignIn else { return }
        appState.hasOfferedCodexSignIn = true
        showCodexSignIn = true
    }

    // MARK: The letter sheet

    /// An opened suggestion, as a sheet over Home.
    @ViewBuilder private var letterSheet: some View {
        if let b = letter {
            HomeLetterSheet(briefing: b,
                            action: model.entry(b.id)?.action,
                            phase: model.entry(b.id)?.phase ?? .offer,
                            editable: model.entry(b.id)?.action != nil && b.draft != nil,   // real action card
                            // The LIVE content for THIS card (reflects any prior edit) — seeds the editor
                            // per briefing so a reused sheet never shows the previous card's draft.
                            liveDraft: model.entry(b.id)?.action?.preparedContent ?? b.draft ?? "",
                            liveRecipient: model.entry(b.id)?.action?.recipient ?? "",
                            fireDimmed: appState.commandCoordinator.run.isRunning
                                && model.entry(b.id)?.action.map { ProactiveExecutor.isFireable($0) } == true,
                            onCommitEdit: { model.applyEdit(b.id, content: $0, recipient: $1) },
                            onLiveEdit: { model.updateDraft(b.id, content: $0, recipient: $1) },
                            onOffer: {
                                closeLetter()
                                model.run(b.id)   // real card → fires for real; demo → theater
                            },
                            onClose: closeLetter)
        }
    }

    private func openLetter(_ b: Briefing) {
        letter = b
        letterShown = true
    }

    private func closeLetter() {
        letterShown = false
    }
}

// MARK: - The model (deal · run · dismiss)

@MainActor @Observable
final class ForYouModel {
    struct Entry: Identifiable {
        let b: Briefing
        var action: PreparedAction?   // real card → the action to fire (mutable: edits update it); demo → nil
        var phase: BriefingPhase
        var dealt = false
        var flight: CGSize?           // set = the card is flying off-screen
        var liveLines: [String] = []  // real card → codex's live play-by-play
        var id: String { b.id }
    }

    var entries: [Entry] = []
    /// The app-lifetime command coordinator (HomeView sets it on appear) — the notch and the
    /// app-wide one-task lock. Every executable card adopts the shared conversation run;
    /// its setup, progress, questions and result all belong to chat.
    weak var coordinator: CommandCoordinator?
    /// Bumped per appearance — in-flight Tasks from a previous visit check it and bail,
    /// so a re-deal can never be mutated by stale theater/dismiss timers.
    private var visit = 0
    private var loadedDeck: BriefingDeck?
    private var loadedBriefing: Date?
    func ensureVisit(deck: BriefingDeck) {
        let stamp = UserDefaults.standard.object(forKey: ProactiveCycle.lastCycleKey) as? Date
        if loadedDeck != deck || (stamp != loadedBriefing && draftPreviews.isEmpty && coordinator?.run.isRunning != true) {
            beginVisit(deck: deck)
        }
    }
    /// Editor values waiting for the existing autosave. Keep them separate from the saved
    /// action so reading Sidekick context cannot change the editor's identity or its fields.
    private var draftPreviews: [String: (content: String, recipient: String)] = [:]

    func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

    /// Exactly the visible, pending real cards. Never resurrect dismissed cards from the
    /// saved deck or turn a demo/gift into an executable suggestion. Preserve display order.
    var sidekickActions: [PreparedAction] {
        entries.compactMap { entry in
            guard entry.dealt, entry.flight == nil, entry.phase == .offer,
                  let action = entry.action else { return nil }
            guard let draft = draftPreviews[entry.id] else { return action }
            return Self.replacing(action, content: draft.content, recipient: draft.recipient)
        }
    }

    private func update(_ id: String, _ mutate: (inout Entry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[i])
    }

    /// A fresh visit. Real mode → the verified cards from the latest proactive run (empty → the orb's
    /// "I'm here to help."). Demo modes → the picked hard-coded deck (welcome re-sealed). Then the orb
    /// deals the cards with staggered springs from above the header.
    func beginVisit(deck: BriefingDeck) {
        loadedDeck = deck
        loadedBriefing = UserDefaults.standard.object(forKey: ProactiveCycle.lastCycleKey) as? Date
        visit += 1
        let v = visit
        draftPreviews.removeAll()
        switch deck {
        case .real:
            // Each card's accent is a shade from its method's color family, cycled by the card's
            // order among its method-mates — a deck of three computer-use cards gets three greens.
            var methodCounts: [PreparedAction.Method: Int] = [:]
            var built: [Entry] = (ProactiveResearch.latest()?.ready ?? []).map { action in
                let variant = methodCounts[action.method, default: 0]
                methodCounts[action.method] = variant + 1
                return Entry(b: Briefing(from: action, variant: variant), action: action, phase: .offer)
            }
            // The day-one welcome "gift" rides LAST as a sealed envelope (generated from the user's
            // own knowledge base by the proactive cycle; absent until that's run once) — last in
            // the deck = the bottom-right scatter slot, the envelope's fixed perch in every mode.
            if let gift = GiftLetter.latest() {
                built.append(Entry(b: Briefing(fromGiftMarkdown: gift), action: nil, phase: .sealed))
            }
            entries = built
        case .jesai, .launch:
            // Both demo decks keep their welcome card LAST for the same bottom-right perch.
            let cards = deck == .launch ? Briefing.launchDemo : Briefing.jesaiDemo
            entries = cards.map { Entry(b: $0, action: nil, phase: $0.kind == .welcome ? .sealed : .offer) }
        }
        for (i, e) in entries.enumerated() {
            if coordinator?.run.externalCardID == e.id { update(e.id) { $0.phase = .working(0) } }
            Task {
                try? await Task.sleep(for: .seconds(0.25 + Double(i) * 0.11))
                guard self.visit == v else { return }
                withAnimation(.spring(response: 0.62, dampingFraction: 0.74)) {
                    self.update(e.id) { $0.dealt = true }
                }
            }
        }
    }

    /// Uninstall's quiet home: invalidate theater timers and take every card off the table.
    func clear() {
        visit += 1
        entries.removeAll()
        draftPreviews.removeAll()
    }

    /// The welcome envelope opened: the card lives on un-sealed (the view opens the letter).
    func unsealWelcome() {
        guard let e = entries.first(where: { $0.b.kind == .welcome }) else { return }
        update(e.id) { $0.phase = .offer }
    }

    /// Fire the offer. A REAL card runs its action through the executor for real (live-streamed, with
    /// STOP); a demo card plays the briefing's hard-coded `workLog` theater for visual feedback.
    func run(_ id: String) {
        guard let e = entry(id), e.phase == .offer, e.b.offer != nil else { return }
        if let action = e.action {
            guard ProactiveExecutor.isFireable(action), coordinator?.run.isRunning != true else { return }
            // Include a live edit even if its debounced persistence has not fired yet.
            let reviewed = draftPreviews[id].map {
                Self.replacing(action, content: $0.content, recipient: $0.recipient)
            } ?? action
            runReal(id, reviewed)
            return
        }
        let v = visit

        Task {
            withAnimation(.easeInOut(duration: 0.3)) { update(id) { $0.phase = .working(0) } }
            for n in 1...e.b.workLog.count {
                try? await Task.sleep(for: .seconds(n == 1 ? 0.55 : Double.random(in: 0.7...1.15)))
                guard self.visit == v else { return }
                withAnimation(.easeOut(duration: 0.22)) { update(id) { $0.phase = .working(n) } }
            }
            try? await Task.sleep(for: .seconds(0.8))
            guard self.visit == v else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { update(id) { $0.phase = .done } }
            try? await Task.sleep(for: .seconds(3.0))
            guard self.visit == v else { return }
            dismiss(id, toward: CGSize(width: CGFloat.random(in: 250...520),
                                       height: -CGFloat.random(in: 350...560)))
        }
    }

    /// Persist the selected request and open chat before any setup or execution awaits.
    /// The app-owned run keeps the exact reviewed artifact and executor policy; the card
    /// is only a suggestion, never a second progress surface or owner of the running task.
    private func runReal(_ id: String, _ action: PreparedAction, retryContext: String = "") {
        let v = visit
        guard ProactiveExecutor.isFireable(action), let coordinator,
              coordinator.beginExternalRun(
                  caption: action.title,
                  request: SidekickCardContext.taskSnapshot(action),
                  retryContext: retryContext,
                  onRetry: { guidance in self.runReal(id, action, retryContext: retryContext + guidance) },
                  onStopRequest: { [weak self] in self?.stopRun(id) }) else { return }
        let adoptedRun = coordinator.run
        let generation = adoptedRun.runID
        let interaction = adoptedRun.interaction
        update(id) { $0.phase = .working(0); $0.liveLines = [] }
        adoptedRun.conversation.requestNavigation()
        InviteProgram.shared.record(.proactive)
        let task = Task {
            let progress: @Sendable (String) -> Void = { line in
                Task { @MainActor in adoptedRun.externalPush(line, runID: generation) }
            }
            let outcome: ProactiveExecutor.Outcome
            do {
                // Validate before setup, then let the executor recheck immediately before acting.
                if let issue = await ProactiveExecutor.mailEvidenceIssue(action) {
                    outcome = .notFireable(issue)
                } else {
                    try Task.checkCancellation()
                    try await ComputerUseGate.shared.waitUntilReady()
                    try Task.checkCancellation()
                    outcome = await SidekickInteraction.$current.withValue(interaction) {
                        await ProactiveExecutor.shared.fire(action, progress: progress)
                    }
                }
            } catch {
                guard adoptedRun.runID == generation else { return }
                let stopped = Task.isCancelled || error is CancellationError || error is ComputerUseGate.SetupCancelled
                let message = (error as? LocalizedError)?.errorDescription ?? "Sidekick couldn’t finish setup. Try again."
                if !stopped { Log("card setup failed — \(ErrorLabel(error))") }
                adoptedRun.completeExternal(stopped ? .stopped : .failed,
                    line: stopped ? "■ stopped" : "✗ \(message)", runID: generation)
                if self.visit == v { withAnimation { self.update(id) { $0.phase = .offer } } }
                return
            }
            guard adoptedRun.runID == generation else { return }
            guard !Task.isCancelled else {
                adoptedRun.completeExternal(.stopped, line: "■ stopped", runID: generation)
                if self.visit == v { withAnimation { self.update(id) { $0.phase = .offer } } }
                return
            }
            switch outcome {
            case .fired(let answer):
                self.removeFromLatest(id)
                adoptedRun.completeExternal(.success, line: "✓ done", finalText: answer, runID: generation)
                guard self.visit == v else { return }
                // The answer lives in chat. Retire the consumed suggestion without a second
                // completion presentation when the user reopens the proactive dock.
                self.entries.removeAll { $0.id == id }
                self.draftPreviews[id] = nil
            case .notFireable(let message), .failed(let message):
                adoptedRun.completeExternal(.failed, line: "✗ \(message)", runID: generation)
                if self.visit == v { withAnimation { self.update(id) { $0.phase = .offer } } }
            }
        }
        adoptedRun.ownExternalTask(task, cardID: id)
    }

    /// STOP a live real-card run: cancel the codex process (CodexCLI honors it) and return to offer.
    /// Reached from the card's STOP directly and, for an adopted run, from the notch/bar/hotkey via
    /// `onStopRequest` — the guard makes a second arrival a no-op (one cancel is enough; the
    /// adoption completes from the fire's unwind in runReal, never here).
    func stopRun(_ id: String) {
        if let run = coordinator?.run, run.isExternal, run.externalCardID == id {
            run.stop(); return
        }
    }

    /// Apply an edited draft + recipient to a card and persist them, so the fire sends exactly this
    /// content to exactly this "To:".
    func applyEdit(_ id: String, content: String, recipient: String) {
        update(id) {
            guard let old = $0.action else { return }
            $0.action = Self.replacing(old, content: content, recipient: recipient)
        }
        draftPreviews[id] = nil
        guard let result = ProactiveResearch.latest() else { return }
        ProactiveResearch.saveLatest(ReadyResult(
            ready: result.ready.map { $0.id == id ? Self.replacing($0, content: content, recipient: recipient) : $0 },
            dropped: result.dropped))
    }

    /// Keep the in-memory draft current on every edit; persistence remains debounced.
    /// A notch request during editing must see the same response and recipient as the user.
    func updateDraft(_ id: String, content: String, recipient: String) {
        guard entry(id)?.action != nil else { return }
        draftPreviews[id] = (content, recipient)
    }

    /// Drop a fired card from the persisted `latest` so a re-deal (next visit) won't show it again.
    private func removeFromLatest(_ id: String) {
        guard let result = ProactiveResearch.latest() else { return }
        ProactiveResearch.saveLatest(ReadyResult(ready: result.ready.filter { $0.id != id },
                                                 dropped: result.dropped))
    }

    /// A newly mounted Home observes the same app-owned task. Reconcile persisted results
    /// when it ends, even when its original view/model is no longer the visible one.
    func reconcileFinishedRuns() {
        guard let latest = ProactiveResearch.latest() else { return }
        let current = Set(latest.ready.map(\.id))
        entries.removeAll { $0.action != nil && !current.contains($0.id) }
        for entry in entries where entry.action != nil {
            if case .working = entry.phase { update(entry.id) { $0.phase = .offer } }
        }
    }

    /// A copy of a PreparedAction with new `preparedContent` + `recipient` (the rest unchanged).
    /// Copy the full value so content edits preserve routing, identity and operation metadata.
    private static func replacing(_ a: PreparedAction, content: String, recipient: String) -> PreparedAction {
        var copy = a
        copy.preparedContent = content
        copy.recipient = recipient
        return copy
    }

    /// Send a card flying along `v` (a flick's predicted translation), then reflow the scatter.
    func dismiss(_ id: String, toward v: CGSize) {
        guard entry(id) != nil else { return }
        let token = visit
        let mag = max(hypot(v.width, v.height), 1)
        let flight = CGSize(width: v.width / mag * 1200, height: v.height / mag * 1200)
        withAnimation(.easeIn(duration: 0.38)) { update(id) { $0.flight = flight } }
        Task {
            try? await Task.sleep(for: .seconds(0.42))
            guard self.visit == token else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                entries.removeAll { $0.id == id }
                draftPreviews[id] = nil
            }
        }
    }
}

// MARK: - Demo data (the home's own showcase strings — cards live in Briefing.jesaiDemo/.launchDemo)

private enum Demo {
    static let lastRun = "3:41 AM"
}

#Preview("Home — the suggestions") {
    HomeView(thingsUnderstood: 3339,
             sources: .init(files: true, whatsapp: true, imessage: true, notes: true))
        .frame(width: 1180, height: 820)
}

#Preview("Home — launch demo deck") {
    HomeView(thingsUnderstood: 3339,
             sources: .init(files: true, whatsapp: true, imessage: true, notes: true),
             deck: .launch)
        .frame(width: 1180, height: 820)
}

#Preview("Home — knowledge-base-only (free plan)") {
    HomeView(thingsUnderstood: 1704,
             sources: .init(files: true),
             deck: .real,
             previewKBOnly: true,
             previewUpgraded: false)
        .frame(width: 1180, height: 820)
}

#Preview("Home — kb-only, upgrade detected") {
    HomeView(thingsUnderstood: 1704,
             sources: .init(files: true),
             deck: .real,
             previewKBOnly: true,
             previewUpgraded: true)
        .frame(width: 1180, height: 820)
}
