//
//  FrontierEnginePicker.swift
//  Sentient OS macOS
//
//  The shared frontier-engine chooser, laid out like System Settings › Apple Intelligence & Siri:
//  a radio list of the five engines (each with its tile, its state and an "In Use" mark on the
//  engine that runs Sentient), then a detail group for the engine being browsed. Rendered by
//  Settings › AI Model (`.settingsGrid`: the pane's grouped Form) and by onboarding's Choose Your
//  AI page (`.singleRow`: GroupBoxes inside a Setup Assistant page). Choosing a row only browses;
//  an engine becomes the one in use only through Test & Select, Use Claude, Use ChatGPT or
//  onboarding's Continue. Owns the endpoint fields (ModelBackend/CustomProvider — the one source
//  of truth), Test & Select (vision-gated activation: an unproven model can never become the
//  engine), and the honest local-models warning. The ChatGPT detail is the host's slot.
//  Deep doc: Cloud/Documentation - Cloud - Frontier Model Choice (BYOM).md.
//

import SwiftUI
import AppKit

struct FrontierEnginePicker<ChatGPTPanel: View>: View {
    /// `.settingsGrid`: the Settings pane's grouped Form. `.singleRow`: a plain stack of GroupBoxes
    /// for a Setup Assistant page (the engines are a vertical radio list in both).
    enum Layout { case settingsGrid, singleRow }

    typealias Tab = FrontierEngineTab

    /// The one model that cleared the computer-use bar in the 2026-07-24 survey (~10 models,
    /// real tasks). Prefilled on the OpenRouter tab and named in its note.
    private static var kimiSlug: String { "moonshotai/kimi-k3" }

    let layout: Layout
    /// Whether the ChatGPT engine counts as healthy (wears "In Use"). Settings passes true —
    /// login honesty lives in Permissions & Health there; onboarding passes the live codex login.
    let chatgptHealthy: Bool
    private let chatgptPanel: () -> ChatGPTPanel
    /// Shows the "How Your Models Work Together" Section (Settings only; set by `explainer()`).
    private var showsExplainer = false

    init(tab: Binding<Tab>,
         layout: Layout = .settingsGrid,
         chatgptHealthy: Bool = true,
         @ViewBuilder chatgptPanel: @escaping () -> ChatGPTPanel) {
        self._tab = tab
        self.layout = layout
        self.chatgptHealthy = chatgptHealthy
        self.chatgptPanel = chatgptPanel
    }

    /// Adds the "How Your Models Work Together" disclosure as the Form's last Section.
    func explainer() -> FrontierEnginePicker {
        var copy = self
        copy.showsExplainer = true
        return copy
    }

    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    @AppStorage(CustomProvider.presetKey) private var presetRaw = CustomProvider.Preset.openRouter.rawValue
    @AppStorage(CustomProvider.baseURLKey) private var baseURL = ""
    @AppStorage(CustomProvider.modelNameKey) private var modelName = ""
    @AppStorage(CustomProvider.reasoningKey) private var reasoningRaw = "low"
    /// Set only by a passing Test Model run; any edit below clears it.
    @AppStorage(CustomProvider.visionVerifiedKey) private var verified = false

    @Binding private var tab: Tab
    @State private var claude = ClaudeSetup.shared
    @State private var claudePreparationTask: Task<Void, Never>?
    @State private var apiKey = ""
    @State private var showLocalWarning = false
    /// The local-reality popup fires once per picker visit, on the LM Studio tab.
    @State private var localWarningShown = false

    /// The Test Model probe, narrated: nil = untested, "…" = running, ✓/✗ lines otherwise.
    @State private var testing = false
    @State private var testVerdict: String?

    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduceMotion: Bool { motionOverride ?? systemReduced }

    private var backend: ModelBackend { ModelBackend(rawValue: backendRaw) ?? .chatgpt }
    private var savedPreset: CustomProvider.Preset { CustomProvider.Preset(rawValue: presetRaw) ?? .openRouter }
    private var settings: Bool { layout == .settingsGrid }

