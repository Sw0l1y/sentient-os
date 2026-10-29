// Home's Double Tap toolbar item with its lesson popover, and the Ask bar's one caption line
// (the notch hint, or "Private by design."). The ready moment waits for a visible, key Home,
// never takes focus, and acknowledges only a completed viewing or a click.
// Doc: Documentation - Views - Home, Processing & Shared UI.md
import SwiftUI
import AppKit

/// The Double Tap toolbar item. A click opens a Control Center-style popover: a tile header, the
/// user's own keyboard row with the configured key lit, the state and its one action.
struct HomeDoubleTapButton: View {
    let active: Bool
    @Binding var presented: Bool
    var needsPersonalSetup = false
    var onFinishSetup: () -> Void = {}
    var onViewAnalysis: () -> Void
    @AppStorage(ShortcutPreferences.storageKey) private var shortcutRaw = ShortcutKey.rightCommand.rawValue
    @AppStorage(DoubleTap.enabledKey) private var enabled = true
    @AppStorage(ProcessingPlan.initialCompletedKey) private var completedAt = 0.0
    @AppStorage(SidekickDiscovery.readyHintSeenKey) private var seenAt = 0.0
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var homeIsKey = false
    @State private var noticeVisible = false
    @State private var highlight = 0.0
    /// The lesson's key press, driven by the replay loop while the popover shows.
    @State private var pressed = false

    private var key: ShortcutKey { ShortcutKey(rawValue: shortcutRaw) ?? .rightCommand }
    private var reduced: Bool { (motionOverride ?? systemReduced) || lowPower }
    private var ready: Bool { completedAt > 0 && enabled }
    private var lessonAnimating: Bool { active && presented && !reduced }
    private var offerNotice: Bool {
        active && homeIsKey && ready && !presented
            && SidekickDiscovery.readyHintPending(completedAt: completedAt, seenAt: seenAt)
    }
    private struct NoticeIdentity: Equatable {
        let eligible: Bool
        let completion: Double
    }

