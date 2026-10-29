//
//  HomeNotices.swift
//  Sentient OS macOS
//
//  Home's one notice row, docked above the column like the account alert at the top of a System
//  Settings pane (SPEC-D1 S4). At most one notice shows, most severe first: something broken now
//  outranks last night's history, and good news never outranks a problem.
//
//    1 ChatGPT signed out · 2 a live HealthCaution issue · 3 computer-use update (updating/failed)
//    4 last night's caution · 5 a skipped connector · 6 computer use up to date
//    7 Sentient was updated, then the invite offer
//
//  The conditions and every dismiss path are HomeView's, unchanged; HomeView hands them in as
//  plain values and closures, so this view reads none of Home's state.
//

import SwiftUI

/// The closures behind each notice's buttons, built by HomeView from its existing private funcs.
struct HomeNoticeActions {
    var signIn: () -> Void
    var dismissSignedOut: () -> Void
    var openHealth: () -> Void
    var dismissIssue: (HealthCaution.Issue) -> Void
    var retryComputerUse: () -> Void
    var dismissComputerUse: () -> Void
    /// The overnight caution's one-click fix; nil when there is no caution or no fix for its kind.
    var cautionAction: (title: String, run: () -> Void)?
    var dismissCaution: () -> Void
    var openSources: () -> Void
    var dismissConnector: (String) -> Void
}

struct HomeNotices: View {
    /// False hides the whole slot (the quiet ranks stay out of the conversation and the setup flow).
    let visible: Bool
    let signedOut: Bool
    let liveIssue: HealthCaution.Issue?
    let caution: OvernightCaution.Record?
    let connector: ConnectorCaution.Item?
    let computerNotice: ComputerUseSetup.UpdateNotice
    let computerProgress: ComputerUseSetup.Progress?
    /// The invite may show (Home visible, real deck, no sheet or popover up).
    let showsInvite: Bool
    let reduceMotion: Bool
    let actions: HomeNoticeActions

    private let dismissLabel = "Dismiss notification"

    var body: some View {
        if visible {
            Group {
                if signedOut {
                    NoticeBar(tile: .noticeSignedOut, title: "ChatGPT Is Signed Out",
                              message: "Sign in to ChatGPT to keep Sentient working for you.",
                              dismissLabel: dismissLabel, onDismiss: actions.dismissSignedOut) {
                        Button("Sign In…", action: actions.signIn)
                    }
                } else if let issue = liveIssue {
                    NoticeBar(tile: .noticeHealth, title: "Sentient Needs Attention", message: issue.message,
                              dismissLabel: dismissLabel, onDismiss: { actions.dismissIssue(issue) }) {
                        Button("Open Settings", action: actions.openHealth)
                    }
                } else if computerNotice == .updating || computerNotice == .failed {
                    ComputerUseUpdateNotice(state: computerNotice, progress: computerProgress,
                                            onRetry: actions.retryComputerUse,
                                            onDismiss: actions.dismissComputerUse)
                } else if let caution {
                    NoticeBar(tile: .noticeOvernight, title: "Last Night’s Run", message: caution.message,
                              dismissLabel: dismissLabel, onDismiss: actions.dismissCaution) {
                        if let fix = actions.cautionAction {
                            Button(fix.title, action: fix.run)
                        }
                    }
                } else if let connector {
                    NoticeBar(tile: .noticeConnector, title: "A Source Was Skipped", message: connector.message,
                              dismissLabel: dismissLabel, onDismiss: { actions.dismissConnector(connector.slug) }) {
                        Button("Open Settings", action: actions.openSources)
                    }
                } else if computerNotice == .ready {
                    ComputerUseUpdateNotice(state: .ready, progress: nil, onDismiss: actions.dismissComputerUse)
                } else {
                    VStack(spacing: Space.s) {
                        UpdateNoticeCapsule()
                        // The offer waits behind every notice above. InviteBanner stays mounted
                        // while it has nothing to show, so its eligibility task keeps running.
                        if showsInvite { InviteBanner() }
                    }
                }
            }
            .frame(maxWidth: PageMetrics.readingColumn)
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .frame(maxWidth: .infinity)
            // Today's text must not show through the gutters around the docked row.
            .background(Color(nsColor: .textBackgroundColor))
            .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: rankKey)
        }
    }

    /// Which rung is showing. An Int because `HealthCaution.Issue` is not Equatable and
    /// `OvernightCaution.Record` is only Codable, so neither can be an animation value.
    private var rankKey: Int {
        if signedOut { return 1 }
        if liveIssue != nil { return 2 }
        if computerNotice == .updating || computerNotice == .failed { return 3 }
        if caution != nil { return 4 }
        if connector != nil { return 5 }
        if computerNotice == .ready { return 6 }
        return showsInvite ? 8 : 7
    }
}
