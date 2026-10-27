//
//  Glass.swift
//  Sentient OS macOS
//
//  The one control language: the system's own push buttons. GlassButtonStyle is a thin wrapper
//  over `.bordered` / `.borderedProminent` so every app-wide button is a standard macOS control
//  (macOS 26 draws those in Liquid Glass itself). `glassSurface` stays for the few floating
//  surfaces that sit over content — never on content cards or long chip lists.
//

import SwiftUI

/// A standard macOS push button. `prominent` is the one primary action per surface (filled with the
/// accent); `tint` recolors the button (a green "connected", a red "remove").
struct GlassButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    var tint: Color? = nil

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let button = Button(role: configuration.role, action: configuration.trigger) { configuration.label }
        if prominent {
            button.buttonStyle(.borderedProminent).tint(tint)
        } else {
            button.buttonStyle(.bordered).tint(tint)
        }
    }
}

extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    static var sentientGlass: GlassButtonStyle { GlassButtonStyle() }
    static var sentientGlassProminent: GlassButtonStyle { GlassButtonStyle(prominent: true) }
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
