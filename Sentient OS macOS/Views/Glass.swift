//
//  Glass.swift
//  Sentient OS macOS
//
//  The one control language: Liquid Glass capsules on macOS 26+, a quiet material capsule on
//  older systems. Every app-wide button style routes through GlassButtonStyle so navigation,
//  toolbar, Settings and CTA buttons share one shape, height ladder, press feedback and accent.
//  Keep glass on controls (the navigation layer), not on content cards or long chip lists —
//  each glass element costs GPU time, and the on-device model shares that GPU overnight.
//

import SwiftUI

/// Capsule glass button. `prominent` tints the glass with the accent (the one primary action per
/// surface); `tint` colors a regular button's label (e.g. a destructive red) without filling it.
struct GlassButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, prominent: prominent, tint: tint)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var sentientGlass: GlassButtonStyle { GlassButtonStyle() }
    static var sentientGlassProminent: GlassButtonStyle { GlassButtonStyle(prominent: true) }
}

/// Heights follow the system control-size ladder so a `.controlSize(.small)` caller still works.
private struct GlassMetrics {
    let font: CGFloat, hPad: CGFloat, height: CGFloat
    init(_ size: ControlSize) {
        switch size {
        case .mini, .small: (font, hPad, height) = (12, 11, 28)
        case .large, .extraLarge: (font, hPad, height) = (15, 22, 44)
        default: (font, hPad, height) = (13.5, 14, 34)
        }
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let tint: Color?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        let m = GlassMetrics(controlSize)
        configuration.label
            .font(.system(size: m.font, weight: .medium))
            .foregroundStyle(prominent ? Color.white : (tint ?? Color.white.opacity(0.92)))
            .lineLimit(1)
            .padding(.horizontal, m.hPad)
            .frame(minHeight: m.height)
            .contentShape(Capsule())
            .glassSurface(Capsule(), tint: prominent ? (tint ?? Theme.accent) : nil)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    /// Liquid Glass behind this view in `shape`; `tint` fills it with color (prominent controls).
    /// `interactive` lets the glass react to the pointer — on for controls, off for static bars.
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// The system glass button styles for stock `Button`s that relied on `.bordered` /
    /// `.borderedProminent` (these honor `.tint`), falling back to bordered before macOS 26.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.ultraThinMaterial), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(tint == nil ? 0.14 : 0.22), lineWidth: 1))
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

/// Groups neighboring glass controls so they render as one sampled layer and can blend into each
/// other (cheaper than separate glass views, and the native look for a cluster of buttons).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

#Preview("Glass controls") {
    VStack(spacing: 16) {
        HStack(spacing: 10) {
            Button {} label: { Label("Home", systemImage: "arrow.left") }
            Button {} label: { Label("Edit", systemImage: "square.and.pencil") }
            Button {} label: { Label("Reveal", systemImage: "folder") }.labelStyle(.iconOnly)
            Button {} label: { Label("Reader View", systemImage: "doc.plaintext") }
                .buttonStyle(.sentientGlassProminent)
        }
        .buttonStyle(.sentientGlass)
        Button("Start Analysis") {}.buttonStyle(.sentientGlassProminent).controlSize(.large)
        Button("Disabled") {}.buttonStyle(.sentientGlass).disabled(true)
    }
    .padding(40)
    .background(Theme.bg)
    .preferredColorScheme(.dark)
}
