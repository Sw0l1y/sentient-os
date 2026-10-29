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

    private var showsRows: Bool { !needsPersonalSetup && !entries.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if !kbOnly, let last = conversation.previewMessage {
                    earlierConversation(last)
                }
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                HomeAssistantTurn {
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
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.xl)
            .centeredColumn(maxWidth: PageMetrics.readingColumn)
            .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: entries.map(\.id))
        }
        .defaultScrollAnchor(.bottom)
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
                BrandMarkView(size: 16)
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
            .padding(Space.m)
        }
    }

    /// The last message as one line: assistant Markdown rendered inline, newlines flattened.
    private func peekText(_ event: SidekickConversationEvent) -> AttributedString {
        let text = String(event.text.prefix(600)).replacingOccurrences(of: "\n", with: " ")
        guard event.kind == .assistantMessage else { return AttributedString(text) }
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// Sentient's speaker convention: the brand mark in a 24 pt gutter, then the turn's content.
private struct HomeAssistantTurn<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            BrandMarkView(size: 16)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: Space.l) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
