//
//  OnboardingFrontierModelView.swift
//  Sentient OS macOS
//
//  Onboarding's "Choose Your AI" step, a Setup Assistant page (SPEC-D6 S8): the five engine
//  choices in one row over the SAME per-engine panels Settings renders (FrontierEnginePicker),
//  with the live codex login embedded as the ChatGPT panel (OnboardingCodexLoginPanel). The
//  footer holds Back, the telemetry footnote, the gift link, the GitHub mark and Continue. Continue prepares and commits a signed-in Claude choice;
//  other choices must already be the active, healthy engine, including the selected custom
//  preset. Every choice prepares its CLI, so an existing login cannot bypass its update check.
//  Joins shared Codex preparation at launch; browsing tabs never changes the saved engine.
//  Doc: Views/Onboarding/Documentation - Onboarding.md
//

import SwiftUI
import AppKit

struct OnboardingFrontierModelView: View {
    let onBack: (() -> Void)?
    let onContinue: () -> Void
    /// The gift celebration hides and disables the rest of onboarding (OnboardingView owns it).
    @Binding private var isPresentingGift: Bool

    init(onBack: (() -> Void)? = nil,
         isPresentingGift: Binding<Bool> = .constant(false),
         onContinue: @escaping () -> Void) {
        self.onBack = onBack
        self._isPresentingGift = isPresentingGift
        self.onContinue = onContinue
    }

    @State private var codex = CodexSetup.shared
    @State private var claude = ClaudeSetup.shared
    @State private var tab: FrontierEngineTab = .chatgpt
    @State private var continueAttempt: UUID?
    @State private var continueTask: Task<Void, Never>?
    @State private var continueStatus: String?
    @State private var limitedPlan = false
    private var limitedChatGPT: Bool { tab == .chatgpt && codex.loggedIn && limitedPlan }
    private var continuing: Bool { continueAttempt != nil }
    private var enginePreparing: Bool {
        tab == .claude
            ? claude.preparing || claude.installing
            : codex.preparing || codex.installing
    }

    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    @AppStorage(CustomProvider.presetKey) private var presetRaw = CustomProvider.Preset.openRouter.rawValue
    /// Observed so a passing Test & Select re-evaluates `engineReady` in place.
    @AppStorage(CustomProvider.visionVerifiedKey) private var visionVerified = false

    private var activeTab: FrontierEngineTab {
        FrontierEngineTab(backend: ModelBackend(rawValue: backendRaw) ?? .chatgpt,
                          preset: CustomProvider.Preset(rawValue: presetRaw) ?? .openRouter)
    }

    /// Claude needs a login; Continue prepares and commits it. Other displayed engines must
    /// already be committed and healthy, including a passing Test & Select for custom endpoints.
    private var engineReady: Bool {
        _ = visionVerified
        if tab == .claude { return claude.loggedIn }
        guard tab == activeTab else { return false }
        switch ModelBackend(rawValue: backendRaw) ?? .chatgpt {
        case .custom:  return CustomProvider.current.isUsable
        case .claude:  return claude.loggedIn
        case .chatgpt: return codex.loggedIn
        }
    }

