// OnboardingDoubleTapKeyboard.swift
// The user's own modifier keys (KeyCapRow) with the configured Double Tap key lit, like the
// key illustration in System Settings → Keyboard. The row is one button: clicking it twice
// counts as a double tap. Two small dots under the row show the first tap and the confirmed
// pair. Nothing pulses or breathes while it waits; the lit key is the invitation.
// Doc: Documentation - Onboarding.md (this folder).

import SwiftUI

struct OnboardingDoubleTapKeyboard: View {
    let pressed: Bool
    let inviting: Bool
    let reduceMotion: Bool
    var tapFeedback: OnboardingDoubleTapDemo.TapFeedback? = nil
    var key: ShortcutKey = .rightCommand
    let action: () -> Void

    var body: some View {
        VStack(spacing: Space.s) {
            Button(action: action) {
                KeyCapRow(highlighting: key, pressed: pressed || tapLit)
            }
            .buttonStyle(.plain)
            // A one-shot state change when the waiting beat begins, never a loop (SPEC-00 1.7).
            .opacity(inviting ? 1 : 0.8)
            .animation(Motion.gated(Motion.quick, reduceMotion: reduceMotion), value: inviting)
            .accessibilityLabel("\(key.spokenLabel) key")
            .accessibilityHint("Double-click this key, or double tap your \(key.spokenLabel) key, to fill the sample reply.")
            .accessibilityValue(tapFeedback.map { $0.confirmed ? "" : "One tap. Tap again." } ?? "")

            tapDots
        }
    }

    /// The key stays lit for the feedback's duration. The demo clears `tapFeedback` exactly when
    /// that duration ends, so its presence is the lit state, with no per-frame timer.
    private var tapLit: Bool { tapFeedback != nil }

    /// First tap seen, then the confirmed pair. The button's value carries the same state.
    private var tapDots: some View {
        HStack(spacing: 6) {
            dot(filled: tapFeedback != nil)
            dot(filled: tapFeedback?.confirmed == true)
        }
        .frame(height: 6)
        .animation(Motion.gated(Motion.quick, reduceMotion: reduceMotion), value: tapFeedback)
        .accessibilityHidden(true)
    }

    private func dot(filled: Bool) -> some View {
        Circle()
            .fill(filled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            .frame(width: 6, height: 6)
    }
}

#if DEBUG
#Preview("Double Tap keys") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(spacing: Space.xl) {
                OnboardingDoubleTapKeyboard(pressed: false, inviting: true, reduceMotion: false, action: {})
                OnboardingDoubleTapKeyboard(pressed: true, inviting: true, reduceMotion: false,
                                            tapFeedback: .init(began: .now, confirmed: false, duration: 1),
                                            key: .leftOption, action: {})
                OnboardingDoubleTapKeyboard(pressed: false, inviting: false, reduceMotion: true,
                                            key: .rightControl, action: {})
            }
            .padding(Space.xl)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
}
#endif
