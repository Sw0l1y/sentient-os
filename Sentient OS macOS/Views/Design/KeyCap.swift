//
//  KeyCap.swift
//  Sentient OS macOS
//
//  A Mac keycap and the bottom-row modifier keys with the Double Tap key lit (SPEC-00 3.11). Users:
//  the Double Tap lesson popover, OnboardingDoubleTapKeyboard, the shortcut recorder sheet and the
//  Finish Setup Double Tap preview.
//

import SwiftUI
import AppKit

struct KeyCap: View {
    private let glyph: String
    private let caption: String?
    private let pressed: Bool
    private let highlighted: Bool
    private let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @Environment(\.pixelLength) private var pixelLength

    /// `highlighted` adds a 2 pt accent ring; `pressed` fills the cap with the accent and turns
    /// the glyph white.
    init(_ glyph: String, caption: String? = nil, pressed: Bool = false, highlighted: Bool = false, width: CGFloat = 56) {
        self.glyph = glyph
        self.caption = caption
        self.pressed = pressed
        self.highlighted = highlighted
        self.width = width
    }

    init(key: ShortcutKey, pressed: Bool = false, highlighted: Bool = false) {
        let face = KeyCap.face(for: key)
        self.init(face.glyph, caption: face.caption, pressed: pressed, highlighted: highlighted)
    }

    /// The glyph and caption printed on `key`'s cap.
    fileprivate static func face(for key: ShortcutKey) -> (glyph: String, caption: String) {
        switch key {
        case .rightCommand: return ("⌘", "right")
        case .leftCommand: return ("⌘", "left")
        case .rightOption: return ("⌥", "right")
        case .leftOption: return ("⌥", "left")
        case .rightControl: return ("⌃", "right")
        case .leftControl: return ("⌃", "left")
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
        VStack(spacing: 0) {
            Text(glyph)
                .font(.title2.weight(.medium))
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(pressed ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            }
        }
        .foregroundStyle(pressed ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        .frame(width: width, height: 44)
        .background(shape.fill(pressed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: pixelLength))
        .overlay {
            if highlighted {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(Motion.gated(Motion.quick, reduceMotion: motionOverride ?? systemReduced), value: pressed)
    }
}

/// A Mac keyboard's bottom-row modifiers (left ⌃ ⌥ ⌘, the space bar, right ⌘ ⌥, and right ⌃ only
/// when it is the key) with `key` highlighted. Narrower caps are used when the full row does not fit.
/// One accessibility element: "Keyboard. Double-tap Right ⌘."
struct KeyCapRow: View {
    private let key: ShortcutKey
    private let pressed: Bool

    init(highlighting key: ShortcutKey, pressed: Bool = false) {
        self.key = key
        self.pressed = pressed
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(capWidth: 56, spaceWidth: 160)
            row(capWidth: 44, spaceWidth: 112)
            row(capWidth: 36, spaceWidth: 72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keyboard. Double-tap \(key.label).")
    }

    private func row(capWidth: CGFloat, spaceWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            cap(.leftControl, width: capWidth)
            cap(.leftOption, width: capWidth)
            cap(.leftCommand, width: capWidth)
            KeyCap("", width: spaceWidth)
            cap(.rightCommand, width: capWidth)
            cap(.rightOption, width: capWidth)
            if key == .rightControl {
                cap(.rightControl, width: capWidth)
            }
        }
        .fixedSize()
    }

    private func cap(_ cap: ShortcutKey, width: CGFloat) -> some View {
        let face = KeyCap.face(for: cap)
        return KeyCap(face.glyph, caption: face.caption, pressed: pressed && cap == key,
                      highlighted: cap == key, width: width)
    }
}

#Preview("Key caps") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(spacing: Space.l) {
                HStack(spacing: Space.s) {
                    KeyCap(key: .rightCommand)
                    KeyCap(key: .rightOption, highlighted: true)
                    KeyCap(key: .leftControl, pressed: true, highlighted: true)
                }
                KeyCapRow(highlighting: .rightCommand)
                KeyCapRow(highlighting: .rightControl, pressed: true)
                    .frame(width: 292)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 1200)
}