    var body: some View {
        // A Setup Assistant page: tile, title and message, the engine picker, then a status
        // line reserved so Continue never moves. The footer carries Back, the privacy small
        // print, the gift link and the GitHub mark, with Continue on the right.
        SetupAssistantPage(tile: .setupChooseAI, title: "Choose Your AI",
                           message: PrivacyCopy.frontierSummary, width: 640) {
            VStack(alignment: .leading, spacing: Space.xl) {
                FrontierEnginePicker(tab: $tab, layout: .singleRow,
                                     chatgptHealthy: codex.loggedIn) {
                    OnboardingCodexLoginPanel()
                }
                statusStack
                    .frame(minHeight: 22, alignment: .top)
            }
        } footer: {
            SetupAssistantFooter(primaryTitle: "Continue",
                                 primaryEnabled: engineReady && !continuing && !enginePreparing,
                                 back: onBack) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    OnboardingTelemetryConsent()
                    HStack(spacing: Space.m) {
                        OnboardingInviteView(isPresentingGift: $isPresentingGift)
                        OnboardingGitHubButton()
                    }
                }
            } primary: {
                continueWithEngine()
            }
        }
        .onAppear {
            tab = activeTab
            // Join launch preparation, including adoption of a portable existing login into
            // the private runtime. A legacy CLI's login alone cannot make this screen ready.
            Task {
                _ = await codex.ensureCurrent()
                await codex.refreshLoginStatus()
                limitedPlan = CodexAuth.isLimited()
            }
            Task {
                await claude.refreshInstalled()
                await claude.refreshLoginStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from the browser — often already signed in. Step-level on purpose: the
            // ChatGPT panel (and its own watcher) may not exist while another tab is showing.
            Task {
                await codex.refreshInstalled()
                await codex.refreshLoginStatus()
                limitedPlan = CodexAuth.isLimited()
            }
            Task {
                await claude.refreshInstalled()
                await claude.refreshLoginStatus()
            }
        }
        .onChange(of: backendRaw) { cancelContinue() }
        .onChange(of: presetRaw) { cancelContinue() }
        .onChange(of: tab) { cancelContinue() }
        .onDisappear { cancelContinue() }
    }

    /// Preparation, install and Continue status, plus the limited-plan note.
    @ViewBuilder private var statusStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            if tab != .claude {
                if codex.preparing || codex.installing { MonoWaitLine("Preparing Codex…") }
                OnboardingStatusText(codex.installStatus)
            }
            OnboardingStatusText(continueStatus)
            if limitedChatGPT {
                StatusLabel("Your ChatGPT plan has limited usage. Try Sidekick now; Sentient will offer an upgrade if your provider reaches a limit.",
                            tone: .info)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.limitedPlan")
            }
        }
    }

    private func continueWithEngine() {
        guard engineReady, !continuing else { return }
        let initialBackend = backendRaw
        let selectedTab = tab
        let attempt = UUID()
        continueStatus = nil
        continueAttempt = attempt
        continueTask = Task {
            defer {
                if continueAttempt == attempt { continueAttempt = nil; continueTask = nil }
            }
            let prepared: Bool
            if selectedTab == .claude {
                prepared = await claude.ensureCurrent()
            } else {
                prepared = await codex.ensureCurrent()
            }
            guard !Task.isCancelled, continueAttempt == attempt,
                  backendRaw == initialBackend, tab == selectedTab else { return }
            guard prepared else {
                continueStatus = selectedTab == .claude
                    ? claude.installStatus ?? "✗ Claude Code couldn't be prepared. Try again."
                    : codex.installStatus ?? "✗ Codex couldn't be prepared. Try again."
                return
            }
            if selectedTab == .claude {
                await claude.refreshLoginStatus()
            } else if selectedTab == .chatgpt {
                await codex.refreshLoginStatus()
            }
            // The user can browse or select another engine while preparation is in flight.
            guard !Task.isCancelled, continueAttempt == attempt,
                  backendRaw == initialBackend, tab == selectedTab else { return }
            guard engineReady else {
                continueStatus = "✗ Sign in to your selected provider, then try Continue again."
                return
            }
            // Commit only after preparation and a fresh login check succeed, immediately
            // before navigation so the next step sees the selected provider.
            if selectedTab == .claude { backendRaw = ModelBackend.claude.rawValue }
            // Let the provider enforce access and usage. A Free/Go account may try Sidekick;
            // only a real provider limit should offer an upgrade, never this local plan label.
            CodexAuth.knowledgeBaseOnly = false
            onContinue()
        }
    }

    private func cancelContinue() {
        continueTask?.cancel()
        continueTask = nil
        continueAttempt = nil
        continueStatus = nil
    }
}

#Preview("Onboarding — Choose Your AI") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingFrontierModelView(onBack: {}, onContinue: {})
                .frame(width: 1100, height: 820)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
