//
//  BriefingCard.swift
//  Sentient OS macOS
//
//  The kept wrapper for one suggestion. The card no longer has a look of its own: it is a
//  HomeSuggestionRow (Mail-style list row) in a HomeInsetGroup, at the caller's width, through the
//  same four phases: sealed (the unread gift) → offer → working → done. SPEC-D1 S10.
//

import SwiftUI

enum BriefingPhase: Equatable {
    case sealed            // welcome only: the unopened gift
    case offer
    case working(Int)      // how many workLog lines are visible
    case done
}

struct BriefingCard: View {
    let briefing: Briefing
    let phase: BriefingPhase
    var onOffer: () -> Void
    var onDetail: () -> Void
    var onOpenEnvelope: () -> Void
    var liveLines: [String] = []       // real cards: codex's live play-by-play (empty → demo theater)
    var onStop: (() -> Void)? = nil    // real cards: the per-card Stop
    var onOpenConversation: (() -> Void)? = nil
    var fireDimmed = false             // one task at a time: another task is running → the offer waits
    var cardWidth: CGFloat = BriefingCard.width
    var previewBodyLines = 5
    var previewTitleLines = 3
    var onDismiss: (() -> Void)? = nil

    static let width: CGFloat = 332

    var body: some View {
        HomeInsetGroup {
            HomeSuggestionRow(briefing: briefing, action: nil, phase: phase,
                              liveLines: liveLines, fireDimmed: fireDimmed,
                              onOpen: onDetail, onOffer: onOffer, onOpenEnvelope: onOpenEnvelope,
                              onStop: onStop, onOpenConversation: onOpenConversation,
                              onDismiss: onDismiss,
                              titleLineLimit: previewTitleLines, previewLineLimit: previewBodyLines)
        }
        .frame(width: cardWidth)
    }
}

// MARK: - The offer button (kept for callers; the row and the sheet draw their own)

struct OfferButton: View {
    let label: String
    let accent: Color          // ignored: no per-card tint
    var icon: String = "sparkles"
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .buttonStyle(.bordered)
    }
}

// MARK: - Previews

#Preview("Phases") {
    VStack(spacing: Space.l) {
        BriefingCard(briefing: Briefing.jesaiDemo[0], phase: .offer,
                     onOffer: {}, onDetail: {}, onOpenEnvelope: {}, onDismiss: {})
        BriefingCard(briefing: Briefing.jesaiDemo[3], phase: .working(3),
                     onOffer: {}, onDetail: {}, onOpenEnvelope: {})
        BriefingCard(briefing: Briefing.jesaiDemo[0], phase: .done,
                     onOffer: {}, onDetail: {}, onOpenEnvelope: {})
        BriefingCard(briefing: Briefing.jesaiDemo[5], phase: .sealed,
                     onOffer: {}, onDetail: {}, onOpenEnvelope: {})
    }
    .padding()
}
