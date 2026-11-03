//
//  HomeToday.swift
//  Sentient OS macOS
//
//  Today: the opening of the conversation with Sentient, laid out the way Messages opens a thread
//  with Siri (SPEC-D1 S3). Top to bottom in one reading column:
//    · "Earlier Conversation" — the last message, its time, and Show Conversation (only when
//      history exists)
//    · a "Today" time break
//    · the assistant's first turn: the greeting, one line about the day, then its content — the
//      analysis status group, the suggestion list, or the knowledge-base-only preview
//    · quick replies (the starters) at the end of the turn
//  Today is presentation only: nothing here is written to the conversation history.
//
//  Also here: HomeSuggestionsInspector, the suggestion list beside the conversation (S6b).
//

import SwiftUI

struct HomeToday: View {
    let greeting: String
    let kbOnly: Bool
    let needsPersonalSetup: Bool
    let initialComplete: Bool
    let conversation: SidekickConversation
    /// The visible suggestions (dealt and not flying away), in deck order.
    let entries: [ForYouModel.Entry]
    /// Builds one suggestion row with HomeView's wiring.
    let row: (ForYouModel.Entry) -> HomeSuggestionRow
    /// The Analysis status group, when today's condition holds (built by HomeView).
    let analysisBlock: AnyView?
    /// The knowledge-base-only preview group (built by HomeView).
    let kbOnlyBlock: AnyView?
    let reduceMotion: Bool
    let onShowConversation: () -> Void
    let onStarter: (String) -> Void

    /// The scroll view's visible height (between the notice row and the Ask bar). Today's column is
    /// at least this tall and bottom-aligned inside it, so the scroll view never has to align short
    /// content itself. When `defaultScrollAnchor`'s alignment role did it, the top scroll
    /// edge effect reached from the top inset all the way down to the content's top edge and drew
    /// its dividing line across the page there (FIX1-NOTES, Home).
    @State private var viewportHeight: CGFloat = 0
    /// The end was pinned at the last viewport change and no change has come since, so the page
    /// still counts as at its end if another resize arrives before the pin lands.
    @State private var endPending = false
    /// A scroll gesture or its momentum is under way, so an offset change is the reader's.
    @State private var scrolling = false

    private var showsRows: Bool { !needsPersonalSetup && !entries.isEmpty }
    private static let end = "today-end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                column
                    .id(Self.end)
            }
            // Today opens at its end, and content that grows or shrinks keeps that end in view.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            // A new viewport size or inset (the window shrinking, a notice docking above) keeps the
            // content's offset whatever the anchor says, which slides the starters under the Ask bar.
            // A page that was at its end is put back there, as the transcript does.
            .onScrollGeometryChange(for: SidekickTranscriptLayout.Viewport.self) { geo in
                .init(top: geo.visibleRect.minY, height: geo.containerSize.height,
                      insetTop: geo.contentInsets.top, insetBottom: geo.contentInsets.bottom,
                      fromBottom: geo.contentSize.height - geo.visibleRect.maxY,
                      width: geo.containerSize.width, contentHeight: geo.contentSize.height)
            } action: { old, viewport in
                // The scroll view can undo a pin itself: a pass after a resize it puts back the
                // offset it had, leaving the page short of its end by the size change (a notice
                // docking, measured at 90 pt). A pending pin that leaves the end with no gesture
                // under way is put back once; only once, so the two can never trade the offset.
                let undone = endPending && !scrolling && old.atEnd && !viewport.atEnd
                let keep = undone || SidekickTranscriptLayout.Viewport.keepsEnd(from: old, to: viewport, pinPending: endPending)
                let pending = keep && !undone
                if endPending != pending { endPending = pending }
                if keep {
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { proxy.scrollTo(Self.end, anchor: .bottom) }
                }
            }
            .onScrollPhaseChange { _, phase in
                if scrolling != phase.isScrolling { scrolling = phase.isScrolling }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if !kbOnly, let last = conversation.previewMessage {
                earlierConversation(last)
            }
            Text("Today")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            // The assistant's turn stands unadorned on the column's edge, as in Messages: the
            // user's bubbles already tell the speakers apart.
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(greeting)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                bodyLine
            }
            if let analysisBlock { analysisBlock }
            if showsRows { suggestionRows }
            if let kbOnlyBlock { kbOnlyBlock }
            if !kbOnly { HomeSidekickSuggestions(onSelect: onStarter) }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.xl)
        .centeredColumn(maxWidth: PageMetrics.readingColumn)
        .frame(minHeight: viewportHeight, alignment: .bottom)
        .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: entries.map(\.id))
    }

    /// One line under the greeting, by state (first match wins).
    @ViewBuilder private var bodyLine: some View {
        if kbOnly {
            EmptyView()                               // the preview group speaks for itself
        } else if needsPersonalSetup {
            HomeSidekickInvitation()
        } else if !entries.isEmpty {
            Text("A few things to make your day easier.")
        } else if initialComplete {
            Text("What can I take off your hands? Your context is already here.")
        } else {
            Text("What can I take off your hands?")
        }
    }

    private var suggestionRows: some View {
        HomeInsetGroup {
            ForEach(entries) { entry in
                row(entry)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                if entry.id != entries.last?.id {
                    Divider().padding(.leading, 30 + Space.m + Space.l)
                }
            }
        }
        .transition(.opacity)
    }

    private func earlierConversation(_ last: SidekickConversation.Record) -> some View {
        HomeInsetGroup {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Earlier Conversation")
                        .font(.subheadline.weight(.semibold))
                    Text(peekText(last.event))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s)
                if conversation.unreadCount > 0 {
                    Circle()
                        .fill(.tint)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Unread")
                }
                Text(last.event.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Show Conversation", action: onShowConversation)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Expand conversation history")
                    .accessibilityIdentifier("sidekick.expandHistory")
            }
            // A suggestion row's insets, so the text and button sit on the edges the rows and the
            // Analysis block share.
            .padding(.vertical, Space.m)
            .padding(.horizontal, Space.l)
        }
    }

    /// The last message as one line: assistant Markdown rendered inline, newlines flattened.
    private func peekText(_ event: SidekickConversationEvent) -> AttributedString {
        let text = String(event.text.prefix(600)).replacingOccurrences(of: "\n", with: " ")
        guard event.kind == .assistantMessage else { return AttributedString(text) }
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Suggestions beside the conversation

/// The day's suggestions as a list in the inspector while the conversation fills the page, like
/// Mail's message list beside its reading pane (SPEC-D1 S6b).
struct HomeSuggestionsInspector: View {
    let entries: [ForYouModel.Entry]
    let row: (ForYouModel.Entry) -> HomeSuggestionRow

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView("No Suggestions", systemImage: "sparkles",
                                   description: Text("New suggestions arrive after the overnight run."))
        } else {
            List {
                Section {
                    ForEach(entries) { entry in
                        row(entry)
                            .listRowInsets(EdgeInsets())
                    }
                } header: {
                    Text("Today’s Suggestions")
                }
            }
            .listStyle(.inset)
        }
    }
}
