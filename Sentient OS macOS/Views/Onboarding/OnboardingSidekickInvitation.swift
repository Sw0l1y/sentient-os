// The film's interactive pause: a coach-mark callout under the notch and a thin accent leader
// line to the real camera cutout. The leader line is a passive window, never a second click
// target. (SPEC-D6 S5, S6: a material bubble with an up arrow and the real keycap.)
import AppKit
import SwiftUI

struct OnboardingSidekickInvitation: View {
    let onOpen: () -> Void
    @Environment(\.onboardingCanvasScale) private var canvasScale
    @AppStorage(ShortcutPreferences.storageKey) private var shortcut = ShortcutKey.rightCommand.rawValue
    @State private var pointsToNotch = OnboardingNotchPointer.hasPhysicalTarget
    @State private var horizontalOffset: CGFloat = 0
    @State private var topInset: CGFloat = 12
    @State var shortcutHint = OnboardingShortcutHint()

    private var key: ShortcutKey { ShortcutKey(rawValue: shortcut) ?? .rightCommand }
    // A mistaken key press expresses a preference for the keyboard door. Keep
    // that instruction visible afterward, while the highlight itself lasts one second.
    private var showsKeyboard: Bool { !pointsToNotch || shortcutHint.pulseCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                callout
            }
            .buttonStyle(.plain)
            .background(OnboardingNotchPointer(scale: canvasScale, prefersKeyboard: shortcutHint.pulseCount > 0) { target, offset, inset in
                pointsToNotch = target; horizontalOffset = offset; topInset = inset
            })
            .offset(x: horizontalOffset)
            .accessibilityLabel(showsKeyboard ? "Press \(key.spokenLabel)" : "Click your notch")
            .accessibilityHint(showsKeyboard ? "Press the \(key.spokenLabel) key once, or click this button."
                               : "Open Sidekick from the top of your screen.")
            .accessibilityIdentifier("onboarding.sidekick.instruction")
            Spacer(minLength: 0)
        }
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingWrongCommandMonitor(hint: shortcutHint, enabled: key == .rightCommand))
        .onAppear { shortcutHint.activate() }
        .onChange(of: shortcut) { shortcutHint.clear() }
        .onDisappear { shortcutHint.deactivate() }
    }

    /// The coach mark: an up arrow toward the notch, then the instruction (with the real keycap
    /// when the keyboard is the door), on popover material.
    private var callout: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
        return VStack(spacing: Space.s) {
            Image(systemName: "arrow.up")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if showsKeyboard {
                    KeyCap(key: key, highlighted: true)
                    OnboardingShortcutInstruction(prefix: "Press ", key: key, hint: shortcutHint)
                } else {
                    Text("Click your notch")
                }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background { PopoverMaterial() }
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor)))
        .contentShape(shape)
    }
}

/// The popover's own material behind the coach mark. SwiftUI has no `.popover` Material and
/// `background(_:in:)` takes only a ShapeStyle, so the effect view rounds its own layer.
private struct PopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = Radius.group
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A vertical leader line joins the callout to the hardware, even when onboarding is windowed.
/// It ignores every mouse event and cannot become key, so the actual notch owns the click.
struct OnboardingNotchPointer: NSViewRepresentable {
    var scale: CGFloat = 1
    var prefersKeyboard = false
    let onLayout: (Bool, CGFloat, CGFloat) -> Void

    static var hasPhysicalTarget: Bool {
        NSScreen.screens.count == 1 && NotchWindowController.builtInNotchScreen() != nil
            && NotchPreferences.clickEnabled()
    }

    static let tipGap: CGFloat = 10
    static let buttonGap: CGFloat = 12
    static let minimumStem: CGFloat = 18

    static func panelFrame(screen: CGRect, notchHeight: CGFloat, button: CGRect) -> CGRect? {
        let tip = screen.maxY - notchHeight - tipGap
        let tail = button.maxY + buttonGap
        guard tip - tail >= minimumStem - 0.5 else { return nil }
        return CGRect(x: screen.midX - 16, y: tail - 8, width: 32, height: tip - tail + 16)
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.onLayout = onLayout
        nsView.renderScale = scale
        nsView.prefersKeyboard = prefersKeyboard
        nsView.scheduleRefresh()
    }
    static func dismantleNSView(_ nsView: Probe, coordinator: ()) { nsView.stop() }

