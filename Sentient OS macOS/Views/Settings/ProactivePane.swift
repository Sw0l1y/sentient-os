//
//  ProactivePane.swift
//  Sentient OS macOS
//
//  Settings → Proactive & Sidekick: the user's standing instructions for the proactive
//  suggestion writer, Sidekick's shortcut key + standing context, and the speed-vs-intelligence
//  slider (ComputerUseSpeed — the model/effort EVERY computer-use run rides, per engine). The strings
//  persist and autosave. ShortcutSetting edits the shared Sidekick and Double Tap binding live. The
//  Sidekick editor writes SidekickMemory.md; its defaults mirror refreshes the editor after
//  agent writes. External edits refresh on appearance and app activation.
//

import SwiftUI

struct ProactivePane: View {
    @AppStorage(CustomInstructions.proactiveKey) private var proactiveInstructions = ""
    @AppStorage(CustomInstructions.sidekickKey) private var sidekickContext = ""
    @AppStorage(NotchPreferences.clickEnabledKey) private var notchClickEnabled = true
    @State private var memoryText = ""
    @State private var memoryError: String?
    @State private var hasUnsavedMemoryEdit = false
    @AppStorage(ComputerUseSpeed.key) private var speedRaw = ComputerUseSpeed.faster.rawValue
    /// The slider drives the subscription engines (ChatGPT and Claude); a custom frontier model
    /// carries ONE reasoning level set in Frontier Model Choice (provider quirks make per-run
    /// tuning unsafe there), so only .custom locks it.
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue

    private var sliderLive: Bool { (ModelBackend(rawValue: backendRaw) ?? .chatgpt) != .custom }

    var body: some View {
        SettingsPane(title: "Proactive & Sidekick",
                     whisper: "Make everyday help feel like your own.") {
            VStack(alignment: .leading, spacing: 32) {
                SettingsGroup(label: "Sidekick", inset: 0) {
                    VStack(spacing: 0) {
                        ShortcutSetting()
                        SettingsHairline(opacity: 0.10)
                        SettingToggleLine(title: "Open Sidekick by clicking the notch",
                            sub: "Turn off to leave the idle notch to apps like Alcove or Droppy. Your keyboard shortcut still works.",
                            isOn: $notchClickEnabled)
                            .accessibilityIdentifier("settings.notchClickEnabled")
                        SettingsHairline(opacity: 0.10)
                        VStack(alignment: .leading, spacing: 12) {
                            instructionLabel("Custom instructions", detail: "Sidekick learns your preferences as you work. Edit its instructions anytime.")
                            SettingsTextBox(placeholder: "Use WhatsApp for messages and Safari for browsing.", text: Binding(
                                get: { memoryText }, set: saveMemory))
                                .frame(height: 104)
                                .accessibilityLabel("Sidekick custom instructions")
                            if let memoryError {
                                Text(memoryError).font(.callout).foregroundStyle(.red)
                                    .accessibilityLabel("Sidekick memory error: " + memoryError)
                                if hasUnsavedMemoryEdit {
                                    Button("Retry saving") { saveMemory(memoryText) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(20)
                    }
                }

                SettingsGroup(label: "Speed & intelligence",
                              description: "Choose how much thought goes into computer tasks.") {
                    VStack(alignment: .leading, spacing: 16) {
                        SpeedIntelligenceSlider(selection: Binding(
                            get: { ComputerUseSpeed(rawValue: speedRaw) ?? .faster },
                            set: { speedRaw = $0.rawValue }))
                            .disabled(!sliderLive)
                            .allowsHitTesting(sliderLive)
                            .opacity(sliderLive ? 1 : 0.4)
                        SettingsProse(sliderLive
                            ? "Faster for everyday tasks. Smarter for the tricky ones."
                            : "Your custom model uses the reasoning level set in Frontier Model Choice.")
                    }
                }

                SettingsGroup(label: "Morning suggestions",
                              description: "Tell Sentient what to focus on, and what to skip.") {
                    SettingsTextBox(placeholder: "Focus on work follow-ups. Skip shopping and bank alerts.", text: $proactiveInstructions)
                        .frame(height: 104)
                        .accessibilityLabel("Morning suggestion instructions")
                }
                Text("Instructions and preferences save automatically.")
                    .font(.callout).foregroundStyle(SettingsStyle.secondary)
            }
        }
        .onAppear(perform: refreshMemory)
        .onChange(of: notchClickEnabled) { _, _ in
            NotificationCenter.default.post(name: .notchInteractionChanged, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMemory()
        }
        .onChange(of: sidekickContext) { _, value in
            if !hasUnsavedMemoryEdit { memoryText = value; memoryError = nil }
        }
    }

    private func refreshMemory() {
        // Keep a failed save visible and editable; activation must not silently discard it.
        guard !hasUnsavedMemoryEdit else { return }
        do {
            memoryText = try SidekickInstructionStore.read().text
            memoryError = nil
        } catch {
            memoryError = "Couldn’t read Sidekick memory. " + error.localizedDescription
            SidekickDiagnostics.failure(.memoryRead, reason: .readFailed, source: .memoryEditor)
        }
    }

    private func saveMemory(_ text: String) {
        memoryText = text
        hasUnsavedMemoryEdit = true
        do {
            try CustomInstructions.saveSidekick(text)
            hasUnsavedMemoryEdit = false
            memoryError = nil
        } catch {
            memoryError = "Your edit hasn’t been saved. " + error.localizedDescription
            SidekickDiagnostics.failure(.memoryWrite, reason: .writeFailed, source: .memoryEditor)
        }
    }

    private func instructionLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.medium)).foregroundStyle(.primary)
            SettingsProse(detail)
        }
    }
}

// MARK: - The speed-vs-intelligence slider

/// A three-stop system slider (Faster · Balanced · Smarter). The readout underneath names the
/// tier and the honest spec (model · how hard it thinks).
private struct SpeedIntelligenceSlider: View {
    @Binding var selection: ComputerUseSpeed

    private var stop: Binding<Double> {
        Binding(get: { Double(ComputerUseSpeed.allCases.firstIndex(of: selection) ?? 1) },
                set: { selection = ComputerUseSpeed.allCases[min(max(Int($0.rounded()), 0), ComputerUseSpeed.allCases.count - 1)] })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: stop, in: 0...Double(ComputerUseSpeed.allCases.count - 1), step: 1) {
                Text("Speed and intelligence")
            } minimumValueLabel: {
                Image(systemName: "hare").accessibilityLabel("Faster")
            } maximumValueLabel: {
                Image(systemName: "brain").accessibilityLabel("Smarter")
            }
            .labelsHidden()
            HStack(alignment: .firstTextBaseline) {
                Text(selection.label).font(.callout.weight(.medium))
                Spacer()
                Text(selection.modelLine).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 300)
        .accessibilityValue("\(selection.label), \(selection.modelLine)")
    }
}

#Preview("Proactive & Sidekick pane") {
    ProactivePane()
        .background(Theme.bg)
        .frame(width: 720, height: 760)
}
