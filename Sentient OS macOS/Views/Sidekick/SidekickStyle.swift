import SwiftUI
import AppKit

extension EnvironmentValues {
    // Optional overrides are used by the isolated rendering lab; production follows macOS.
    @Entry var sidekickReduceMotionOverride: Bool? = nil
    @Entry var sidekickReduceTransparencyOverride: Bool? = nil
    @Entry var sidekickHoveredMessageID: String? = nil
    @Entry var sidekickHoveredCardID: String? = nil
}

/// Retired tokens (SPEC-00 4.3). After the final cleanup (4.1) only `motion(_:)` remains, because
/// SidekickUILab still calls it; every other retired Sidekick token, surface and style had no users
/// and was deleted.
enum SidekickStyle {
    /// `Motion.standard` through `Motion.gated`: nil (no animation) when `reduced` or in Low Power Mode.
    @available(*, deprecated, message: "Use Motion.gated(Motion.standard, reduceMotion:)")
    static func motion(_ reduced: Bool) -> Animation? {
        Motion.gated(Motion.standard, reduceMotion: reduced)
    }
}

/// Tracks the real native window, so hidden/occluded Home never consumes unread messages.
struct SidekickWindowPresence: NSViewRepresentable {
    var requiresKeyWindow = false
    var changed: (Bool) -> Void
    func makeNSView(context: Context) -> Probe { Probe(requiresKeyWindow: requiresKeyWindow, changed: changed) }
    func updateNSView(_ view: Probe, context: Context) {
        view.requiresKeyWindow = requiresKeyWindow; view.changed = changed; view.publish()
    }
    final class Probe: NSView {
        var requiresKeyWindow: Bool
        var changed: (Bool) -> Void
        private var tokens: [NSObjectProtocol] = []
        private var last: Bool?
        init(requiresKeyWindow: Bool, changed: @escaping (Bool) -> Void) {
            self.requiresKeyWindow = requiresKeyWindow; self.changed = changed; super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver); tokens = []
            let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification, NSApplication.didBecomeActiveNotification,
                NSApplication.didResignActiveNotification]
            for name in names {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.publish() }
                })
            }
            publish()
        }
        func publish() {
            let value = window.map { NSApp.isActive && $0.isVisible && !$0.isMiniaturized
                && $0.occlusionState.contains(.visible) && (!requiresKeyWindow || $0.isKeyWindow) } ?? false
            guard value != last else { return }; last = value
            DispatchQueue.main.async { [weak self] in self?.changed(value) }
        }
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// The conversation's search and clear actions — plain buttons the window toolbar styles.
struct SidekickToolbarIconButton: View {
    let symbol: String
    var busy = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            if busy { ProgressView().controlSize(.small) }
            else { Image(systemName: symbol) }
        }
    }
}
