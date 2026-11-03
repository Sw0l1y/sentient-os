//
//  HomeNotices.swift
//  Sentient OS macOS
//
//  Home's one notice row (SPEC-D1 S4). At most one notice shows, most severe first: something
//  broken now outranks last night's history, and good news never outranks a problem.
//
//  On Today it is part of the page (`docked: false`): the last thing in the assistant's turn, above
//  the quick replies, where Messages shows a thread's notices beside its latest message. Today opens
//  at its end, so that is where it is seen, and it scrolls with the page: docked above Today, it
//  made the scroll view's top edge a line through the page that cut the top row off flat. Over the
//  conversation and an example it docks above the page, under the toolbar (`docked: true`).
//
//    1 ChatGPT signed out · 2 a live HealthCaution issue · 3 computer-use update (updating/failed)
//    4 last night's caution · 5 a skipped connector · 6 computer use up to date
//    7 Sentient was updated, then the invite offer
//
//  The conditions and every dismiss path are HomeView's, unchanged; HomeView hands them in as
//  plain values and closures, so this view reads none of Home's state.
//

import SwiftUI

extension EnvironmentValues {
    /// False while the reader is away from Home's notice slot: on Today it sits near the end of a
    /// page that may be scrolled up. A notice spent just by appearing (the invite) waits for it.
    @Entry var noticeSlotInView = true
}

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
    /// Above the page, with the page margins and an opaque backing; false: inside Today's column.
    var docked = true

    private let dismissLabel = "Dismiss notification"

    var body: some View {
        if visible {
            // An empty slot takes no height: a padded empty slot is a strip of page with nothing in
            // it (under the toolbar, it cut Today's top edge off flat). The last rung's notices
            // decide for themselves whether to draw, and the invite stays mounted while it waits,
            // so only the layout can tell whether the slot holds anything.
            if docked {
                NoticeSlotLayout(top: Space.m, bottom: Space.s) { notice }
                    // The page margin sits inside the reading column, as in Today and the
                    // conversation, so the notice shares their edges at every width.
                    .padding(.horizontal, Space.xl)
                    .centeredColumn()
                    // The page's text must not show through the gutters around the docked row.
                    .background(Color(nsColor: .textBackgroundColor))
                    .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: rankKey)
            } else {
                // Today's column has the margins; the slot brings its own gap above.
                NoticeSlotLayout(top: Space.l, bottom: 0) { notice }
                    .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: rankKey)
            }
        }
    }

    @ViewBuilder private var notice: some View {
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

/// Stacks the slot's content (two notices while one replaces the other) and insets it by `top`
/// and `bottom` while it has any height; while it is empty it takes no height at all.
private struct NoticeSlotLayout: Layout {
    let top: CGFloat
    let bottom: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        let height = sizes.reduce(0) { $0 + $1.height }
        return CGSize(width: sizes.map(\.width).max() ?? 0, height: height > 0 ? top + height + bottom : 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let row = ProposedViewSize(width: bounds.width, height: nil)
        var y = bounds.minY + top
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: row)
            y += subview.sizeThatFits(row).height
        }
    }
}
