// First launch: the existing film and lessons, then the frontier model connection.
// Home opens immediately afterward. Personal context is a separate resumable window.
// Doc: Documentation - Onboarding.md
//
// A Setup Assistant flow (SPEC-D6 S1): no backdrop of its own (the window background shows), no
// floating Back pill and no corner chrome. Each step owns its footer: Choose Your AI carries Back,
// the privacy footnote, the gift link and the GitHub mark beside Continue; the film places the
// GitHub mark itself.

import SwiftUI
import AppKit

struct OnboardingView: View {
    let onFinished: () -> Void

    /// For the DEBUG skip handle only — the quiet flag flip, no finale.
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    /// Resume the introduction or frontier-model connection after an ordinary relaunch.
    @AppStorage("onboarding.step") private var step = 0

    @State private var isPresentingInviteGift = false
    #if DEBUG
    @State private var introFilm: FilmDriver?
    #endif

    /// Keep setup visible; the analysis owner separately holds system sleep while it works.
    @State private var awake = DisplayAwake()

    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }

    var body: some View {
        ZStack {
            switch step {
            case 0:
                // Step 1 is the website's film in a webview — it plays to the morning-home
                // rest and offers its own Continue (OnboardingFilmView owns the choreography).
                #if DEBUG
                OnboardingFilmView(onContinue: advance, onWebIntroChange: { introFilm = $0 })
                    .transition(.opacity)
                #else
                OnboardingFilmView(onContinue: advance).transition(.opacity)
                #endif
            default:
                OnboardingFrontierModelView(onBack: goBack, isPresentingGift: $isPresentingInviteGift,
                                            onContinue: onFinished)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The introduction ends at Home; the display can then sleep normally.
        .onAppear { awake.begin(reason: "Onboarding — keeping the screen on") }
        .onDisappear { awake.end() }
        // No right-clicks anywhere in onboarding — the film's webview would offer a browser
        // context menu (Reload…), and no onboarding surface has a legitimate right-click.
        // Window-scoped, gone with this view.
        .background(RightClickBlocker())
        // No GitHub overlay here: the film (bottom-right), its fallback page, the Double Tap
        // lesson and Choose Your AI each place OnboardingGitHubButton() in their own footer.
        #if DEBUG
        // Developer shortcuts, top-center under the titlebar: every bottom corner belongs to a
        // page footer.
        .overlay(alignment: .top) {
            devRow.padding(.top, 40)
        }
        #endif
        .disabled(isPresentingInviteGift)
        .accessibilityHidden(isPresentingInviteGift)
    }

    #if DEBUG
    private var devRow: some View {
        HStack(spacing: Space.s) {
            if step == 0, let introFilm {
                OnboardingDevButton(title: introFilm.introSpedUp ? "Intro at 50×" : "Speed Up Intro",
                                    icon: "forward.fill", action: introFilm.speedUpIntro)
                    .disabled(introFilm.introSpedUp)
                    .help("Play the remaining web intro at 50× speed.")
            }
            OnboardingDevButton(title: "Skip to Home", icon: "forward.end") {
                withAnimation(Motion.gated(Motion.standard, reduceMotion: reduceMotion)) {
                    appState.hasCompletedOnboarding = true
                }
            }
        }
    }
    #endif

    private func advance() {
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reduceMotion)) { step += 1 }
    }

    private func goBack() {
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reduceMotion)) { step = 0 }
    }
}

#if DEBUG
/// The developer controls share one row and are entirely absent from Release.
private struct OnboardingDevButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
#endif

/// The shared primary for onboarding-era callers (LoginLinkButton, the analysis and download
/// steps, the permission pages): the system prominent button at large size, on Return.
/// `glow` is kept for source compatibility and ignored.
struct OnboardingNextButton: View {
    let title: String
    var enabled: Bool = true
    var glow: Double = 0
    var minimumLabelWidth: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(minWidth: minimumLabelWidth)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!enabled)
    }
}

/// A standard Back button. No onboarding step uses it after the remake (Back lives in the
/// Choose Your AI footer); kept for source compatibility.
struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.left")
        }
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
    }
}

/// The GitHub mark: a 16 pt template image, borderless, that opens the public repo. The film
/// places it at the bottom-right; the Setup Assistant pages put it at the end of their footer's
/// leading group.
struct OnboardingGitHubButton: View {
    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: "https://github.com/Sentient-OS-Labs/sentient-os")!)
        } label: {
            Image("GitHubMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("View on GitHub")
        .accessibilityLabel("Sentient OS on GitHub")
    }
}

/// Swallows right-clicks in the window hosting onboarding, for onboarding's whole lifetime.
/// The film's webview serves WebKit's context menu (Reload Page restarts the film), and no
/// onboarding screen has a legitimate right-click — so the event is eaten at the door.
/// Window-scoped on purpose: other windows (dev tools, the notch) keep theirs. The local
/// monitor installs on view-did-move-to-window (post-launch — never during app init, the
/// notch lesson) and dies with the view. Ctrl-click menus are covered separately by
/// PassiveWebView's willOpenMenu override.
private struct RightClickBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> Blocker { Blocker() }
    func updateNSView(_ view: Blocker, context: Context) {}

    final class Blocker: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.rightMouseDown, .rightMouseUp]) { [weak self] event in
                event.window === self?.window ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

/// The trust line, as small print. The caller places it; it adds no padding of its own.
struct OnboardingTrustFooter: View {
    var body: some View {
        Text(PrivacyCopy.trustRibbon)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

#Preview("Onboarding") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingView(onFinished: {})
                .frame(width: 1100, height: 820)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
