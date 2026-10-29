// ComputerUseUpdateNotice.swift
// Home's computer-use update as a notice row (SPEC-D1 S4): real download progress, verification,
// retry, and done. Reads the shared installer so a Sidekick command and a launch-time update show
// the same state.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI

struct ComputerUseUpdateNotice: View {
    let state: ComputerUseSetup.UpdateNotice
    let progress: ComputerUseSetup.Progress?
    var onRetry: () -> Void = {}
    var onDismiss: () -> Void = {}

    /// The download fraction, when the installer knows one.
    private var fraction: Double? {
        if case .downloading(let f?) = progress { return f }
        return nil
    }

    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .ready:
            NoticeBar(tile: .noticeUpToDate, title: "Computer Use Is Up to Date",
                      dismissLabel: "Dismiss notification", onDismiss: onDismiss)
        case .failed:
            NoticeBar(tile: .noticeUpdateFailed, title: "Computer Use Couldn’t Update",
                      message: "Please try again.",
                      dismissLabel: "Dismiss notification", onDismiss: onDismiss) {
                Button("Retry", action: onRetry)
            }
        case .updating:
            NoticeBar(tile: .noticeUpdating, title: "Updating Computer Use",
                      message: progress?.message ?? "Preparing the update…",
                      progress: fraction.map { .fraction($0) } ?? .indeterminate)
                // NoticeBar's bar carries no label of its own; the row reports the progress.
                .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "In progress")
        }
    }
}

#Preview("Computer-use update") {
    VStack(spacing: Space.m) {
        ComputerUseUpdateNotice(state: .updating, progress: .downloading(0.58))
        ComputerUseUpdateNotice(state: .updating, progress: .checkingSignature)
        ComputerUseUpdateNotice(state: .failed, progress: nil)
        ComputerUseUpdateNotice(state: .ready, progress: .ready)
    }
    .padding(Space.xl)
    .frame(width: 680)
}
