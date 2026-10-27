//
//  GlowProgressBar.swift
//  Sentient OS macOS
//
//  The analysis / model-download progress bar: an accent capsule fill with a soft bloom at the
//  leading tip. Shared by ProcessingView and onboarding's downloading-model screen. One bar, one
//  place.
//
//  It used to scroll a six-color rainbow through four blurred copies of itself, driven by an
//  unthrottled TimelineView that wrote @State every frame — a full body re-render at display rate
//  for as long as the bar was on screen. It is now static between progress updates.
//

import SwiftUI

struct GlowProgressBar: View {
    var value: Double   // 0...1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fill = value > 0 ? max(min(value, 1) * w, 14) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                if fill > 0 {
                    // Tip bloom: a short accent capsule at the leading edge, blurred once.
                    Capsule().fill(Theme.accent)
                        .frame(width: min(fill, 60), height: 9)
                        .offset(x: fill - min(fill, 60))
                        .blur(radius: 9)
                        .opacity(0.8)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.accentRamp[3], Theme.accentRamp[1]],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: fill, height: 9)
                }
            }
        }
        .frame(height: 9)
        .animation(.easeInOut(duration: 0.35), value: value)
    }
}

#Preview("Glow progress bar") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 30) {
            GlowProgressBar(value: 0.08)
            GlowProgressBar(value: 0.55)
            GlowProgressBar(value: 0.92)
        }
        .frame(width: 380)
        .padding(60)
    }
    .frame(width: 560, height: 300)
    .preferredColorScheme(.dark)
}
