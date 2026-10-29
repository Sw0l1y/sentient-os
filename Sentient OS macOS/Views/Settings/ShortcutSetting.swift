// ShortcutSetting.swift
// The shared shortcut row (Keyboard › Keyboard Shortcuts style: a label and a popup) and the
// single-key recorder sheet, for Sidekick and Double Tap. "Other…" opens a fitted recorder sheet
// that shows the key as a key cap; nothing is saved until Use Key, and Cancel keeps the binding.
// Doc: Documentation - Settings.md

import AppKit
import SwiftUI

/// One Form row: "Shortcut Key" and its popup. Its explanation lives in the host Section's footer.
struct ShortcutSetting: View {
    @AppStorage(ShortcutPreferences.storageKey) private var keyRaw = "rightCommand"
    @State private var recording = false

    private var key: ShortcutKey { ShortcutKey(rawValue: keyRaw) ?? .rightCommand }
    private var selection: Binding<String> {
        Binding(get: { key.rawValue }, set: { value in
            if value == "other" {
                ShortcutPreferences.setRecording(true)
                recording = true
            } else if let key = ShortcutKey(rawValue: value) {
                ShortcutPreferences.save(key)
            }
        })
    }

    var body: some View {
        LabeledContent("Shortcut Key") {
            SettingsMenu(title: "Sidekick shortcut", value: key.label, selection: selection) {
                Text("Right ⌘").tag(ShortcutKey.rightCommand.rawValue)
                Text("Right ⌥").tag(ShortcutKey.rightOption.rawValue)
                if key != .rightCommand && key != .rightOption {
                    Text(key.label).tag(key.rawValue)
                }
                Divider()
                Text("Other…").tag("other")
            }
            .frame(width: 150)
        }
        // The one row-level sheet in Settings (area rule 1's exception): it is modal, so the row
        // cannot scroll away while it is up.
        .sheet(isPresented: $recording, onDismiss: { ShortcutPreferences.setRecording(false) }) {
            ShortcutRecorderSheet(current: key)
                .environment(\.settingsFormStyle, false)
        }
        .onDisappear {
            if recording { ShortcutPreferences.setRecording(false) }
        }
    }
}

/// "Press a key": the current key on a keyboard row, the recorded key as a lit key cap, Cancel and
/// Use Key. Global shortcuts are suspended while it is open.
private struct ShortcutRecorderSheet: View {
    /// The saved key, shown lit on the keyboard row until a new key is pressed.
    let current: ShortcutKey
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: ShortcutKey?
    @State private var error: String?

    var body: some View {
        VStack(spacing: Space.l) {
            IconTile(.shortcutKey, size: 64)
            Text("Sidekick Shortcut")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("The same key is used for Sidekick and Double Tap. Press and release Command, Option, or Control on either side of your keyboard.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Space.s) {
                if let candidate {
                    KeyCap(key: candidate, highlighted: true)
                } else {
                    KeyCapRow(highlighting: current)
                }
                Text(candidate?.label ?? "Press a key…")
                    .font(.headline)
                    .foregroundStyle(candidate == nil ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentShape(Rectangle())
            // The key listener sits behind the preview, so a click there refocuses it.
            .background {
                ShortcutRecorderInput(onKey: { candidate = $0; error = nil },
                                      onError: { candidate = nil; error = $0 },
                                      onCancel: { dismiss() })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recorded key")
            .accessibilityValue(candidate?.spokenLabel ?? "Waiting for a key")

            Group {
                if let error {
                    StatusLabel(error, tone: .error)
                } else {
                    Text("Press one modifier key by itself, without a key combination.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 32, alignment: .top)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Use Key") {
                    guard let candidate else { return }
                    ShortcutPreferences.save(candidate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(candidate == nil)
            }
        }
        .padding(Space.xl)
        .frame(width: 420)
        .presentationSizing(.fitted)
        .onDisappear { ShortcutPreferences.setRecording(false) }
    }
}

/// This responder only sees events in its own focused sheet. Global shortcuts are suspended.
private struct ShortcutRecorderInput: NSViewRepresentable {
    let onKey: (ShortcutKey) -> Void
    let onError: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyView { KeyView() }

    func updateNSView(_ view: KeyView, context: Context) {
        view.onKey = onKey
        view.onError = onError
        view.onCancel = onCancel
    }

    final class KeyView: NSView {
        var onKey: ((ShortcutKey) -> Void)?
        var onError: ((String) -> Void)?
        var onCancel: (() -> Void)?
        private var pending: ShortcutKey?
        private var tap = ShortcutTap()
        private var focusObserver: NSObjectProtocol?
        override var acceptsFirstResponder: Bool { true }

        deinit {
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
            focusObserver = nil
            pending = nil
            tap = ShortcutTap()
            guard let window else { return }
            focusObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.pending = nil
                        self?.tap = ShortcutTap()
                    }
                }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, event.type == .keyDown,
                  !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                return super.performKeyEquivalent(with: event)
            }
            // Reject combinations inside the recorder before an app menu can handle them.
            reject()
            return true
        }

        override func flagsChanged(with event: NSEvent) {
            if let pending {
                let down = UInt64(event.modifierFlags.rawValue) & pending.deviceBit != 0
                let alone = down ? pending.isAlone(in: event.modifierFlags)
                    : event.modifierFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty
                finish(pending, down: down, alone: alone)
                return
            }
            guard let key = ShortcutKey(keyCode: event.keyCode) else {
                reject()
                return
            }
            guard UInt64(event.modifierFlags.rawValue) & key.deviceBit != 0 else { return }
            begin(key, alone: key.isAlone(in: event.modifierFlags))
        }

        override func keyDown(with event: NSEvent) {
            guard !event.isARepeat else { return }
            if event.keyCode == 53 { onCancel?(); return }
            reject()
        }

        private func begin(_ key: ShortcutKey, alone: Bool) {
            guard alone else { reject(); return }
            pending = key
            tap = ShortcutTap()
            _ = tap.update(down: true, alone: true, at: ProcessInfo.processInfo.systemUptime,
                           activity: .current)
        }

        private func finish(_ key: ShortcutKey, down: Bool, alone: Bool) {
            let valid = tap.update(down: down, alone: alone, at: ProcessInfo.processInfo.systemUptime,
                                   activity: .current, maximumDuration: .infinity)
            if !alone { onError?("Use one key by itself, without another modifier.") }
            if !down {
                pending = nil
                if valid { onKey?(key) }
                else { onError?("Press and release one key by itself.") }
            }
        }

        private func reject() {
            tap.cancel()
            onError?("Use a Command, Option, or Control key by itself.")
        }
    }
}

#if DEBUG
#Preview("Shortcut row") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            PaneForm { Section { ShortcutSetting() } }
                .frame(width: 560, height: 200)
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Record a shortcut") {
    ShortcutRecorderSheet(current: .rightCommand)
}
#endif
