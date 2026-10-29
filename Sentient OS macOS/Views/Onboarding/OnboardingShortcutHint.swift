// A small, window-local correction for the two live onboarding lessons.
// No global keyboard listener, permission request or typed-character capture.
import AppKit
import SwiftUI

struct OnboardingWrongCommandTap {
    private var tap = ShortcutTap()

    mutating func flagsChanged(keyCode: UInt16, flags: NSEvent.ModifierFlags,
                              at time: TimeInterval, activity: ShortcutActivity,
                              lastInputTime: TimeInterval, eligible: Bool,
                              mouseIsDown: Bool) -> Bool {
        guard eligible else { reset(); return false }
        guard keyCode == ShortcutKey.leftCommand.keyCode else { tap.cancel(); return false }
        let down = UInt64(flags.rawValue) & ShortcutKey.leftCommand.deviceBit != 0
        let alone = down ? ShortcutKey.leftCommand.isAlone(in: flags)
            : flags.intersection([.command, .option, .control, .shift, .function]).isEmpty
        return tap.update(down: down, alone: alone && !mouseIsDown, at: time,
                          activity: activity, lastInputTime: lastInputTime)
    }

    mutating func interrupt() { tap.cancel() }
    mutating func reset() { tap = ShortcutTap() }
}

@MainActor @Observable
final class OnboardingShortcutHint {
    static let duration: TimeInterval = 1
    private(set) var acceptsInput = false
    private(set) var began: TimeInterval?
    private(set) var pulseCount = 0
    private var expiry: Task<Void, Never>?
    var isActive: Bool { began != nil }

    func activate() { acceptsInput = true }
    func deactivate() { acceptsInput = false; clear() }
    func clear() { expiry?.cancel(); expiry = nil; began = nil }

    func flash() {
        // A mistaken double tap is one gentle correction, not two flashing restarts.
        guard acceptsInput, began == nil else { return }
        let start = ProcessInfo.processInfo.systemUptime
        began = start; pulseCount += 1
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Self.duration)) } catch { return }
            guard let self, self.began == start else { return }
            self.began = nil; self.expiry = nil
        }
    }

    func progress(at time: TimeInterval) -> Double {
        guard let began else { return 1 }
        return min(1, max(0, (time - began) / Self.duration))
    }
}

/// The instruction line ("Press right Command"), in the caller's font. A mistaken left ⌘ tap
/// lights the word "right" with a Find-style accent highlight that fades over one second. With
/// `showsKeycap`, the key's cap is drawn before the words. One accessibility label.
/// This file is compiled standalone by Scripts/test_onboarding_shortcut_hint.swift, so it names
/// no Views/Design type: the keycap below is drawn here to match KeyCap.
struct OnboardingShortcutInstruction: View {
    let prefix: String
    let key: ShortcutKey
    var suffix = ""
    let hint: OnboardingShortcutHint
    /// Kept for source compatibility; ignored (the text follows the caller's style).
    var onLight = false
    var showsKeycap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if showsKeycap {
                InstructionKeycap(glyph: String(key.label.suffix(1)))
                    .padding(.trailing, 6)
            }
            Text(prefix).fixedSize()
            if key == .rightCommand {
                Text("right")
                    .fixedSize()
                    .background { highlight }
                Text(" Command" + suffix).fixedSize()
            } else {
                Text(key.spokenLabel + suffix).fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(prefix + key.spokenLabel + suffix)
    }

    /// The accent highlight behind "right": full strength on a mistaken tap, easing out over
    /// the hint's duration (static while Reduce Motion is on).
    private var highlight: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !hint.isActive || reduceMotion)) { _ in
            let p = hint.progress(at: ProcessInfo.processInfo.systemUptime)
            let eased = p * p * (3 - 2 * p)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.accentColor.opacity(0.28))
                .padding(.horizontal, -2)
                .opacity(hint.isActive ? (reduceMotion ? 1 : 1 - eased) : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A small keycap drawn to match KeyCap (quaternary fill, separator hairline).
private struct InstructionKeycap: View {
    let glyph: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text(glyph)
            .font(.callout.weight(.medium))
            .frame(width: 22, height: 22)
            .background(shape.fill(.quaternary))
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct OnboardingWrongCommandMonitor: NSViewRepresentable {
    let hint: OnboardingShortcutHint
    var enabled: Bool
    var onMistake: () -> Void = {}

    func makeNSView(context: Context) -> Probe {
        let view = Probe(hint: hint)
        view.configure(enabled: enabled, onMistake: onMistake)
        return view
    }
    func updateNSView(_ view: Probe, context: Context) {
        view.configure(enabled: enabled, onMistake: onMistake)
    }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: NSView {
        let hint: OnboardingShortcutHint
        private var enabled = false
        private var onMistake: () -> Void = {}
        private var detector = OnboardingWrongCommandTap()
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private(set) var isMonitoring = false

        init(hint: OnboardingShortcutHint) { self.hint = hint; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(enabled: Bool, onMistake: @escaping () -> Void) {
            self.onMistake = onMistake
            if self.enabled != enabled { reset() }
            self.enabled = enabled
            if enabled { attachIfNeeded() } else { detach() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach(); attachIfNeeded()
        }

        private func attachIfNeeded() {
            guard enabled, monitor == nil, let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown,
                .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
                self?.receive(event)
                return event // The original shortcut and normal app input always continue.
            }
            isMonitoring = monitor != nil
            for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject),
                                   (NSWindow.willCloseNotification, window as AnyObject),
                                   (NSApplication.didResignActiveNotification, NSApp as AnyObject)] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: object,
                    queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.reset() } })
            }
        }

        private func receive(_ event: NSEvent) {
            guard enabled, hint.acceptsInput, ShortcutPreferences.current == .rightCommand,
                  !ShortcutPreferences.isRecording, NSApp.isActive,
                  let window, window.isKeyWindow, window.isVisible,
                  event.window == nil || event.window === window,
                  !isHiddenOrHasHiddenAncestor else { reset(); return }
            guard event.type == .flagsChanged else { detector.interrupt(); hint.clear(); return }
            if event.keyCode == ShortcutKey.rightCommand.keyCode { hint.clear() }
            if detector.flagsChanged(keyCode: event.keyCode, flags: event.modifierFlags,
                at: event.timestamp, activity: .current, lastInputTime: ShortcutActivity.lastInputTime,
                eligible: true, mouseIsDown: NSEvent.pressedMouseButtons != 0) {
                onMistake(); hint.flash()
            }
        }

        private func reset() { detector.reset(); hint.clear() }
        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
            isMonitoring = false; reset()
        }
    }
}
