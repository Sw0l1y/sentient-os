//
//  GlowProgressBar.swift
//  Sentient OS macOS
//
//  The analysis / model-download progress bar — the system linear progress indicator, shared by
//  ProcessingView and onboarding's downloading-model screen. One bar, one place.
//

import SwiftUI

struct GlowProgressBar: View {
    var value: Double   // 0...1

    var body: some View {
        ProgressView(value: min(max(value, 0), 1))
            .progressViewStyle(.linear)
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