    /// The engine that runs Sentient (it wears "In Use" while healthy).
    private var activeTab: Tab {
        Tab(backend: backend, preset: savedPreset)
    }

    var body: some View {
        Group {
            switch layout {
            case .settingsGrid:
                PaneForm {
                    Section {
                        engineRows
                    } header: {
                        Text("Engine")
                    } footer: {
                        Text("Choose the AI behind your knowledge, suggestions, and Sidekick.")
                    }
                    Section {
                        detail
                    } header: {
                        Text(detailTitle)
                    } footer: {
                        detailFooter
                    }
                    if showsExplainer {
                        Section {
                            DisclosureGroup("How Your Models Work Together") {
                                VStack(alignment: .leading, spacing: Space.s) {
                                    Text(PrivacyCopy.frontierDetail)
                                    Text(PrivacyCopy.customProvider)
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            case .singleRow:
                VStack(alignment: .leading, spacing: Space.l) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: Space.s) {
                            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { index, engine in
                                if index > 0 { Divider() }
                                engineRow(engine)
                            }
                        }
                        .padding(.vertical, Space.xs)
                    }
                    if tab == .chatgpt {
                        chatgptPanel()
                    } else {
                        GroupBox(detailTitle) {
                            VStack(alignment: .leading, spacing: Space.m) {
                                detail
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.xs)
                        }
                    }
                }
            }
        }
        // A quiet crossfade — no lateral slide: the detail groups differ in height.
        .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: tab)
        .onAppear {
            tab = activeTab
            apiKey = CustomProvider.apiKey ?? ""
        }
        // The host's ChatGPT panel flipping the backend home (Use ChatGPT) retires any verdict.
        .onChange(of: backendRaw) {
            if backend == .chatgpt { testVerdict = nil }
        }
        .alert("A Note on Local Frontier Models", isPresented: $showLocalWarning) {
            Button("Understood") {}
        } message: {
            Text("Computer use needs a model that understands screenshots and uses tools reliably. Larger local models may need more memory. Choose the model and provider that fit your Mac and preferences. Cloud providers process your context under their own policies and your account settings.")
        }
        // Claude's install and login probe, whenever its detail is browsed.
        .task(id: tab) {
            guard tab == .claude else { return }
            await claude.refreshInstalled()
            await claude.refreshLoginStatus()
        }
        .task(id: claude.loggingIn) {
            // The sign-in watcher: while the browser flow is out, quietly re-check every 2s —
            // the detail flips to the signed-in state by itself the moment the login lands.
            guard claude.loggingIn else { return }
            while !Task.isCancelled, claude.loggingIn, !claude.loggedIn {
                try? await Task.sleep(for: .seconds(2))
                await claude.refreshLoginStatus()
            }
        }
        .onChange(of: tab) { old, new in
            if old == .claude, new != .claude { claudePreparationTask?.cancel() }
        }
        .onDisappear { claudePreparationTask?.cancel() }
    }

    // MARK: - The engine radio list

    @ViewBuilder private var engineRows: some View {
        ForEach(Tab.allCases) { engineRow($0) }
    }

    /// One engine: a radio mark, its tile, name and badge, and "In Use" on the live engine.
    /// Choosing it only browses its detail.
    private func engineRow(_ engine: Tab) -> some View {
        let browsed = tab == engine
        return Button {
            selectTab(engine)
        } label: {
            LabeledContent {
                if activeTab == engine && isActiveEngineHealthy(engine) {
                    Label("In Use", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: browsed ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(browsed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                    TileLabel(displayLabel(engine), subtitle: subtitle(engine)) {
                        IconTile(engineTile(engine))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(browsed ? .isSelected : [])
    }

    private func engineTile(_ engine: Tab) -> TileSpec {
        switch engine {
        case .chatgpt:    return .engineChatGPT
        case .claude:     return .engineClaude
        case .openRouter: return .engineOpenRouter
        case .lmStudio:   return .engineLMStudio
        case .custom:     return .engineCustom
        }
    }

    /// Settings drops " Subscription" ("ChatGPT", "Claude"); onboarding keeps the full label.
    private func displayLabel(_ engine: Tab) -> String {
        settings ? engine.label.replacingOccurrences(of: " Subscription", with: "") : engine.label
    }

    private func subtitle(_ engine: Tab) -> String? {
        if engine == .custom { return "Your endpoint" }
        switch engine.badge {
        case "recommended": return "Recommended"
        case "beta":        return "Beta"
        case "local":       return "Local"
        default:            return nil
        }
    }

    /// "In Use" stays honest: a custom engine only wears it once it's proven usable, Claude's is
    /// its live login, and ChatGPT's honesty is the host's call (Settings: always; onboarding:
    /// logged in).
    private func isActiveEngineHealthy(_ t: Tab) -> Bool {
        switch t {
        case .chatgpt: return chatgptHealthy
        case .claude:  return claude.loggedIn
        default:       return CustomProvider.current.isUsable
        }
    }

    /// Browsing tabs never disturbs a live engine: fields are only prefilled while nothing
    /// custom is active (Test Model and Use-this-model pin the right values when the user
    /// actually acts). The LM Studio tab raises the local-reality popup once per visit.
    private func selectTab(_ t: Tab) {
        tab = t
        testVerdict = nil
        // NO install kicks here (field-found 2026-08-22: a browsing tab click silently
        // downloaded codex on a Claude-backend Mac). Lazy install fires only on COMMITMENT
        // actions: the sign-in buttons, Use ChatGPT, and Test & Select — never on browsing.
        if t == .lmStudio, !localWarningShown {
            localWarningShown = true
            showLocalWarning = true
        }
        guard backend != .custom else { return }
        switch t {
        case .openRouter:
            if modelName.isEmpty { modelName = Self.kimiSlug }   // Kimi K3 forward
            baseURL = CustomProvider.Preset.openRouter.defaultBaseURL
        case .lmStudio:
            if baseURL.isEmpty || baseURL == CustomProvider.Preset.openRouter.defaultBaseURL {
                baseURL = CustomProvider.Preset.lmStudio.defaultBaseURL
            }
        default:
            break
        }
    }

    // MARK: - The browsed engine's detail

    private var detailTitle: String {
        switch tab {
        case .chatgpt:    return "ChatGPT"
        case .claude:     return settings ? "Claude" : "Your Claude"
        case .openRouter: return "Your OpenRouter"
        case .lmStudio:   return "Your LM Studio"
        case .custom:     return "Your Endpoint"
        }
    }

    @ViewBuilder private var detail: some View {
        switch tab {
        case .chatgpt:    chatgptPanel()
        case .claude:     claudeRows
        case .openRouter: endpointRows(for: .openRouter)
        case .lmStudio:   endpointRows(for: .lmStudio)
        case .custom:     endpointRows(for: .custom)
        }
    }

    @ViewBuilder private var detailFooter: some View {
        switch tab {
        case .openRouter, .lmStudio, .custom:
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Applies wherever this model runs.")
                Text("Stored in your Mac’s Keychain.")
                Text("Test the model’s image support before using it.")
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Claude (the claude -p engine)

    @ViewBuilder private var claudeRows: some View {
        Text(settings
             ? "Use your Claude Pro, Max, or Team subscription for knowledge, morning suggestions, and Sidekick."
             : "Claude Code runs on your own Claude subscription (Pro, Max, or Team), so a plan you already pay for powers everything: knowledge base, morning cards, Sidekick, computer use.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        claudeStates

        if claude.preparing || claude.installing { MonoWaitLine("Preparing Claude Code…") }
        OnboardingStatusText(claude.installStatus)

        if settings {
            DisclosureGroup("Using Gmail and Google Calendar") {
                Text("Connect them in Claude’s Settings → Connectors to use them in Sentient.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Gmail and Calendar can ride your claude.ai connectors: connect them once at claude.ai, under Settings, then Connectors, and Sentient's reads use them here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The Claude state machine: signed in (Use Claude in Settings; onboarding uses Continue) →
    /// browser out → install failed → the sign-in button (which lazily installs the CLI first).
    @ViewBuilder private var claudeStates: some View {
        let busy = claude.preparing || claude.installing
        if claude.loggedIn {
            StatusRow("Claude Account",
                      detail: claude.plan.map { "Signed in to Claude Code · \($0) plan" } ?? "Signed in to Claude Code",
                      tone: .ok)
            if backend == .claude {
                StatusLabel("Sentient is running on your Claude.", tone: .ok)
            } else if settings {
                HStack {
                    Spacer()
                    Button("Use Claude") { prepareClaude(signIn: false) }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                }
            }
        } else if claude.loggingIn {
            LoginLinkButton(url: claude.loginURL)
            StatusLabel("Finish signing in in your browser.", tone: .working)
            MonoWaitLine("Waiting for the browser sign-in…")
        } else if claude.installGaveUp && !claude.installed {
            StatusLabel("Sentient couldn’t finish installing Claude Code automatically.", tone: .error)
            Text("You can install it yourself in a minute with this Terminal command, then come back here:")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                Text(Self.claudeInstallCommand)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: Space.s)
                CopyButton(value: Self.claudeInstallCommand)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            HStack {
                Spacer()
                Button("Try Again") { prepareClaude(signIn: true) }
                    .buttonStyle(.bordered)
                    .disabled(busy)
            }
        } else {
            HStack {
                Spacer()
                if settings {
                    Button(busy ? "Setting Up…" : "Sign In with Claude") { prepareClaude(signIn: true) }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                } else {
                    Button(busy ? "Setting Up…" : "Sign In with Claude") { prepareClaude(signIn: true) }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                }
            }
            OnboardingStatusText(claude.loginStatusLine)
        }
    }

    private static var claudeInstallCommand: String { "curl -fsSL https://claude.ai/install.sh | bash" }

    private func prepareClaude(signIn: Bool) {
        claudePreparationTask = Task {
            guard await claude.ensureCurrent(), !Task.isCancelled else { return }
            await claude.refreshLoginStatus()
            guard !Task.isCancelled else { return }
            if signIn, !claude.loggedIn { claude.startLogin() }
            if claude.loggedIn {
                backendRaw = ModelBackend.claude.rawValue
                if layout == .settingsGrid { await ComputerUseSetup.instance(for: .cua).install() }
            }
        }
    }

    // MARK: - Configurable endpoints (OpenRouter · Custom + its local presets)

    @ViewBuilder private func endpointRows(for preset: CustomProvider.Preset) -> some View {
        Group {
            switch preset {
            case .openRouter:
                Text("Any model on OpenRouter, billed to your own key.")
            case .lmStudio:
                Text(settings
                     ? "Use an image-capable model from LM Studio. Keep its local server running while you use Sentient."
                     : "A model running on your own hardware, through LM Studio's local server. Sentient's translator makes it a first-class engine, computer use included; whether the model is up to the job is the honest question (see the note when this tab opens).")
            case .custom:
                Text("Any endpoint that speaks the OpenAI Responses API (a /v1/responses route). Base URL, model name, key if it needs one.")
            }
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        if preset != .lmStudio {
            if settings {
                DisclosureGroup("Choosing a Model for Computer Use") {
                    modelGuidance.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                modelGuidance
            }
        }

        // OpenRouter's base URL is fixed — no field, the tab pins it itself.
        if preset != .openRouter {
            LabeledContent("Base URL") {
                TextField("Base URL", text: $baseURL,
                          prompt: Text(preset == .lmStudio
                                       ? CustomProvider.Preset.lmStudio.defaultBaseURL
                                       : "https://your-endpoint.example/v1"))
                    .labelsHidden()
                    .autocorrectionDisabled()
                    .onChange(of: baseURL) { invalidate() }
            }
        }
        LabeledContent("Model") {
            TextField("Model", text: $modelName,
                      prompt: Text(preset == .openRouter ? Self.kimiSlug
                                   : preset == .lmStudio ? "the model id shown in LM Studio"
                                   : "the model id your server expects"))
                .labelsHidden()
                .autocorrectionDisabled()
                .onChange(of: modelName) { invalidate() }
        }
        LabeledContent(preset == .openRouter ? "OpenRouter API Key" : "API Key") {
            SecureField(preset == .openRouter ? "OpenRouter API Key" : "API Key", text: $apiKey,
                        prompt: Text(preset == .openRouter ? "sk-or-…" : "optional for keyless servers"))
                .labelsHidden()
                .onChange(of: apiKey) {
                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        Keychain.delete(CustomProvider.apiKeyAccount)
                    } else {
                        Keychain.set(CustomProvider.apiKeyAccount, trimmed)
                    }
                    invalidate()
                }
        }
        reasoningRow

        HStack(spacing: Space.s) {
            if isActive(preset) {
                StatusLabel("This model is running Sentient.", tone: .ok)
            }
            Spacer()
            if settings {
                Button(testing ? "Testing…" : "Test & Select") {
                    guard !testing else { return }
                    runTest(preset: preset)
                }
                .buttonStyle(.borderedProminent)
                .disabled(testing)
            } else {
                Button(testing ? "Testing…" : "Test & Select") {
                    guard !testing else { return }
                    runTest(preset: preset)
                }
                .buttonStyle(.bordered)
                .disabled(testing)
            }
        }
        if let testVerdict {
            StatusLabel(testVerdict, tone: testVerdict.hasPrefix("✓") ? .ok
                                         : testVerdict.hasPrefix("✗") ? .error : .working)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !settings {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Applies wherever this model runs.")
                Text("Stored in your Mac’s Keychain.")
                Text("Your model has to be able to see: Sentient acts on your Mac by looking at the screen, so a text-only model can't drive it. The test below checks that for you by asking your model to read a picture.")
                Text(PrivacyCopy.customProvider)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelGuidance: some View {
        Text("For computer use, consider GPT-6 Sol at low reasoning or Claude Sonnet 5 with reasoning off. Of the open-weights models we tested, Kimi K3 at low reasoning is the only one we can recommend for reliably driving computer use.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The endpoint's ONE reasoning level — free text, because models speak different dialects
    /// (`none`, `low`, `xhigh`, `adaptive`, …), applied to every run this model powers (the
    /// Speed control is ChatGPT's). Kimi wants low; Claude-class endpoints need none. Editing it
    /// re-runs the gate via the field's invalidate, since a wrong level can break the endpoint
    /// outright. The menu offers the common levels.
    private var reasoningRow: some View {
        LabeledContent("Reasoning") {
            HStack(spacing: Space.xs) {
                TextField("Reasoning", text: $reasoningRaw,
                          prompt: Text("low · none · xhigh · whatever your model supports"))
                    .labelsHidden()
                    .autocorrectionDisabled()
                    .onChange(of: reasoningRaw) { invalidate() }
                Menu {
                    ForEach(["none", "low", "medium", "high", "xhigh"], id: \.self) { level in
                        Button(level) { reasoningRaw = level }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Suggested Levels")
                .accessibilityLabel("Suggested reasoning levels")
            }
        }
    }

    /// Any edit to the endpoint retires the old verdict: a different model has to prove it can
    /// see for itself. Also drops the backend back to ChatGPT if the running engine just became
    /// unverified, so Sentient is never left pointed at an unproven model.
    private func invalidate() {
        guard verified || backend == .custom else { return }
        verified = false
        testVerdict = nil
        if backend == .custom { backendRaw = ModelBackend.chatgpt.rawValue }
    }

    private func isActive(_ preset: CustomProvider.Preset) -> Bool {
        backend == .custom && savedPreset == preset && CustomProvider.current.isUsable
    }

    /// Flip the backend to the viewed tab's endpoint — reached ONLY through a passing
    /// Test & Select run, so an unproven model can never become the engine. Fields already
    /// autosave (@AppStorage); activation is just the choice becoming official.
    private func activate(_ preset: CustomProvider.Preset) {
        presetRaw = preset.rawValue
        guard CustomProvider.current.isUsable else { return }
        backendRaw = ModelBackend.custom.rawValue
        if layout == .settingsGrid { Task { await ComputerUseSetup.instance(for: .cua).install() } }
    }

    private func runTest(preset: CustomProvider.Preset) {
        // A pending probe cannot borrow the previous preset's ready state for Continue.
        verified = false
        // OpenRouter's URL is pinned (no field on that tab); elsewhere only fill an empty one.
        if preset == .openRouter {
            baseURL = preset.defaultBaseURL
        } else if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURL = preset.defaultBaseURL
        }
        presetRaw = preset.rawValue   // the probe reads the SAVED provider — keep it current
        guard CustomProvider.current.isConfigured else {
            testVerdict = "✗ It needs a base URL and a model name first."
            return
        }
        testing = true
        testVerdict = "Preparing Codex CLI to test your model…"
        Task {
            // Custom endpoints run through Codex too. Test & Select must prepare an existing
            // older CLI just as it installs a missing one, before launching the vision probe.
            guard await CodexSetup.shared.ensureCurrent() else {
                testing = false
                verified = false
                testVerdict = CodexSetup.shared.installStatus ?? "✗ Codex CLI couldn't be prepared. Try again."
                return
            }
            testVerdict = "Showing your model a picture and asking it to read the number… local models can take a minute to load."
            let verdict = await CodexTrigger.$current.withValue(.probe) { await CodexCLI.probeCustomEndpoint() }
            await MainActor.run {
                testing = false
                switch verdict {
                case .available:
                    verified = true
                    activate(preset)   // Test & Select: a passing model becomes the engine
                    testVerdict = "✓ Your model answered and read the picture. Sentient is now running on it."
                case .notInstalled:
                    verified = false
                    testVerdict = "✗ Codex CLI couldn't be installed on this Mac (it runs the test). Check your connection and try again."
                case .notWorking(let detail):
                    verified = false
                    testVerdict = "✗ \(friendly(detail))"
                }
            }
        }
    }

    /// Reduce codex's raw stderr to one readable hint; the full detail stays in the console.
    /// A base URL missing its `/v1` is the single most common setup slip (codex appends
    /// `/responses` to whatever you give it, so the request lands on a route the server
    /// doesn't serve), so every failure carries that nudge when it applies.
    private func friendly(_ detail: String) -> String {
        let lowered = detail.lowercased()
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let v1Hint = trimmedURL.hasSuffix("/v1") ? ""
            : " Most servers also expect the base URL to end in /v1."
        if lowered.hasPrefix("blind") || lowered.contains("image input") || lowered.contains("multimodal") {
            return "This model can't see pictures, so it can't act on your Mac. Pick one that accepts images."
        }
        if lowered.contains("401") || lowered.contains("unauthorized") {
            return "The endpoint rejected the API key."
        }
        if lowered.contains("connection refused") || lowered.contains("error sending request") {
            return "Nothing is listening at that base URL. Is the server running?\(v1Hint)"
        }
        if lowered.contains("404") || lowered.contains("not found")
            || lowered.contains("unexpected endpoint") {
            return "The endpoint answered but has no /v1/responses route.\(v1Hint.isEmpty ? " It must support the OpenAI Responses API." : v1Hint)"
        }
        return "No answer from the endpoint.\(v1Hint) \(detail.prefix(180))"
    }
}


// MARK: - Kept types

/// One engine as a plain row button: its name and badge, and "In Use" on the live engine.
/// Kept compiling for source compatibility; the picker draws its own rows.
struct EngineTab: View {
    let label: String
    var badge: String? = nil
    let selected: Bool
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledContent {
                if active {
                    Label("In Use", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } label: {
                Text(label)
                if let badge { Text(label == "Custom" ? "Your endpoint" : badge.capitalized) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The "this engine is live" line — shared by the picker's endpoint details and the Settings
/// pane's ChatGPT detail.
struct FrontierActiveLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        StatusLabel(text, tone: .ok)
    }
}

#Preview("Engine picker") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            FrontierEnginePicker(tab: .constant(.openRouter)) {
                Text("ChatGPT detail")
            }
            .explainer()
            .frame(width: 640, height: 760)
            .environment(\.colorScheme, scheme)
        }
    }
}
