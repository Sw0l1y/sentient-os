//
//  ModelDownloadWhisper.swift
//  Sentient OS macOS
//
//  The on-device model download as one activity line, the way Mail shows background progress at
//  the foot of its sidebar: a caption, a mini progress bar and honest numbers. It lives in the
//  sidebar footer (AppSidebar's SidebarStatusFooter) and, during onboarding, in RootView's
//  bottom-left whispers overlay. It yields while onboarding's full-screen downloading view shows
//  the same bar (ModelDownload.fullScreenVisible), disappears on .ready, and becomes one orange
//  "paused" line on .failed (the full-screen view owns the Try Again flow).
//

import SwiftUI

struct ModelDownloadWhisper: View {
    let download: ModelDownload

    /// Nothing renders when there's nothing to report (idle/ready), or while the full-screen
    /// downloading view has the bar: the bar never shows twice on one screen.
    private var visible: Bool {
        if download.fullScreenVisible { return false }
        switch download.phase {
        case .downloading, .verifying, .failed: return true
        case .idle, .ready: return false
        }
    }

    private var fraction: Double {
        download.bytesTotal > 0 ? min(1, max(0, Double(download.bytesDone) / Double(download.bytesTotal))) : 0
    }

    /// "1.24 of 3.66 GB": decimal GB, same voice as the full-screen downloading view.
    private var gbLine: String {
        String(format: "%.2f of %.2f GB",
               Double(download.bytesDone) / 1_000_000_000,
               Double(download.bytesTotal) / 1_000_000_000)
    }

    private var progressLine: String {
        gbLine + " · " + (download.phase == .verifying
            ? "Verifying…"
            : fraction.formatted(.percent.precision(.fractionLength(0))))
    }

    var body: some View {
        if visible {
            Group {
                if case .failed = download.phase { paused } else { downloading }
            }
            .font(.caption)
            // It also renders in the onboarding overlay, which sets no width: never stretch the bar.
            .frame(maxWidth: 240, alignment: .leading)
            .transition(.opacity)
        }
    }

    private var downloading: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Downloading on-device model")
                .lineLimit(1)
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .controlSize(.mini)
                .accessibilityLabel("On-device model download")
                .accessibilityValue(progressLine)
            Text(progressLine)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var paused: some View {
        Label("Model download paused. It will resume when you continue.", systemImage: "pause.circle")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// previewInstance is DEBUG-only, and #Preview bodies compile in Release too, so these are guarded.
#if DEBUG
#Preview("Download line: states") {
    HStack(alignment: .top, spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(alignment: .leading, spacing: Space.l) {
                ModelDownloadWhisper(download: .previewInstance(phase: .downloading, bytesDone: 310_000_000))
                ModelDownloadWhisper(download: .previewInstance(phase: .downloading, bytesDone: 2_610_000_000))
                ModelDownloadWhisper(download: .previewInstance(phase: .verifying, bytesDone: 3_659_530_240))
                ModelDownloadWhisper(download: .previewInstance(
                    phase: .failed("Sentient could not reach the download server.")))
            }
            .padding(Space.m)
            .frame(width: 232, height: 260, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
        }
    }
}
#endif
