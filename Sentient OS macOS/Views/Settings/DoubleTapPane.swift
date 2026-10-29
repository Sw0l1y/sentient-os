// DoubleTapPane.swift
// Settings › Double Tap, laid out like System Settings › Keyboard: the shortcut first, then the
// drafting model and its credentials, the autosaved custom instructions with a live byte count,
// the writing examples, and what is shared. DoubleTapCredentials keeps unsaved keys in view state
// and persists them only to Keychain on Save.
// Doc: Documentation - Settings.md

import SwiftUI
import Combine
import AppKit

struct DoubleTapPane: View {
    @AppStorage(CustomInstructions.doubleTapKey) private var instructions = ""
    @AppStorage(DoubleTapProvider.key) private var providerRaw = DoubleTapProvider.sentient.rawValue
    @AppStorage(DoubleTap.enabledKey) private var doubleTapEnabled = true
    @AppStorage(ShortcutPreferences.storageKey) private var keyRaw = "rightCommand"
    @State private var activity = PipelineActivity.shared
    @State private var hasWritingExamples = WritingStyle.exists()
    @State private var hasWritingSources = WritingStyle.hasSources
    @State private var collectingExamples = false
    @State private var writingStatus: String?

    private var provider: DoubleTapProvider { DoubleTapProvider(rawValue: providerRaw) ?? .sentient }
    private var key: ShortcutKey { ShortcutKey(rawValue: keyRaw) ?? .rightCommand }

    /// Today's rule: the trimmed instructions' UTF-8 size against the Double Tap limit.
    private var bytes: Int { instructions.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count }
    private var overLimit: Bool { bytes > CustomInstructions.doubleTapByteLimit }

