//  OnboardingDoubleTapView.swift
//  The Double Tap lesson as a Setup Assistant page (like macOS's Touch ID lesson): a tile and
//  title, one vignette with the real Mail or Messages icon, the user's own modifier keys, and a
//  footer whose primary lights only once the lesson succeeds. The real caret spiral still lands
//  in the reply field. DoubleTapDemoInput connects only this key window to the coordinator's
//  existing key monitor.
//  Doc: Documentation - Onboarding.md (this folder).

import AppKit
import SwiftUI

struct OnboardingDoubleTapView: View {
    /// nil lets previews run without creating AppState or starting global services.
    var coordinator: CommandCoordinator?
    let onContinue: () -> Void
    @State var demo = OnboardingDoubleTapDemo()
    @State var shortcutHint = OnboardingShortcutHint()
    @AppStorage("sidekick.hotkey") private var shortcutRaw = ShortcutPreferences.current.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    private var shortcut: ShortcutKey { ShortcutKey(rawValue: shortcutRaw) ?? .rightCommand }

    /// True when Reduce Motion, the Sidekick override or Low Power Mode asks for stillness
    /// (Motion.gated returns no animation). The demo's own choreography follows this flag.
    private var reduceMotion: Bool {
        Motion.gated(Motion.standard, reduceMotion: motionOverride ?? systemReduced) == nil
    }

    private var motion: Animation? { Motion.gated(Motion.standard, reduceMotion: reduceMotion) }

    /// The stage height fits the email card with its full drafted reply, so nothing below it
    /// moves when the reply lands or when Messages replaces Mail.
    private static let stageHeight: CGFloat = 280

    var body: some View {
        GeometryReader { geometry in
            SetupAssistantPage(tile: .setupDoubleTap, title: "Double tap your \(shortcut.label) key",
                               message: "Sentient drafts a reply where your cursor is.") {
                VStack(spacing: Space.xl) {
                    stage
                        .frame(height: Self.stageHeight, alignment: .top)

                    OnboardingDoubleTapKeyboard(pressed: demo.keyIsDown, inviting: demo.phase == .waiting,
                                                reduceMotion: reduceMotion, tapFeedback: demo.tapFeedback,
                                                key: shortcut,
                                                action: { demo.clicked() })
                        .disabled(demo.phase != .waiting)
                        .opacity(demo.controlsVisible ? (demo.phase == .complete ? 0.55 : 1) : 0)
                        .animation(motion, value: demo.phase)
                        .accessibilityHidden(!demo.controlsVisible)

                    instructionRow
                        .frame(height: 28)
                }
                .frame(maxWidth: .infinity)
            } footer: {
                footer
            }
            .overlayPreferenceValue(DoubleTapDemoCaretAnchor.self) { anchor in
                caretSwirl(anchor)
            }
            .onAppear {
                // Begin beyond the edges of the whole window. Only the orbit expands; the
                // comet strokes stay fine as the light gathers into the reply field.
                demo.start(reduceMotion: reduceMotion,
                           entranceRadius: Double(max(geometry.size.width, geometry.size.height)) * 0.78)
            }
        }
        .background {
            if let coordinator {
                DoubleTapDemoInput(coordinator: coordinator, onKeyChange: { demo.keyChanged($0) },
                                   onFocusLost: demo.resetGesture)
            }
        }
        .background(OnboardingWrongCommandMonitor(hint: shortcutHint,
            // Waiting is the input boundary. The instruction's opacity changes
            // in a separate animation transaction as that phase begins.
            enabled: shortcut == .rightCommand && demo.phase == .waiting,
            onMistake: demo.resetGesture))
        .onAppear { shortcutHint.activate() }
        .onChange(of: reduceMotion) { demo.setReduceMotion(reduceMotion) }
        .onChange(of: shortcutRaw) { demo.resetGesture(); shortcutHint.clear() }
        .onChange(of: demo.phase) {
            if demo.phase != .waiting { shortcutHint.clear() }
        }
        .onDisappear { demo.stop(); shortcutHint.deactivate() }
    }

    // MARK: Vignette stage