    final class Probe: NSView {
        var onLayout: ((Bool, CGFloat, CGFloat) -> Void)?
        var renderScale: CGFloat = 1
        var prefersKeyboard = false
        override var isFlipped: Bool { true }
        private(set) var pointer: NSPanel?
        private var observers: [NSObjectProtocol] = []
        private var lastLayout: (target: Bool, offset: CGFloat, inset: CGFloat)?
        private var refreshPending = false
        private var alignmentTask: Task<Void, Never>?

        override func layout() {
            super.layout()
            scheduleRefresh()
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            super.setFrameOrigin(newOrigin)
            scheduleRefresh()
        }

        func scheduleRefresh() {
            guard !stopped, !refreshPending else { return }
            refreshPending = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshPending = false
                self.refresh()
            }
        }
        private var stopped = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard window != nil, !stopped else { pointer?.orderOut(nil); return }
            let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification,
                NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                NSApplication.didChangeScreenParametersNotification, UserDefaults.didChangeNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    // Outside SwiftUI's update pass; stale callbacks are harmless after teardown.
                    Task { @MainActor [weak self] in self?.refresh() }
                })
            }
            Task { @MainActor [weak self] in self?.refresh() }
        }

        func refresh() {
            guard !stopped else { return }
            guard let window, bounds.width > 0 else { return }
            let screen = NotchWindowController.builtInNotchScreen()
            let root = window.convertToScreen(window.contentLayoutRect)
            let button = window.convertToScreen(convert(bounds, to: nil))
            let offset = (screen?.frame.midX ?? root.midX) - root.midX
            let fits = abs(offset) + button.width / 2 + 24 <= root.width / 2
            let target = !prefersKeyboard && OnboardingNotchPointer.hasPhysicalTarget && window.screen == screen && fits
            let tip = (screen?.frame.maxY ?? 0) - (screen?.notchSize?.height ?? 0) - OnboardingNotchPointer.tipGap
            let inset = target ? max(12, (root.maxY - tip + OnboardingNotchPointer.minimumStem + OnboardingNotchPointer.buttonGap) / renderScale) : 12
            let proposedOffset = target ? offset / renderScale : 0
            if lastLayout?.target != target || abs((lastLayout?.offset ?? .infinity) - proposedOffset) > 0.25
                || abs((lastLayout?.inset ?? .infinity) - inset) > 0.25 {
                lastLayout = (target, proposedOffset, inset)
                onLayout?(target, proposedOffset, inset)
                // SwiftUI applies the CTA offset after AppKit's move notification.
                // Read the settled placement once, rather than keeping a polling timer.
                alignmentTask?.cancel()
                alignmentTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    self?.refresh()
                }
            }
            guard target, window.isVisible, window.isKeyWindow, !window.isMiniaturized,
                  NSApp.isActive, let screen, let notch = screen.notchSize,
                  abs(button.midX - screen.frame.midX) < 1,
                  let frame = OnboardingNotchPointer.panelFrame(screen: screen.frame, notchHeight: notch.height, button: button) else {
                pointer?.orderOut(nil)
                return
            }
            if pointer == nil {
                let panel = PointerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
                panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
                panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = true
                panel.isReleasedWhenClosed = false
                panel.level = .statusBar
                panel.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllApplications, .ignoresCycle]
                panel.setAccessibilityElement(false)
                panel.title = "Sidekick onboarding notch pointer"
                // Follows the app's appearance: the leader line is the accent colour.
                panel.contentView = NSHostingView(rootView: NotchPointerDrawing())
                pointer = panel
            }
            pointer?.setFrame(frame, display: true)
            if pointer?.isVisible != true { pointer?.orderFrontRegardless() }
        }

        func stop() {
            stopped = true
            alignmentTask?.cancel(); alignmentTask = nil
            observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
            pointer?.orderOut(nil); pointer?.close(); pointer = nil
            onLayout = nil
        }
    }

    private final class PointerPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}

/// The coach-mark leader line: a 3 pt accent stem with an arrowhead at the notch. No shadow.
private struct NotchPointerDrawing: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            let center = geometry.size.width / 2
            Path { path in
                path.move(to: CGPoint(x: center, y: geometry.size.height - 8))
                path.addLine(to: CGPoint(x: center, y: 8))
            }
            .trim(from: 0, to: appeared ? 1 : 0)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { path in
                path.move(to: CGPoint(x: center - 7, y: 18))
                path.addLine(to: CGPoint(x: center, y: 8))
                path.addLine(to: CGPoint(x: center + 7, y: 18))
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .opacity(appeared ? 1 : 0)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onAppear {
            withAnimation(Motion.gated(Motion.standard, reduceMotion: motionOverride ?? systemReduceMotion)) {
                appeared = true
            }
        }
    }
}