    var body: some View {
        PaneForm {
            Section {
                ShortcutSetting()
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Replies in your voice, ready for you to review. The same key opens Sidekick. Double-tap it to draft a reply.")
            }

            Section {
                LabeledContent("Provider") {
                    SettingsMenu(title: "Double Tap provider", value: provider.label, selection: $providerRaw) {
                        ForEach(DoubleTapProvider.allCases) { provider in
                            Text(provider.label).tag(provider.rawValue)
                        }
                    }
                    .frame(width: 200)
                }
                if provider == .sentient {
                    Text(PrivacyCopy.doubleTapCovered)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    DoubleTapCredentials(provider: provider).id(provider)
                }
            } header: {
                Text("Drafting Model")
            } footer: {
                Text("Independent of your Sidekick model.")
            }

            Section {
                SettingsTextBox(placeholder: "Keep texts casual and lowercase. Use a professional tone for email.",
                                text: $instructions)
                    .frame(minHeight: 112)
                    .accessibilityLabel("Double Tap custom instructions")
            } header: {
                Text("Custom Instructions")
            } footer: {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Tell Double Tap how you like to write.")
                    HStack(alignment: .firstTextBaseline) {
                        if overLimit {
                            StatusLabel("These instructions are too long. Shorten them before using Double Tap.", tone: .error)
                        } else {
                            Text("Saved automatically for every reply.")
                        }
                        Spacer(minLength: Space.m)
                        Text("\(bytes.formatted()) of \(CustomInstructions.doubleTapByteLimit.formatted())")
                            .monospacedDigit()
                            .accessibilityLabel("\(bytes.formatted()) of \(CustomInstructions.doubleTapByteLimit.formatted()) bytes")
                    }
                }
            }

            Section {
                LabeledContent {
                    if hasWritingExamples {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([
                                VaultGenerator.vaultRoot.appendingPathComponent(WritingStyle.fileName)
                            ])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(collectingExamples ? "Collecting…" : "Collect Examples", action: collectExamples)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(collectingExamples || activity.isRunning || !hasWritingSources
                                || !FileManager.default.fileExists(atPath: VaultGenerator.vaultRoot.appendingPathComponent("README.md").path))
                    }
                } label: {
                    TileLabel("Your Writing Examples", subtitle: hasWritingExamples ? "Collected" : nil,
                              tile: .writingExamples)
                }
                if let writingStatus {
                    StatusLabel(writingStatus, tone: writingStatusTone(writingStatus))
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup("How Writing Examples Are Used") {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(PrivacyCopy.writingSamples)
                        Text(PrivacyCopy.writingSources)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Writing Examples")
            } footer: {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if hasWritingExamples {
                        Text("A one-time snapshot you can inspect and edit.")
                    } else {
                        Text("Optional. Double Tap can use your instructions and visible conversation.")
                        if !hasWritingSources && writingStatus == nil {
                            Text("Choose chats or an email source in Knowledge Sources to add examples of your own writing.")
                        }
                    }
                }
            }

            Section {
                DisclosureGroup("What Is Shared with This Provider?") {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(PrivacyCopy.doubleTapContext)
                        Text(routeLine)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .pageSubtitle(doubleTapEnabled ? "\(key.label) · On" : "Off", page: .settings, pane: .doubleTap)
        .onAppear(perform: refreshWritingState)
        .onChange(of: activity.isRunning) { _, _ in refreshWritingState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshWritingState() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)) { _ in refreshWritingState() }
    }

    /// Where the drafting context goes, by provider.
    private var routeLine: String {
        provider == .sentient
            ? "This context passes through Sentient’s relay to OpenAI."
            : provider.hasCustomEndpoint
            ? "This context goes directly to your configured endpoint. For local drafting, use a local model served on this Mac."
            : "This context goes directly to your chosen \(provider.name) provider, under its policies and your account settings."
    }

    private func writingStatusTone(_ status: String) -> StatusTone {
        if status.hasPrefix("Writing examples are ready") { return .ok }
        if status.hasPrefix("Examples could not be collected") { return .error }
        return .info
    }

    private func refreshWritingState() {
        hasWritingExamples = WritingStyle.exists()
        hasWritingSources = WritingStyle.hasSources
    }

    private func collectExamples() {
        guard !collectingExamples, !activity.isRunning, !WritingStyle.exists(), WritingStyle.hasSources else { return }
        collectingExamples = true; writingStatus = nil
        Task { @MainActor in
            defer { collectingExamples = false; refreshWritingState() }
            do {
                try await WritingStyle.generateIfNeeded()
                writingStatus = WritingStyle.exists() ? "Writing examples are ready."
                    : "No sent examples were found in your selected sources. Double Tap still works with your conversation and instructions."
            } catch is CancellationError { }
            catch {
                writingStatus = "Examples could not be collected. Check your selected sources and try again. Double Tap remains available."
            }
        }
    }
}

/// The chosen provider's endpoint, key and model, as rows of the "Drafting Model" Section.
private struct DoubleTapCredentials: View {
    let provider: DoubleTapProvider
    @AppStorage private var model: String
    @AppStorage private var baseURL: String
    @AppStorage private var apiRaw: String
    @State private var keyDraft = ""
    @State private var keySaved = false
    @State private var keyError: String?
    @State private var editingOtherModel = false

    init(provider: DoubleTapProvider) {
        self.provider = provider
        _model = AppStorage(wrappedValue: provider.defaultModel, provider.modelKey)
        _baseURL = AppStorage(wrappedValue: provider.defaultBaseURL, provider.baseURLKey)
        _apiRaw = AppStorage(wrappedValue: DoubleTapProvider.API.chatCompletions.rawValue, provider.apiFormatKey)
    }

    private var trimmedKey: String { keyDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isPreset: Bool {
        DoubleTapProvider.modelPresets.contains { provider.modelID($0.id) == model }
    }
    private var modelSelection: Binding<String> {
        Binding(get: { editingOtherModel || !isPreset ? "other" : model }, set: { value in
            editingOtherModel = value == "other"
            model = editingOtherModel ? "" : value
        })
    }

    /// Several Form rows. Only the key row carries the Keychain probe (a modifier on this view
    /// would run once per row).
    @ViewBuilder var body: some View {
        if provider.hasCustomEndpoint {
            LabeledContent("Base URL") {
                TextField("Base URL", text: $baseURL,
                          prompt: Text(provider.defaultBaseURL.isEmpty ? "https://your-endpoint.example/v1" : provider.defaultBaseURL))
                    .labelsHidden()
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .accessibilityLabel("\(provider.name) base URL")
            }
            if DoubleTapProvider.endpoint(baseURL: baseURL,
                                          api: DoubleTapProvider.API(rawValue: apiRaw) ?? .chatCompletions) == nil {
                StatusLabel("Enter a valid http:// or https:// base URL, including its API prefix (usually /v1).", tone: .error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("API Format") {
                SettingsMenu(title: "API format", value: (DoubleTapProvider.API(rawValue: apiRaw) ?? .chatCompletions).label, selection: $apiRaw) {
                    ForEach(DoubleTapProvider.API.allCases) { api in
                        Text(api.label).tag(api.rawValue)
                    }
                }
                .frame(width: 240)
            }
            Text("Use Chat Completions for most compatible servers, or Responses if your endpoint requires it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        LabeledContent(provider.requiresKey ? "\(provider.name) API Key" : "API Key (Optional)") {
            HStack(spacing: Space.s) {
                SecureField("API Key", text: $keyDraft,
                            prompt: Text(keySaved ? "Enter a replacement key"
                                         : provider.requiresKey ? "Enter your API key" : "Optional for keyless servers"))
                    .labelsHidden()
                    .accessibilityLabel("\(provider.name) API key")
                    .onSubmit(saveKey)
                Button("Save", action: saveKey)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(trimmedKey.isEmpty)
            }
        }
        .onAppear { keySaved = provider.apiKey != nil }

        if keySaved {
            LabeledContent {
                Button("Remove") {
                    if provider.removeKey() {
                        keySaved = false
                        keyDraft = ""
                        keyError = nil
                    } else {
                        keyError = "Couldn't remove the key. Unlock your Mac and try again."
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } label: {
                StatusLabel("Saved in Keychain", tone: .ok)
            }
        } else {
            Text(provider.requiresKey ? "Save your API key to use \(provider.name)."
                 : "Leave empty if your server does not require an API key.")
                .foregroundStyle(.secondary)
        }
        if let keyError {
            StatusLabel(keyError, tone: .error)
        }

        if provider.hasModelPresets {
            LabeledContent("Model") {
                SettingsMenu(title: "Model", value: DoubleTapProvider.modelPresets.first(where: { provider.modelID($0.id) == model })?.label ?? "Other model…", selection: modelSelection) {
                    ForEach(DoubleTapProvider.modelPresets, id: \.id) { preset in
                        Text(preset.label).tag(provider.modelID(preset.id))
                    }
                    Text("Other model…").tag("other")
                }
                .frame(width: 240)
            }
        }
        if !provider.hasModelPresets || editingOtherModel || !isPreset {
            LabeledContent("Model ID") {
                TextField("Model ID", text: $model,
                          prompt: Text(provider == .openRouter ? "provider/model-id"
                                       : provider == .ollama ? "e.g. gemma4:e4b" : "model-id"))
                    .labelsHidden()
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .accessibilityLabel("\(provider.name) model ID")
            }
            Text("Enter a model ID from \(provider.name) that supports images and text replies.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if provider.hasCustomEndpoint {
            Text("Choose a model with enough context for your knowledge base. If you use a local server, keep it running with the model loaded. Double Tap stops after 30 seconds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Saved automatically. Applies to the next Double Tap reply.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Usage is billed to your \(provider.name) account.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func saveKey() {
        guard !trimmedKey.isEmpty else { return }
        if provider.saveKey(trimmedKey) {
            keySaved = true
            keyDraft = ""
            keyError = nil
        } else {
            keyError = "Couldn't save the key. Unlock your Mac and try again."
        }
    }
}


#Preview("Double Tap") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            DoubleTapPane()
                .environment(\.settingsFormStyle, true)
                .frame(width: 680, height: 740)
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Ollama provider") {
    PaneForm {
        Section("Drafting Model") { DoubleTapCredentials(provider: .ollama) }
    }
    .frame(width: 600, height: 520)
}