    var body: some View {
        Button {
            if ready { seenAt = completedAt }
            presented.toggle()
        } label: {
            Label {
                Text("Double Tap")
            } icon: {
                Image(systemName: ready ? "hand.tap.fill" : "hand.tap")
                    .foregroundStyle(highlight > 0 || presented ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
        }
        .accessibilityIdentifier("navigation.doubleTap")
        .accessibilityLabel("Double Tap")
        .accessibilityValue(enabled ? (completedAt > 0 ? "Ready" : "Ready after your first analysis") : "Turned off")
        .help(noticeVisible ? "Double Tap is ready. Draft a reply with two taps of \(key.label)."
              : ready ? "Draft a reply with two taps of \(key.label)."
              : (enabled ? "Double Tap unlocks after your first analysis." : "Double Tap is turned off."))
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            lesson
                .frame(width: PageMetrics.popover)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("doubleTap.lesson")
        }
        .background(SidekickWindowPresence(requiresKeyWindow: true) { homeIsKey = $0 }
            .allowsHitTesting(false).accessibilityHidden(true))
        .task(id: NoticeIdentity(eligible: offerNotice, completion: completedAt)) {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LAB_SIDEKICK_STAGE"] == "ui-discovery" {
                Log("Discovery hint: eligible=\(offerNotice), active=\(active), presented=\(presented)")
            }
            #endif
            guard offerNotice else { noticeVisible = false; highlight = 0; return }
            let completion = completedAt
            do {
                // Let Home's own entrance settle before drawing attention to a new capability.
                try await Task.sleep(for: .milliseconds(700))
                try Task.checkCancellation()
                withAnimation(Motion.gated(Motion.standard, reduceMotion: reduced)) {
                    noticeVisible = true; highlight = 1
                }
                NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                    userInfo: [.announcement: "Double Tap is ready. Tap \(key.spokenLabel) twice in a reply box.",
                               .priority: NSAccessibilityPriorityLevel.low.rawValue])
                try await Task.sleep(for: .milliseconds(900))
                withAnimation(Motion.gated(.easeOut(duration: 1.2), reduceMotion: reduced)) { highlight = 0.35 }
                try await Task.sleep(for: .seconds(5))
                try Task.checkCancellation()
                // Hiding Home cancels this task before acknowledgement, so the hint can wait.
                seenAt = completion
                #if DEBUG
                if ProcessInfo.processInfo.environment["LAB_SIDEKICK_STAGE"] == "ui-discovery" { Log("Discovery hint acknowledged") }
                #endif
                withAnimation(Motion.gated(Motion.standard, reduceMotion: reduced)) { noticeVisible = false; highlight = 0 }
            } catch {
                #if DEBUG
                if ProcessInfo.processInfo.environment["LAB_SIDEKICK_STAGE"] == "ui-discovery" { Log("Discovery hint interrupted") }
                #endif
                noticeVisible = false; highlight = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private var lesson: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            TileLabel("Double Tap", subtitle: "Replies in your voice.", tile: .featureDoubleTap, size: 30)

            KeyCapRow(highlighting: key, pressed: pressed)
                .frame(maxWidth: .infinity)

            if !enabled {
                Text("Double Tap is turned off.")
                    .font(.body)
                Button("Turn On Double Tap") {
                    enabled = true
                    if completedAt > 0 { seenAt = completedAt }
                }
                .buttonStyle(.borderedProminent)
            } else if completedAt <= 0 {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Ready after your first analysis.")
                        .font(.headline)
                        .accessibilityIdentifier("doubleTap.waiting")
                    Text(needsPersonalSetup
                         ? "Finish setup and connect three sources to give Double Tap your personal context. After your first analysis, click a reply box and tap \(key.label) twice."
                         : "Your first analysis gives Double Tap your personal context. Then click a reply box and tap \(key.label) twice.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button(needsPersonalSetup ? "Finish Setup…" : "View analysis") {
                    presented = false
                    if needsPersonalSetup { onFinishSetup() } else { onViewAnalysis() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(needsPersonalSetup ? "doubleTap.finishSetup" : "doubleTap.viewAnalysis")
            } else {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Click a reply box, then tap **\(key.label) twice**.")
                        .font(.body)
                        .accessibilityIdentifier("doubleTap.instructions")
                    Text("Your draft appears right where you’re typing. Review it, then send.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text("One tap opens Sidekick.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Space.l)
        .task(id: lessonAnimating) {
            // Two presses of 120 ms with 100 ms gaps, then a 2 s pause. KeyCap animates the press
            // itself through Motion.gated; under Reduce Motion or Low Power the key stays lit and still.
            guard lessonAnimating else { pressed = false; return }
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(600))
                    for _ in 1...2 {
                        pressed = true
                        try await Task.sleep(for: .milliseconds(120))
                        pressed = false
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    try await Task.sleep(for: .seconds(2))
                }
            } catch { pressed = false }
        }
    }
}

/// The Ask bar's caption: one secondary line under the field, like Siri's "Type to Siri".
/// The notch hint while it is still being learned (and allowed here), else "Private by design.".
struct HomeNotchHint: View {
    let coordinator: CommandCoordinator
    var allowsHint = true
    @AppStorage(ShortcutPreferences.storageKey) private var shortcutRaw = ShortcutKey.rightCommand.rawValue
    @AppStorage(NotchPreferences.clickEnabledKey) private var clickable = true
    @AppStorage(SidekickDiscovery.notchUsesKey) private var uses = 0
    private var key: ShortcutKey { ShortcutKey(rawValue: shortcutRaw) ?? .rightCommand }

    init(coordinator: CommandCoordinator, allowsHint: Bool = true) {
        self.coordinator = coordinator
        self.allowsHint = allowsHint
    }

    private var showsHint: Bool {
        allowsHint && uses < SidekickDiscovery.notchLearningUses
            && !coordinator.run.isRunning && coordinator.phase == .hidden
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            if showsHint {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .accessibilityHidden(true)
                Text("Press \(key.label) to ask from anywhere.")
                Button("Try It") { coordinator.openNotchFromHome() }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("sidekick.notchHint")
                    .accessibilityLabel("Open Sidekick in the notch")
                    .help(clickable ? "Sidekick is in your notch, too. Click it or press \(key.label) from any app."
                          : "Press \(key.label) to open Sidekick from any app.")
            } else {
                Label("Private by design.", systemImage: "lock.fill")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#if DEBUG
#Preview("Notch caption") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(spacing: Space.m) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                    Text("Press Right ⌘ to ask from anywhere.")
                    Button("Try It") {}.buttonStyle(.link)
                }
                Label("Private by design.", systemImage: "lock.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(Space.xl)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 720)
}
#endif
