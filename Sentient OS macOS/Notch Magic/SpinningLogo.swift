//
//  SpinningLogo.swift
//  Sentient OS macOS
//
//  The notch's identity mark: the Sentient BrandMark (a ring with a gap and a dot sitting in it),
//  filled with one tint. Motion has one meaning, the way a Dynamic Island leading glyph animates only
//  while its activity is live: at rest (`fast == false`) the mark stands still; while Sentient is
//  working (`fast == true`) the whole mark turns once every 1.6 s, so the gap and the dot circle the ring.
//  `paused` freezes it in place (hidden notch, Reduce Motion, Low Power Mode).
//

import SwiftUI

struct SpinningLogo: View {
    var size: CGFloat
    var fast: Bool
    var paused: Bool
    var tint: Color

    init(size: CGFloat = 20, fast: Bool = false, paused: Bool = false, tint: Color = NotchTone.accent) {
        self.size = size
        self.fast = fast
        self.paused = paused
        self.tint = tint
    }

    // Anchor (angle + wall-time) so a pause freezes the mark instead of jumping it.
    @State private var anchorAngle: Double = 0
    @State private var anchorTime: Double = Date().timeIntervalSinceReferenceDate

    private static let period: Double = 1.6   // seconds per turn while working

    var body: some View {
        // The clock runs only while the mark actually turns; a resting or paused mark costs no frames.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused || !fast)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let angle = fast ? anchorAngle + (paused ? 0 : (t - anchorTime) / Self.period * 360) : 0
            BrandMark()
                .fill(tint)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(angle))
        }
        // The turn is wall-clock driven: never let a parent's animation (the notch morph) interpolate it.
        .transaction { $0.animation = nil }
        // Rest ⇄ work always starts from the resting angle.
        .onChange(of: fast) { _, _ in
            anchorAngle = 0
            anchorTime = Date().timeIntervalSinceReferenceDate
        }
        // Re-base on pause so it freezes where it is and resumes from there.
        .onChange(of: paused) { wasPaused, _ in
            let t = Date().timeIntervalSinceReferenceDate
            if fast && !wasPaused { anchorAngle += (t - anchorTime) / Self.period * 360 }
            anchorTime = t
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("mark") {
    ZStack {
        Color.black
        HStack(spacing: 30) {
            SpinningLogo(size: 17, fast: false)
            SpinningLogo(size: 17, fast: true)
            SpinningLogo(size: 22, fast: true, paused: true)
        }
    }
    .frame(width: 200, height: 120)
}
