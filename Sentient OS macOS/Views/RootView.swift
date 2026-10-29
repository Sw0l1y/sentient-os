// Main window navigation: onboarding becomes a sidebar window once the frontier model is
// connected. Home and Knowledge stay mounted while hidden; the other pages are built on demand.
// The root sets the window title and subtitle once (pages publish subtitles with .pageSubtitle);
// background progress lives in the sidebar footer (AppSidebar). No window background is drawn.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI
import Combine

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var navigation = MainNavigation.shared
    @State private var attemptedWritingStyleSelection: WritingStyle.Selection?
    @State private var writingStyleSelection = WritingStyle.selectionIdentity
    @State private var onboardingScale = OnboardingWindowLayout.scale(
        visibleSize: NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900))
    // Persistent custom folder roots (CustomRoots store) — added in Settings or Dev Tools,
    // watched here so Analyze Now and the Analysis popover react to edits from any window.
    @AppStorage(CustomRoots.key) private var customRootsRaw = ""
    private var customRoots: [URL] { CustomRoots.decode(customRootsRaw) }
    // The 3-way card mode (Dev Tools → Proactive Cards…). DEFAULT: real cards + full-cycle
    // Analyze Now; .jesai/.launch swap in a hard-coded demo deck (pitch / launch-video mode).
    @AppStorage(BriefingDeck.key) private var deckRaw = BriefingDeck.defaultRaw
    private var deck: BriefingDeck { BriefingDeck(rawValue: deckRaw) ?? .real }
    /// Observe the engine choice as well as its installer, including changes in another window.
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    private var computerSetup: ComputerUseSetup {
        .instance(for: .selected(for: ModelBackend(rawValue: backendRaw) ?? .chatgpt))
    }

    /// Observed for onboarding's top-left model-download whisper (after onboarding, the sidebar
    /// footer shows it).
    @State private var download = ModelDownload.shared

    /// Which sources Home shows as selected. SourceSelection.current() checks each folder's and
    /// database's readability (privacy round-trips), so it runs when its inputs change — appear,
    /// app activation, returning Home, a source-selection or custom-folder change — not on every
    /// body pass (sampled blocking the main thread on each Knowledge / Settings switch).
    @State private var homeSources = HomeSources()
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    private func refreshHomeSources() {
        let sources = SourceSelection.current()
        let next = HomeSources(
            files: sources.contains { if case .files = $0 { return true } else { return false } },
            whatsapp: sources.contains { if case .whatsapp = $0 { return true } else { return false } },
            imessage: sources.contains { if case .imessage = $0 { return true } else { return false } },
            notes: sources.contains(.notes),
            whatsappAvailable: WhatsAppSource.isInstalled)
        if next != homeSources { homeSources = next }
    }

    var body: some View {
        ZStack {
            if !appState.hasCompletedOnboarding {
                OnboardingCanvas(scale: onboardingScale) {
                    OnboardingView {
                        withAnimation(standardAnimation) { appState.hasCompletedOnboarding = true }
                    }
                }
                .transition(.opacity)
                // The just-updated notice, overlaid on ONBOARDING only (the home renders it in
                // its own banner slot): a mid-onboarding user may have closed a broken window,
                // and the post-update relaunch that brings it back should say why it's back.
                .overlay(alignment: .topTrailing) {
                    UpdateNoticeCapsule()
                        .padding(.trailing, 24).padding(.top, 24)
                }
            } else {
                NavigationSplitView {
                    AppSidebar()
                } detail: {
                    detail
                }
                .frame(minWidth: 900, minHeight: 600)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: appState.hasCompletedOnboarding ? nil : OnboardingWindowLayout.minimum.width * onboardingScale,
               minHeight: appState.hasCompletedOnboarding ? nil : OnboardingWindowLayout.minimum.height * onboardingScale)
        .background(OnboardingWindowFit(active: !appState.hasCompletedOnboarding) { onboardingScale = $0 })
        // Core tier: the home window came up (fires once per window instantiation — launch opens it
        // automatically; anything later is a deliberate menu-bar/Dock reopen, hence the trigger
        // param). Sidekick-only users who never look at home are exactly who this measures.
        // Onboarding appearances don't count; the SDK's session signals cover day one.
        .onAppear {
            guard appState.hasCompletedOnboarding else { return }
            let sinceBoot = Date().timeIntervalSince(Analytics.bootTime)
            Analytics.signal("Home.opened",
                             parameters: ["trigger": sinceBoot < 5 ? "launch" : "reopen"], tier: .core)
        }
        // Onboarding's slot for the background download whispers: top-left, just under the
        // titlebar, because every onboarding page keeps its footer (Back, the footnote, the info
        // button, the GitHub mark) in the bottom-left corner (SPEC-D6 1.4 / open issue 11). After
        // onboarding the sidebar footer carries the same pair.
        .overlay(alignment: .topLeading) {
            if !appState.hasCompletedOnboarding { whispers }
        }
        // The mandatory update gate floats above everything (home, processing, dev sheet) — when a
        // required update is found it takes over; otherwise it draws nothing. (Updates/)
        .modifier(LifetimeUpgradePresentation())
        .overlay { UpdateGateView() }
        .background(MainWindowCloseGuard())
        .onChange(of: navigation.page) { _, page in
            if page == .home { refreshHomeSources() }
        }
        .onAppear { refreshHomeSources() }
        .onChange(of: writingStyleSelection) { _, _ in refreshHomeSources() }
        .onChange(of: customRootsRaw) { _, _ in refreshHomeSources() }
        .onChange(of: appState.hasCompletedOnboarding) { _, completed in
            if !completed {
                navigation.showDevTools = false
                attemptedWritingStyleSelection = nil
            }
        }
        .sheet(isPresented: $navigation.showDevTools) {
            DevToolsView()
        }
        // Source opt-ins and account generations may change in another window. Compare the
        // complete consent identity before retrying; unrelated defaults changes do no work.
        // Debounced: any defaults write posts this, and the identity probes database readability.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)) { _ in
                let next = WritingStyle.selectionIdentity
                if next != writingStyleSelection { writingStyleSelection = next }
                // Folder and Notes opt-ins are not part of that identity.
                refreshHomeSources()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            writingStyleSelection = WritingStyle.selectionIdentity
            refreshHomeSources()
        }
        .onReceive(NotificationCenter.default.publisher(for: DirectMCPStore.changed).receive(on: RunLoop.main)) { _ in
            writingStyleSelection = WritingStyle.selectionIdentity
        }
        // Optional samples retry once per distinct source selection while Home is idle. Keep
        // the work independent: collect marks the pipeline busy, which changes this task's id.
        .task(id: eligibleWritingStyleSelection) {
            guard let selection = eligibleWritingStyleSelection,
                  attemptedWritingStyleSelection != selection else { return }
            attemptedWritingStyleSelection = selection
            Task { @MainActor in
                Log("WritingStyle: silent setup started for an existing knowledge base")
                do { try await WritingStyle.generateIfNeeded() }
                catch { Log("WritingStyle: silent setup failed (\(ErrorLabel(error)))") }
            }
        }
    }

    private var eligibleWritingStyleSelection: WritingStyle.Selection? {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["SENTIENT_SELFTEST"] == nil else { return nil }
        #endif
        guard appState.hasCompletedOnboarding && appState.processing.initialComplete && !appState.processing.isBusy
            && !appState.processing.isSuspended
            && !PipelineActivity.shared.isRunning && !appState.commandCoordinator.run.isRunning
            && writingStyleSelection.hasSources
            && !WritingStyle.exists()
            && FileManager.default.fileExists(atPath: VaultGenerator.vaultRoot.appendingPathComponent("README.md").path)
        else { return nil }
        return writingStyleSelection
    }

    /// The detail column. Home and Knowledge are retained while hidden so a draft, scroll
    /// position or open note survives a trip to another page; the rest are built on demand.
    private var detail: some View {
        ZStack {
            home.retained(visible: navigation.page == .home)
            if navigation.hasOpenedKnowledge {
                KnowledgeView(isPresented: navigation.page == .knowledge)
                    .retained(visible: navigation.page == .knowledge)
            }
            switch navigation.page {
            case .settings: SettingsView()
            case .analysis: ProcessingWindowView()
            case .setup: PersonalSetupView()
            case .home, .knowledge: EmptyView()
            }
        }
        // Set once, here. No page sets .navigationTitle or .navigationSubtitle itself.
        .navigationTitle(navigation.title)
        .navigationSubtitle(navigation.subtitle)
    }

    /// Onboarding only: the model-download card and the computer-use setup line (the driver
    /// download is an unstructured background task that can outlive onboarding).
    private var whispers: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModelDownloadWhisper(download: download)
            if computerSetup.isInstalling {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Setting up computer use in the background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding(.leading, 22).padding(.top, 12)
        .animation(standardAnimation, value: computerSetup.isInstalling)
        .animation(standardAnimation, value: download.phase)
        .animation(standardAnimation, value: download.fullScreenVisible)
    }

    private var standardAnimation: Animation? {
        Motion.gated(Motion.standard, reduceMotion: motionOverride ?? systemReduced)
    }

    private var home: some View {
        HomeView(
            isPresented: navigation.page == .home,
            thingsUnderstood: LifetimeStats.analyzed,
            sources: homeSources,
            customRoots: customRoots,
            deck: deck,
            onAnalyze: {
                guard appState.hasCompletedPersonalSetup || appState.processing.initialComplete else {
                    navigation.show(.setup)
                    return
                }
                if !appState.processing.isBusy && appState.processing.record.status != .requested {
                    appState.processing.requestNow()
                }
                navigation.show(.analysis)
            },
            onShowDevTools: { navigation.showDevTools = true },
            onFinishSetup: { navigation.show(.setup) })
    }
}

private extension View {
    /// Keeps a page mounted but inert and invisible while another page is showing.
    func retained(visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .disabled(!visible)
            .accessibilityHidden(!visible)
    }
}
