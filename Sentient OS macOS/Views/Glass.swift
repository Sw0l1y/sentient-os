//
//  Glass.swift
//  Sentient OS macOS
//
//  The only file that names a macOS 26 API (SPEC-00 3.2). The window's sidebar, toolbar, sheets,
//  popovers and menus get Liquid Glass from the system; custom glass is only for floating controls
//  over content (the Home Ask field, the New Response pill, the graph zoom group, PermissionGuide),
//  through `floatingGlass(in:interactive:)`. Every helper here has a macOS 15 fallback.
//

import SwiftUI
import AppKit

// The app's own button style (SentientButtonStyle, formerly GlassButtonStyle, which shadowed
// SwiftUI's `GlassButtonStyle`) and its `.sentientGlass` / `.sentientGlassProminent` aliases were
// deleted at the final cleanup (SPEC-00 4.2 step 5): buttons are `.bordered` / `.borderedProminent`,
// and floating controls use `glassButtonStyle(prominent:)` below.

extension View {
    /// Liquid Glass on a floating control (Ask field, New Response pill, graph zoom group, PermissionGuide).
    /// macOS 26: glassEffect(.regular[.interactive()], in: shape).
    /// macOS 15: .background(.regularMaterial, in: shape) + shape.stroke(Color(nsColor: .separatorColor), lineWidth: 1).
    func floatingGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(FloatingGlass(shape: shape, interactive: interactive))
    }

    /// A bar pinned to the top or bottom edge of a scroll view (the Home Ask bar).
    /// macOS 26: safeAreaBar(edge:spacing:content:). macOS 15: safeAreaInset(edge:spacing:content:), no
    /// background (the floating control inside carries its own material).
    @ViewBuilder
    func floatingBar<Bar: View>(edge: VerticalEdge = .bottom, spacing: CGFloat? = nil,
                                @ViewBuilder content: () -> Bar) -> some View {
        let bar = content()
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: spacing) { bar }
        } else {
            safeAreaInset(edge: edge, spacing: spacing) { bar }
        }
    }

    /// macOS 26: scrollEdgeEffectStyle(.soft, for: edges). macOS 15: no-op.
    @ViewBuilder
    func softScrollEdge(_ edges: Edge.Set = .all) -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }

    /// macOS 26: backgroundExtensionEffect(). macOS 15: no-op. Only the Knowledge graph canvas may use it.
    @ViewBuilder
    func extendsBackground() -> some View {
        if #available(macOS 26.0, *) {
            backgroundExtensionEffect()
        } else {
            self
        }
    }

    /// The system glass button styles (`.glass` / `.glassProminent`) on macOS 26, `.bordered` /
    /// `.borderedProminent` before. For floating controls only (Ask field Send, New Response pill).
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

private struct FloatingGlass<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }
}

/// Groups neighboring glass controls so they render as one sampled layer and can blend into each
/// other: GlassEffectContainer on macOS 26, plain content before.
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

#Preview("Floating glass") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(spacing: Space.l) {
                HStack(spacing: Space.s) {
                    Text("Ask anything")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {} label: { Image(systemName: "arrow.up") }
                        .glassButtonStyle(prominent: true)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s)
                .floatingGlass(in: Capsule(), interactive: true)
                GlassGroup {
                    HStack(spacing: Space.s) {
                        Button {} label: { Image(systemName: "minus.magnifyingglass") }
                        Button {} label: { Image(systemName: "plus.magnifyingglass") }
                    }
                    .glassButtonStyle()
                }
                HStack(spacing: Space.s) {
                    Button("Cancel") {}.buttonStyle(.bordered)
                    Button("Start Analysis") {}.buttonStyle(.borderedProminent)
                }
            }
            .padding(Space.xxl)
            .frame(maxWidth: .infinity)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 720)
}
