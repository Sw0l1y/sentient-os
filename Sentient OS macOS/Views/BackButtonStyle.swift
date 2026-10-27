// Home and Back navigation buttons: the shared glass capsule (GlassButtonStyle) with the title
// always shown, so navigation reads exactly like every other control.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI

struct BackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonStyle().makeBody(configuration: configuration)
            .labelStyle(.titleAndIcon)
    }
}

#Preview("Back navigation") {
    HStack(spacing: 16) {
        Button {} label: { Label("Home", systemImage: "arrow.left") }
        Button {} label: { Label("Back", systemImage: "chevron.left") }
        Button {} label: { Label("Back", systemImage: "chevron.left") }
            .disabled(true)
    }
    .buttonStyle(BackButtonStyle())
    .padding(24)
    .background(Color(white: 0.065))
    .preferredColorScheme(.dark)
}
