//
//  ProactivePane.swift
//  Sentient OS macOS
//
//  Settings › Sidekick, laid out like System Settings › Control Center: four named sections.
//  Notch: the shared Sidekick / Double Tap shortcut (ShortcutSetting) and notch clicks.
//  Sidekick: its standing instructions, which live in SidekickMemory.md. The editor saves on every
//  keystroke; a failed save stays visible and editable, and nothing reloads over it.
//  Speed & Intelligence: the model/effort every computer-use run rides (ComputerUseSpeed), as a
//  segmented control. A custom AI model carries ONE reasoning level set in AI Model (provider
//  quirks make per-run tuning unsafe there), so only .custom locks it.
//  Morning Suggestions: standing instructions for the proactive suggestion writer.
//

import SwiftUI
import AppKit

struct ProactivePane: View {
    @AppStorage(CustomInstructions.proactiveKey) private var proactiveInstructions = ""
    @AppStorage(CustomInstructions.sidekickKey) private var sidekickContext = ""
    @AppStorage(NotchPreferences.clickEnabledKey) private var notchClickEnabled = true
    @AppStorage(ShortcutPreferences.storageKey) private var keyRaw = "rightCommand"
    @AppStorage(ComputerUseSpeed.key) private var speedRaw = ComputerUseSpeed.faster.rawValue
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    @State private var memoryText = ""
    @State private var memoryError: String?
    @State private var hasUnsavedMemoryEdit = false

    private var key: ShortcutKey { ShortcutKey(rawValue: keyRaw) ?? .rightCommand }
    private var sliderLive: Bool { (ModelBackend(rawValue: backendRaw) ?? .chatgpt) != .custom }
    private var current: ComputerUseSpeed { ComputerUseSpeed(rawValue: speedRaw) ?? .faster }
    private var speed: Binding<ComputerUseSpeed> {
        Binding(get: { current }, set: { speedRaw = $0.rawValue })
    }
    private var memoryBinding: Binding<String> {
        Binding(get: { memoryText }, set: saveMemory)
    }
    private var subtitle: String {
        notchClickEnabled ? "\(key.label) · Notch click on" : key.label
    }

    var body: some View {
        PaneForm {
            notchSection
            sidekickSection
            speedSection
            morningSection
        }
        .pageSubtitle(subtitle, page: .settings, pane: .proactive)
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

    // MARK: - Notch

    private var notchSection: some View {
        Section {
            ShortcutSetting()
            Toggle("Open Sidekick by Clicking the Notch", isOn: $notchClickEnabled)
                .toggleStyle(.switch)
                .accessibilityIdentifier("settings.notchClickEnabled")
        } header: {
            Text("Notch")
        } footer: {
            Text("Make everyday help feel like your own. Tap to open Sidekick. Double-tap to draft a reply. Turn off notch clicks to leave the idle notch to apps like Alcove or Droppy. Your keyboard shortcut still works.")
        }
    }

    // MARK: - Sidekick

    private var sidekickSection: some View {
        Section {
            LabeledContent {
                EmptyView()
            } label: {
                TileLabel("Custom Instructions", tile: .memory)
            }
            SettingsTextBox(placeholder: "Use WhatsApp for messages and Safari for browsing.", text: memoryBinding)
                .accessibilityLabel("Sidekick custom instructions")
            if let memoryError {
                LabeledContent {
                    if hasUnsavedMemoryEdit {
                        Button("Retry Saving") { saveMemory(memoryText) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } label: {
                    StatusLabel(memoryError, tone: .error)
                }
                .accessibilityLabel("Sidekick memory error: " + memoryError)
            }
        } header: {
            Text("Sidekick")
        } footer: {
            Text("Sidekick learns your preferences as you work. Edit its instructions anytime.")
        }
    }

    // MARK: - Speed & Intelligence

    private var speedSection: some View {
        Section {
            Picker(selection: speed) {
                ForEach(ComputerUseSpeed.allCases, id: \.self) { tier in
                    Text(tier.label).tag(tier)
                }
            } label: {
                HStack(spacing: Space.s) {
                    TileLabel("Speed & Intelligence", tile: .speed)
                    if !sliderLive {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Locked")
                    }
                }
            }
            .pickerStyle(.segmented)
            .disabled(!sliderLive)
            .accessibilityLabel("Speed and intelligence")
            .accessibilityValue("\(current.label), \(current.modelLine)")
        } header: {
            Text("Speed & Intelligence")
        } footer: {
            Text("Choose how much thought goes into computer tasks. "
                 + (sliderLive
                    ? "\(current.modelLine). Faster for everyday tasks. Smarter for the tricky ones."
                    : "Your custom model uses the reasoning level set in AI Model."))
        }
    }

    // MARK: - Morning Suggestions

    private var morningSection: some View {
        Section {
            LabeledContent {
                EmptyView()
            } label: {
                TileLabel("Instructions", tile: .morningSuggestions)
            }
            SettingsTextBox(placeholder: "Focus on work follow-ups. Skip shopping and bank alerts.", text: $proactiveInstructions)
                .accessibilityLabel("Morning suggestion instructions")
        } header: {
            Text("Morning Suggestions")
        } footer: {
            Text("Tell Sentient what to focus on, and what to skip. Instructions and preferences save automatically.")
        }
    }

    // MARK: - Memory file

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
}

#Preview("Sidekick pane") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            ProactivePane()
                .frame(width: 720, height: 760)
                .environment(\.colorScheme, scheme)
        }
    }
}
