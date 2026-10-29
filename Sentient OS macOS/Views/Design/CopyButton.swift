//
//  CopyButton.swift
//  Sentient OS macOS
//
//  Copies a value to the pasteboard and says "Copied" with a checkmark for 2 seconds (SPEC-00 3.14).
//  The button style comes from the caller (default `.bordered`). InviteCopyButton keeps its own states.
//

import SwiftUI
import AppKit

struct CopyButton: View {
    private let title: String
    private let value: String
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    init(_ title: String = "Copy", value: String) {
        self.title = title
        self.value = value
    }

    private var animation: Animation? {
        Motion.gated(Motion.quick, reduceMotion: motionOverride ?? systemReduced)
    }

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            withAnimation(animation) { copied = true }
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(animation) { copied = false }
            }
        } label: {
            Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .onDisappear { resetTask?.cancel() }
    }
}

#Preview("Copy button") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            HStack(spacing: Space.m) {
                CopyButton(value: "ABCD-1234")
                CopyButton("Copy Path", value: "/Users/me/Sentient")
            }
            .buttonStyle(.bordered)
            .padding(Space.xl)
            .frame(maxWidth: .infinity)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 520)
}