    /// Mail, then Messages, in one place. The email slides out toward the leading edge as it
    /// departs; Messages slides in from the trailing edge as it arrives. Both are driven by the
    /// demo's own departure and arrival values, which already honour Reduce Motion.
    private var stage: some View {
        ZStack(alignment: .top) {
            switch demo.sample {
            case .email:
                DoubleTapDemoEmailWindow(replied: demo.replyVisible, waiting: demo.phase == .waiting,
                                         reduceMotion: reduceMotion)
            case .message:
                DoubleTapDemoMessageWindow(replied: demo.replyVisible, waiting: demo.phase == .waiting,
                                           reduceMotion: reduceMotion)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .opacity(stageOpacity)
        .offset(x: stageOffset)
        .accessibilityHidden(!demo.windowVisible || demo.emailDeparture > 0)
    }

    private var stageOpacity: Double {
        guard demo.windowVisible else { return 0 }
        return Double(demo.sample == .email ? 1 - demo.emailDeparture : demo.messageArrival)
    }

    private var stageOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return demo.sample == .email ? -48 * demo.emailDeparture : 48 * (1 - demo.messageArrival)
    }

    // MARK: Instruction and completion

    /// One fixed row: the instruction while the lesson runs, the completion line once both
    /// samples are drafted. Neither adds height.
    private var instructionRow: some View {
        ZStack {
            OnboardingShortcutInstruction(prefix: "Tap ", key: shortcut, suffix: " twice, quickly.",
                                          hint: shortcutHint)
                .font(.title3)
                .foregroundStyle(.secondary)
                .opacity(demo.instructionVisible ? (demo.phase == .waiting ? 1 : 0.42) : 0)
                .accessibilityHidden(!demo.instructionVisible)

            Label {
                Text("Drafted from your entire personal context")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.title3)
            .opacity(demo.completionVisible ? 1 : 0)
            .accessibilityHidden(!demo.completionVisible)
        }
        .animation(motion, value: demo.instructionVisible)
        .animation(motion, value: demo.phase)
        .animation(motion, value: demo.completionVisible)
    }

    // MARK: Footer

    /// Built by hand with SetupAssistantFooter's metrics, because the primary's accessibility
    /// label ("Next: iMessage demo") differs from its visible title.
    private var footer: some View {
        let active = demo.nextVisible || demo.continueVisible
        return HStack(spacing: Space.m) {
            InfoPopoverButton(PrivacyCopy.doubleTapInfo, title: "About Double Tap")
            OnboardingGitHubButton()
            Spacer(minLength: Space.m)
            Button {
                if demo.nextVisible { demo.showMessages() } else { onContinue() }
            } label: {
                if demo.nextVisible {
                    HStack(spacing: Space.xs) {
                        Text("Next")
                        Image(systemName: "arrow.right")
                    }
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!active)
            .accessibilityLabel(demo.nextVisible ? "Next: iMessage demo" : "Continue")
            // Until a sample is drafted there is nothing to continue to; the lesson's keys are
            // the only action, as before.
            .accessibilityHidden(!active)
        }
    }

    // MARK: Caret swirl

    private func caretSwirl(_ anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { overlay in
            let caret = anchor.map { overlay[$0] }
                ?? CGRect(x: overlay.size.width / 2, y: overlay.size.height / 2, width: 1, height: 18)
            CaretSwirlView(model: demo.swirl)
                .frame(width: max(overlay.size.width, SwirlMath.canvasSide),
                       height: max(overlay.size.height, SwirlMath.canvasSide))
                .position(demo.spiralAtCaret
                          ? CGPoint(x: caret.midX, y: caret.midY)
                          : CGPoint(x: overlay.size.width / 2, y: overlay.size.height / 2))
                .opacity(demo.spiralVisible && !reduceMotion ? 1 : 0)
                .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
    }
}

/// Reuses the app's modifier monitor for the correct key. Wrong-side feedback has its
/// own instruction-scoped local monitor; neither path adds a permission prompt.
private struct DoubleTapDemoInput: NSViewRepresentable {
    let coordinator: CommandCoordinator
    let onKeyChange: (Bool) -> Void
    let onFocusLost: () -> Void

    func makeNSView(context: Context) -> InputView {
        InputView(coordinator: coordinator, onKeyChange: onKeyChange, onFocusLost: onFocusLost)
    }
    func updateNSView(_ view: InputView, context: Context) {}
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.detach() }

    final class InputView: NSView {
        let coordinator: CommandCoordinator
        let onKeyChange: (Bool) -> Void
        let onFocusLost: () -> Void
        private let sessionID = UUID()
        private var observer: NSObjectProtocol?

        init(coordinator: CommandCoordinator, onKeyChange: @escaping (Bool) -> Void, onFocusLost: @escaping () -> Void) {
            self.coordinator = coordinator
            self.onKeyChange = onKeyChange
            self.onFocusLost = onFocusLost
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            coordinator.armOnboardingDoubleTapDemo(id: sessionID, in: window, onKeyChange: onKeyChange)
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                               object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onFocusLost() }
            }
        }

        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            coordinator.disarmOnboardingDoubleTapDemo(id: sessionID)
            onFocusLost()
        }
    }
}

#if DEBUG
#Preview("Double Tap · waiting") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingDoubleTapView(onContinue: {}, demo: .preview())
                .frame(width: 900, height: 820)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Double Tap · email ready for Next") {
    OnboardingDoubleTapView(onContinue: {}, demo: .preview(completed: true))
        .frame(width: 1040, height: 800)
}

#Preview("Double Tap · Messages") {
    OnboardingDoubleTapView(onContinue: {}, demo: .preview(sample: .message))
        .frame(width: 1040, height: 800)
}

#Preview("Double Tap · Messages arriving") {
    OnboardingDoubleTapView(onContinue: {}, demo: .preview(sample: .message, arrival: 0.45))
        .frame(width: 1040, height: 800)
}

#Preview("Double Tap · complete, minimum window") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingDoubleTapView(onContinue: {}, demo: .preview(sample: .message, completed: true))
                .frame(width: 1040, height: 800)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
#endif
