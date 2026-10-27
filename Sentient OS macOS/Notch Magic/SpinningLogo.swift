//
//  SpinningLogo.swift
//  Sentient OS macOS
//
//  The 2D Sentient mark for the notch (matches the app icon): a THICK ring of the accent's shades
//  (Theme.accentRamp) rendered SHARP so the colour reads boldly, over a
//  soft additive bloom, with a thin white ring for shape and a white planet-dot. The spectrum slowly
//  spins, FASTER when Sentient is acting (`fast`); the spin is anchored on every speed change so the
//  colours never jump. Tiny + cheap — the heavy 3D Orb is too much at this size.
//

import SwiftUI

struct SpinningLogo: View {
    var size: CGFloat = 20
    var fast: Bool = false            // running → quicker spin
    var paused = false               // retained hidden surfaces do not keep a display clock alive

    // Anchor (angle + wall-time) so a period change re-bases the spin instead of jumping it.
    @State private var anchorAngle: Double = 0
    @State private var anchorTime: Double = Date().timeIntervalSinceReferenceDate

    private static func period(fast: Bool) -> Double { fast ? 2 : 13 }   // seconds / revolution (2s = the fast "processing" spin)

    /// The ring's palette: the accent's shades (Theme.accentRamp), so the mark matches the rest of
    /// the app's single-accent language instead of the old rainbow spectrum.
    private static var bandStops: [Color] { Theme.accentRamp }

    var body: some View {
        TimelineView(.animation(minimumInterval: fast ? 1.0 / 60.0 : 1.0 / 30.0, paused: paused)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let angle = anchorAngle + (paused ? 0 : (t - anchorTime) / Self.period(fast: fast) * 360)
            ZStack {
                // The colored ring is rasterized ONCE (drawingGroup) and spun as a compositor
                // transform — re-shading a conic gradient every frame ran on the CPU.
                colorRing.rotationEffect(.degrees(angle))
                // 3. A thin white ring — just for the shape (kept extra-fine; floor governs at notch size).
                Circle().stroke(.white, lineWidth: max(0.75, size * 0.028)).blur(radius: size * 0.005)
                // 4. The white planet — with a tiny additive glow so it reads as lit, not flat.
                Circle().fill(.white).frame(width: size * 0.50, height: size * 0.50)
                    .blur(radius: size * 0.07).blendMode(.plusLighter).opacity(0.6)
                Circle().fill(.white).frame(width: size * 0.36, height: size * 0.36)
            }
            .frame(width: size, height: size)
        }
        // The spin is wall-clock driven — never let a parent's animation (the notch morph) interpolate
        // the gradient angle, or a speed change reverse-spins it for the morph's duration.
        .transaction { $0.animation = nil }
        .onChange(of: fast) { oldFast, _ in
            let t = Date().timeIntervalSinceReferenceDate
            if !paused { anchorAngle += (t - anchorTime) / Self.period(fast: oldFast) * 360 }
            anchorTime = t
        }
        .onChange(of: paused) { wasPaused, _ in
            let t = Date().timeIntervalSinceReferenceDate
            if !wasPaused { anchorAngle += (t - anchorTime) / Self.period(fast: fast) * 360 }
            anchorTime = t
        }
        .allowsHitTesting(false)
    }

    /// 1. Soft colored bloom (the neon bleed) + 2. the thick band, both from one fixed-angle
    /// gradient. Padded so the bloom's tail fits inside the raster bounds.
    private var colorRing: some View {
        let spectrum = AngularGradient(colors: Self.bandStops, center: .center)
        return ZStack {
            Circle().stroke(spectrum, lineWidth: size * 0.22).blur(radius: size * 0.14).blendMode(.plusLighter)
            Circle().stroke(spectrum, lineWidth: size * 0.17).blur(radius: size * 0.008)
        }
        .frame(width: size, height: size)
        .padding(size * 0.4)
        .drawingGroup()
        .padding(-size * 0.4)
    }
}

#Preview("logo") {
    ZStack {
        Color.black
        HStack(spacing: 30) {
            SpinningLogo(size: 22, fast: false)
            SpinningLogo(size: 22, fast: true)
        }
    }
    .frame(width: 200, height: 120)
}
