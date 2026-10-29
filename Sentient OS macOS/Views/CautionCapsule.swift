//
//  CautionCapsule.swift
//  Sentient OS macOS
//
//  The kept entry point onto Home's notice row (SPEC-D1 S4): UpdateNoticeCapsule, the
//  self-contained "Sentient Was Updated" notice, rendered as a `NoticeBar`. It reads UpdateNotice
//  on appearance, draws nothing when no notice is armed, and retires it on dismiss or on opening
//  the changelog. Rendered by Home's notice slot and by RootView over onboarding.
//  `CautionCapsule` was deleted at the final cleanup: Home builds its NoticeBars directly
//  (HomeNotices, ComputerUseUpdateNotice), so it had no callers left.
//

import SwiftUI

/// The "Sentient Was Updated" notice — self-contained: reads UpdateNotice on appearance, draws
/// nothing when no notice is armed, and retires it on dismiss or on opening the changelog.
/// Hosts decide placement; this owns everything else.
struct UpdateNoticeCapsule: View {
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reducedMotion: Bool { motionOverride ?? systemReducedMotion }

    var body: some View {
        Group {
            if armed {
                NoticeBar(tile: .noticeAppUpdated, title: "Sentient Was Updated",
                          dismissLabel: "Dismiss notification",
                          onDismiss: {
                              UpdateNotice.dismiss()
                              retire()
                          }) {
                    Button("Read the Changelog") {
                        UpdateNotice.openChangelog()
                        retire()
                    }
                }
                // RootView's onboarding overlay gives it no width; the row's Spacer would
                // otherwise stretch it across the window. On Home the column already caps it.
                .frame(maxWidth: PageMetrics.readingColumn)
            }
        }
        .onAppear { armed = UpdateNotice.pending != nil }
    }

    private func retire() {
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reducedMotion)) { armed = false }
    }
}
