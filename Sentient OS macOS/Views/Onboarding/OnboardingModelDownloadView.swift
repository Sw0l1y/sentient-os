//
//  OnboardingModelDownloadView.swift
//  Sentient OS macOS
//
//  The on-device model download (ModelDownload), in two forms:
//  - Page: a Setup Assistant download page with a system tile, a determinate progress view and
//    honest numbers (GB of GB, percent, "Verifying…"); a warning line + Try Again on failure.
//  - Compact: one Software Update-style form row, used inside Analysis while it waits for the
//    model.
//  Both hand the bar off from the sidebar's download line (ModelDownloadWhisper) while visible,
//  so one bar is on screen, never two.
//

import SwiftUI

struct OnboardingModelDownloadView: View {
    let download: ModelDownload
    var compact = false                       // memberwise init(download:compact:); init(download:) still compiles

    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduce: Bool { motionOverride ?? systemReduced }

    private static let message = "Sentient’s on-device model reads your life privately, right on this Mac. It’s a one-time download, and your analysis starts the moment it lands."

    private var fraction: Double {
        download.bytesTotal > 0 ? min(1, Double(download.bytesDone) / Double(download.bytesTotal)) : 0
    }

    /// "2.61 GB of 3.66 GB" — decimal GB, matching how the model size is talked about everywhere.
    private var gbLine: String {
        String(format: "%.2f GB of %.2f GB",
               Double(download.bytesDone) / 1_000_000_000,
               Double(download.bytesTotal) / 1_000_000_000)
    }

    private var failureReason: String? {
        if case .failed(let reason) = download.phase { return reason }
        return nil
    }

    private var percentText: String {
        download.phase == .verifying ? "Verifying…" : "\(Int(fraction * 100))%"
    }

    var body: some View {
        // One container, so the appear/disappear hand-off below fires once for the whole view
        // (modifiers on a Group would apply to each child, and a child leaving on failure would
        // clear fullScreenVisible while the row is still on screen).
        ZStack {
            if compact { compactRow } else { page }
        }
        .animation(Motion.gated(Motion.standard, reduceMotion: reduce), value: download.phase)
        // The safety net: normally the post-FDA launch kick started this minutes ago, but if that
        // was missed (FDA granted without the relaunch), Start Analysis still gets a download.
        // fullScreenVisible hands the bar off from the sidebar line (ModelDownloadWhisper).
        .onAppear {
            download.kickIfNeeded()
            download.fullScreenVisible = true
        }
        .onDisappear { download.fullScreenVisible = false }
    }

    /// One form row: the model with its byte count (or "Download Failed") and the percent or
    /// Try Again, then the bar, or the full failure reason as a warning line.
    private var compactRow: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            LabeledContent {
                if failureReason != nil {
                    Button("Try Again") { download.kickIfNeeded() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Text(percentText).monospacedDigit().foregroundStyle(.secondary)
                }
            } label: {
                TileLabel("On-Device Model", subtitle: failureReason == nil ? gbLine : "Download Failed",
                          tile: .onDeviceModel)
            }
            if let reason = failureReason {
                StatusLabel(reason, tone: .warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView(value: fraction)
                    .accessibilityLabel("On-Device Model Download")
                    .accessibilityValue(percentText)
            }
        }
    }

    private var page: some View {
        SetupAssistantPage(tile: .setupModelDownload, title: "Downloading Your AI", message: Self.message) {
            if let reason = failureReason {
                VStack(alignment: .leading, spacing: Space.l) {
                    StatusLabel(reason, tone: .warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") { download.kickIfNeeded() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: Space.s) {
                    ProgressView(value: fraction)
                        .accessibilityLabel("Download Progress")
                        .accessibilityValue(percentText)
                    HStack {
                        Text(gbLine)
                        Spacer()
                        Text(percentText)
                    }
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        } footer: {
            OnboardingTrustFooter()
                .frame(maxWidth: .infinity)
        }
    }
}

// previewInstance is DEBUG-only, and #Preview bodies compile in Release too — so these must be guarded.
#if DEBUG
#Preview("Downloading — mid-flight") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingModelDownloadView(download: .previewInstance(phase: .downloading, bytesDone: 2_610_000_000))
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 1180, height: 640)
}

#Preview("Downloading — failed") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingModelDownloadView(download: .previewInstance(
                phase: .failed("Sentient could not reach the download server. Check your internet connection, then hit Try Again.")))
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 1180, height: 640)
}

#Preview("Compact row") {
    Form {
        Section("On-Device Model") {
            OnboardingModelDownloadView(download: .previewInstance(phase: .downloading, bytesDone: 2_610_000_000), compact: true)
        }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 200)
}
#endif
