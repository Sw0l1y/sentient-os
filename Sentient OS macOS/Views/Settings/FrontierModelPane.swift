//
//  FrontierModelPane.swift
//  Sentient OS macOS
//
//  Settings › AI Model: which frontier engine powers the cloud ~10% of Sentient (the on-device
//  model does the rest). The SHARED FrontierEnginePicker is the pane's Form (the engine radio
//  list and the browsed engine's detail, which onboarding's Choose Your AI page renders too);
//  what's Settings' own here is the ChatGPT detail — activate directly with Use ChatGPT, and
//  point at Permissions & Health for login and plan (onboarding embeds the live login instead) —
//  and the window subtitle naming the engine in use. Writes ModelBackend/CustomProvider (the one
//  source of truth); everything applies to the very next run, no restart.
//

import SwiftUI

struct FrontierModelPane: View {

    @State private var tab: FrontierEngineTab = .chatgpt

    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    @AppStorage(CustomProvider.presetKey) private var presetRaw = CustomProvider.Preset.openRouter.rawValue

    private var backend: ModelBackend { ModelBackend(rawValue: backendRaw) ?? .chatgpt }

    /// The engine in use, as the window subtitle ("ChatGPT", "Claude", "OpenRouter", …).
    private var subtitle: String {
        FrontierEngineTab(backend: backend, preset: CustomProvider.Preset(rawValue: presetRaw) ?? .openRouter)
            .label.replacingOccurrences(of: " Subscription", with: "")
    }

    var body: some View {
        FrontierEnginePicker(tab: $tab) {
            chatgptPanel
        }
        .explainer()
        .pageSubtitle(subtitle, page: .settings, pane: .frontierModel)
    }

    // MARK: - ChatGPT (Settings' own detail rows — login honesty lives in Permissions & Health)

    @ViewBuilder private var chatgptPanel: some View {
        Text("Use your ChatGPT subscription for knowledge, morning suggestions, and Sidekick.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if backend == .chatgpt {
            LabeledContent {
                Button("Manage Account…") {
                    MainNavigation.shared.show(.settings, settingsPane: .health)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } label: {
                FrontierActiveLine("Using ChatGPT")
            }
        } else {
            HStack {
                Spacer()
                Button("Use ChatGPT") {
                    backendRaw = ModelBackend.chatgpt.rawValue
                    // The commitment moment — the lazy codex install fires here (a
                    // detection-first no-op when the CLI already exists).
                    Task {
                        await CodexSetup.shared.ensureInstalled()
                        guard backendRaw == ModelBackend.chatgpt.rawValue else { return }
                        await ComputerUseSetup.instance(for: .openAI).install()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview("AI Model") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            FrontierModelPane()
                .environment(\.settingsFormStyle, true)
                .frame(width: 720, height: 820)
                .environment(\.colorScheme, scheme)
        }
    }
}
