//
//  NoticeBar.swift
//  Sentient OS macOS
//
//  Home's actionable notice (SPEC-00 3.7): a 30 pt tile, a title, an optional message and
//  progress, up to two small bordered actions and an optional ✕. A grouped fill with a separator
//  hairline; no glass, no shadow. Home only.
//

import SwiftUI
import AppKit

struct NoticeBar<Actions: View>: View {
    nonisolated enum Progress: Equatable, Sendable {
        case fraction(Double)
        case indeterminate
    }

    private let tile: TileSpec
    private let title: String
    private let message: String?
    private let progress: Progress?
    private let dismissLabel: String
    private let onDismiss: (() -> Void)?
    private let actions: Actions
    @Environment(\.pixelLength) private var pixelLength

    /// Actions get `.bordered` and `.controlSize(.small)`; at most two. The first may be
    /// `.borderedProminent` only when it is the notice's whole point (the caller sets that).
    /// Insert it with `withAnimation(Motion.gated(Motion.standard, reduceMotion: …))`; the bar
    /// carries `Motion.barInsert` as its transition.
    init(tile: TileSpec, title: String, message: String? = nil, progress: Progress? = nil,
         dismissLabel: String = "Dismiss", onDismiss: (() -> Void)? = nil,
         @ViewBuilder actions: () -> Actions) {
        self.tile = tile
        self.title = title
        self.message = message
        self.progress = progress
        self.dismissLabel = dismissLabel
        self.onDismiss = onDismiss
        self.actions = actions()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
        HStack(spacing: 12) {
            IconTile(tile, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let progress {
                    progressBar(progress)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            actions
                .buttonStyle(.bordered)
                .controlSize(.small)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(dismissLabel)
                .accessibilityLabel(dismissLabel)
            }
        }
        .padding(12)
        .background(.background.secondary, in: shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: pixelLength))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .transition(Motion.barInsert)
    }

    @ViewBuilder
    private func progressBar(_ progress: Progress) -> some View {
        switch progress {
        case .fraction(let value):
            ProgressView(value: min(max(value, 0), 1))
                .progressViewStyle(.linear)
                .controlSize(.small)
        case .indeterminate:
            ProgressView()
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
    }
}

extension NoticeBar where Actions == EmptyView {
    init(tile: TileSpec, title: String, message: String? = nil, progress: Progress? = nil,
         dismissLabel: String = "Dismiss", onDismiss: (() -> Void)? = nil) {
        self.init(tile: tile, title: title, message: message, progress: progress,
                  dismissLabel: dismissLabel, onDismiss: onDismiss) { EmptyView() }
    }
}

#Preview("Notice bars") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(spacing: Space.m) {
                NoticeBar(tile: .noticeSignedOut, title: "Sign in to ChatGPT again",
                          message: "Sidekick can’t reach your AI until you sign in.", onDismiss: {}) {
                    Button("Sign In…") {}
                }
                NoticeBar(tile: .noticeUpdating, title: "Updating Sentient OS",
                          message: "Downloading version 2.4", progress: .fraction(0.42))
                NoticeBar(tile: .noticeUpToDate, title: "You’re up to date", onDismiss: {})
            }
            .padding(Space.xl)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 960)
}
