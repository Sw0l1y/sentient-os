//
//  PaneForm.swift
//  Sentient OS macOS
//
//  A grouped Form centered in a reading column (SPEC-00 3.12). Every Settings pane, Finish Setup and
//  the Analysis page (`maxWidth: PageMetrics.setupPage`) use it.
//

import SwiftUI

struct PaneForm<Content: View>: View {
    private let maxWidth: CGFloat
    private let content: Content
    @State private var width: CGFloat = 0

    init(maxWidth: CGFloat = PageMetrics.readingColumn, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .contentMargins(.horizontal, max(Space.xl, (width - maxWidth) / 2), for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
    }
}

extension View {
    /// Centers non-Form content in a column: .frame(maxWidth: maxWidth).frame(maxWidth: .infinity).
    func centeredColumn(maxWidth: CGFloat = PageMetrics.readingColumn) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}

#Preview("Pane form") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            PaneForm(maxWidth: 360) {
                Section("General") {
                    Toggle("Open at Login", isOn: .constant(true))
                    LabeledContent("Version", value: "2.4")
                }
            }
            .frame(width: 560, height: 260)
            .environment(\.colorScheme, scheme)
        }
    }
}
