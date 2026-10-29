import SwiftUI
import AppKit

/// The Home conversation, laid out like Messages: your messages are accent bubbles on the right,
/// Sentient's answers are plain document text on the left under a brand-mark gutter, in a
/// 680 pt reading column on the system text background (HomeView supplies the background and
/// the floating Ask bar; this view draws none). While the toolbar search has text, a results
/// list replaces the transcript.
struct SidekickTranscript: View {
    let conversation: SidekickConversation
    let coordinator: CommandCoordinator
    @Bindable var presentation: SidekickPresentation
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduced: Bool { motionOverride ?? systemReduced }
    @State private var columnWidth: CGFloat = PageMetrics.readingColumn
    private struct RefreshKey: Equatable {
        let generation: UUID?
        let revision: UInt64
        let ready: Bool
    }
    private struct NavigationKey: Equatable {
        let generation: UUID?
        let request: UUID?
    }
    private struct ActiveWorkKey: Equatable {
        let generation: UUID?
        let taskID: UUID?
    }
    private var activeWorkKey: ActiveWorkKey {
        .init(generation: conversation.generation, taskID: coordinator.run.isRunning ? coordinator.run.runID : nil)
    }
    private var refreshKey: RefreshKey {
        RefreshKey(generation: conversation.generation, revision: conversation.revision,
                   ready: active && conversation.navigationRequest == nil && !presentation.searchShown
                       && presentation.newMessages && presentation.canFollowLatest)
    }
    private var searching: Bool { presentation.searchShown && !presentation.search.isEmpty }
    private var showsLatestButton: Bool {
        presentation.hasLater || (presentation.newMessages && !presentation.atLatest)
            || (!presentation.followsLatest && presentation.activeWorkTaskID != nil)
    }

    var body: some View {
        Group {
            if searching {
                SidekickSearchResults(conversation: conversation, presentation: presentation)
            } else {
                transcript
            }
        }
        // The query comes from Home's toolbar search field; results replace the transcript.
        .task(id: presentation.search) { await presentation.find(conversation: conversation) }
        .onChange(of: activeWorkKey, initial: true) { _, key in
            presentation.followActiveWork(key.taskID, generation: key.generation)
        }
        .onChange(of: active, initial: true) { _, visible in
            guard visible, conversation.navigationRequest == nil else { return }
            presentation.resumeFollowing(generation: conversation.generation)
        }
        .onAppear { presentation.isScrolling = false }
        .onDisappear { presentation.isScrolling = false }
        .task(id: NavigationKey(generation: conversation.generation, request: conversation.navigationRequest)) {
            presentation.resetForGeneration(conversation.generation)
            if let request = conversation.navigationRequest {
                presentation.search = ""; presentation.searchShown = false
                if let id = conversation.destinationMessageID {
                    await presentation.load(.around(id), conversation: conversation)
                } else { await presentation.load(.latest, conversation: conversation, animated: active && !reduced) }
                if !Task.isCancelled && conversation.navigationRequest == request { conversation.consumeDestination() }
            } else if presentation.rows.isEmpty { await presentation.load(.latest, conversation: conversation) }
        }
        .onChange(of: conversation.revision) { _, _ in
            presentation.newMessages = true
        }
        .task(id: conversation.revision) { await presentation.refreshTaskStates(conversation: conversation) }
        .task(id: refreshKey) {
            guard refreshKey.ready else { return }
            await presentation.load(.latest, conversation: conversation, animated: !reduced, automaticallyFollowing: true)
        }
    }

    private var transcript: some View {
        // Capture rows and their generation together. A retained old row must not borrow
        // the conversation's newer identity while Clear chat is replacing the viewport.
        let generation = presentation.generation
        let display = SidekickTranscriptLayout.rows(presentation.rows)
        let leaders = Self.runLeaders(display)
        return ScrollViewReader { proxy in
            ScrollView {
                // History is already paged (normally 40, at most 100 records). Stable
                // measured rows avoid lazy estimated-height gaps when a live disclosure
                // moves into its final response while the window is hidden.
                VStack(alignment: .leading, spacing: 0) {
                    if presentation.hasEarlier {
                        pagingButton("Earlier Messages", symbol: "arrow.up") {
                            guard let first = presentation.rows.first else { return }
                            Task { await presentation.load(.earlier(first.sequence), conversation: conversation) }
                        }
                    }
                    if let error = presentation.error {
                        historyError(error)
                    }
                    if presentation.rows.isEmpty && !presentation.loading && presentation.error == nil && conversation.storageError == nil {
                        emptyState
                    }
                    ForEach(display) { row in
                        VStack(alignment: .leading, spacing: Space.m) {
                            if let date = row.timeBreak {
                                Text(SidekickTranscriptLayout.timeBreakLabel(date))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, Space.s)
                            }
                            SidekickMessageRow(record: row.record, showsWork: row.showsWork,
                                leadsRun: leaders.contains(row.id), bubbleWidth: columnWidth * 0.75,
                                generation: generation, conversation: conversation, coordinator: coordinator,
                                presentation: presentation, active: active)
                        }
                        .padding(.top, leaders.contains(row.id) ? Space.l : Space.m)
                        .id(row.id)
                        .transition(.opacity)
                    }
                    if presentation.hasLater {
                        pagingButton("Later Messages", symbol: "arrow.down") {
                            guard let last = presentation.rows.last else { return }
                            Task { await presentation.load(.later(last.sequence), conversation: conversation) }
                        }
                    } else if coordinator.run.isRunning && !display.contains(where: { $0.showsWork && $0.record.event.taskID == coordinator.run.runID }) {
                        SidekickWorkDisclosure(conversation: conversation, taskID: coordinator.run.runID,
                            state: presentation.taskStates[coordinator.run.runID], presentation: presentation,
                            running: true, waiting: coordinator.run.recovery.isPending, active: active,
                            liveStatus: coordinator.run.statusLine)
                            .padding(.leading, 24).padding(.top, Space.m)
                    }
                    Color.clear.frame(height: 1).id("sidekick-bottom")
                }
                .padding(.horizontal, Space.xl).padding(.top, Space.l).padding(.bottom, Space.m)
                .frame(maxWidth: PageMetrics.readingColumn)
                .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * Space.xl } action: { columnWidth = max(200, $0) }
                .frame(maxWidth: .infinity)
                .scrollTargetLayout()
            }
            // A final response can acquire its activity height after the explicit scroll
            // request. Keep followers at the native bottom through those size changes;
            // deliberate history reading/selection keeps its existing viewport instead.
            .defaultScrollAnchor(presentation.canFollowLatest ? .bottom : nil, for: .sizeChanges)
            .onScrollPhaseChange { _, phase, context in
                // Programmatic smooth scrolling is not a new reading gesture. Use this
                // phase's actual geometry so a late layout callback cannot re-enable follow.
                let bottom = context.geometry.contentSize.height - context.geometry.visibleRect.maxY < 70
                presentation.userScrollChanged(phase == .tracking || phase == .interacting || phase == .decelerating,
                                               atLatest: bottom)
            }
            // ScrollViewReader owns navigation and live following. A second top-anchored
            // scrollPosition binding competes with bottom following as row heights change.
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentSize.height - geo.visibleRect.maxY < 70
            } action: { _, bottom in presentation.viewportChanged(atLatest: bottom) }
            .task(id: presentation.scrollRequest) {
                let request = presentation.scrollRequest
                let requestedDestination = presentation.navigationTarget
                let automatic = presentation.scrollIsAutomatic
                let intent = presentation.readingIntentRevision
                // Activity rows and their expanded viewport measure in the next layout pass.
                // Coalesce bursts before scrolling to the new actual tail, not its old frame.
                await Task.yield()
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                guard !Task.isCancelled, request == presentation.scrollRequest,
                      let requestedTarget = requestedDestination else { return }
                let target = SidekickTranscriptLayout.destination(requestedTarget, records: presentation.rows)
                guard !automatic || (active && intent == presentation.readingIntentRevision
                    && presentation.canFollowLatest) else { return }
                let tail = target == "sidekick-bottom" || target.hasPrefix("sidekick-work-bottom-")
                if tail && !reduced {
                    withAnimation(Motion.gated(.smooth(duration: 0.28), reduceMotion: reduced)) {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                } else { proxy.scrollTo(target, anchor: tail ? .bottom : .top) }
            }
            .overlay(alignment: .bottom) { latestButton }
        }
        // A deleted conversation has a new identity, including its native scroll viewport.
        // Do not retain a months-old content offset over the fresh empty state.
        .id(conversation.generation)
    }

    /// The Messages / Mail "jump to latest" glass capsule, floating above the Ask field.
    private var latestButton: some View {
        ZStack {
            if showsLatestButton {
                Button {
                    Task { await presentation.load(.latest, conversation: conversation) }
                } label: {
                    Label(presentation.newMessages ? "New Response" : "Back to Latest", systemImage: "arrow.down")
                }
                .glassButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .accessibilityIdentifier("sidekick.latest")
                .padding(.bottom, Space.m)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.gated(Motion.standard, reduceMotion: reduced), value: showsLatestButton)
    }

    @ViewBuilder private func historyError(_ error: String) -> some View {
        // One model string is shared by history loading and search; a stale search error keeps
        // its own words rather than claiming the history failed.
        Group {
            if error.hasPrefix("History") {
                ContentUnavailableView {
                    Label("History Couldn’t Be Loaded", systemImage: "exclamationmark.bubble")
                } description: {
                    Text("Your existing data has been preserved.")
                } actions: {
                    Button("Try Again") { Task { await presentation.load(.latest, conversation: conversation) } }
                }
            } else {
                ContentUnavailableView {
                    Label(error, systemImage: "exclamationmark.bubble")
                } actions: {
                    Button("Try Again") { Task { await presentation.load(.latest, conversation: conversation) } }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("A little help. A lot more possible.")
            } icon: {
                BrandMarkView(size: 40)
            }
        } description: {
            Text("Ask a question, follow a thought, or hand something over.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxxl)
    }

    private func pagingButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(presentation.loading)
            .frame(maxWidth: .infinity).padding(.vertical, Space.m)
    }

    /// A row leads a run when its sender differs from the previous display row's, or a time break
    /// precedes it. You: `.userMessage` and `.answer`; Sentient: everything else.
    private static func runLeaders(_ rows: [SidekickTranscriptLayout.Row]) -> Set<String> {
        var leaders = Set<String>()
        var previousIsYou: Bool?
        for row in rows {
            let kind = row.record.event.kind
            let isYou = kind == .userMessage || kind == .answer
            if row.timeBreak != nil || previousIsYou != isYou { leaders.insert(row.id) }
            previousIsYou = isYou
        }
        return leaders
    }
}

private struct SidekickMessageRow: View {
    let record: SidekickConversationStore.Record
    let showsWork: Bool
    let leadsRun: Bool
    let bubbleWidth: CGFloat
    let generation: UUID?
    let conversation: SidekickConversation
    let coordinator: CommandCoordinator
    let presentation: SidekickPresentation
    var active: Bool
    @State private var visible = false
    @State private var hovered = false
    @State private var copied = false
    @Environment(\.sidekickHoveredMessageID) private var hoverOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var event: SidekickConversationEvent { record.event }
    private var user: Bool { event.kind == .userMessage || event.kind == .answer }
    private var incoming: Bool { event.kind == .assistantMessage || event.kind == .question }
    private var running: Bool { coordinator.run.isRunning && coordinator.run.runID == event.taskID }
    /// The brand-mark gutter that Sentient's text, status lines and work line up past.
    private static let gutter: CGFloat = 24
    private struct ReadReceiptKey: Equatable {
        let generation: UUID?
        let messageID: String
        let visible: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if showsWork {
                SidekickWorkDisclosure(conversation: conversation, taskID: event.taskID,
                    state: presentation.taskStates[event.taskID], presentation: presentation,
                    running: running, waiting: running && coordinator.run.recovery.isPending, active: active,
                    liveStatus: running ? coordinator.run.statusLine : "")
                    .padding(.leading, Self.gutter)
            }
            if event.kind == .taskFinished {
                if let status = standaloneStatus {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled).padding(.leading, Self.gutter)
                }
            } else { message }
        }
        .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
        .task(id: ReadReceiptKey(generation: generation, messageID: event.id, visible: active && visible)) {
            guard incoming, active, visible, let generation, conversation.generation == generation else { return }
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard !Task.isCancelled, active, visible, conversation.generation == generation else { return }
            conversation.markRead(messageIDs: [event.id], generation: generation)
        }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(1.8)); copied = false } catch { }
        }
    }

    private var message: some View {
        Group {
            if user {
                // Yours: a right-aligned accent bubble that hugs its text, the reply quote above it.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: Space.xs) {
                        replyReference
                        SidekickPlainText(text: event.text, onReply: { reply($0) }, onReplyToMessage: { reply(nil) },
                            onSelectionChange: { presentation.setSelection($0, messageID: event.id) }, bubble: true)
                            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
                    }
                    .frame(maxWidth: bubbleWidth, alignment: .trailing)
                }
            } else {
                // Sentient's: unboxed document text, with the mark once per run in the gutter.
                HStack(alignment: .top, spacing: 0) {
                    Group {
                        if leadsRun { BrandMarkView(size: 16).padding(.top, 2) }
                    }
                    .frame(width: Self.gutter, alignment: .leading)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        replyReference
                        SidekickMarkdown(markdown: event.text, compact: event.messageKind == .update,
                            onReply: reply, onReplyToMessage: { reply(nil) },
                            onSelectionChange: { presentation.setSelection($0, messageID: event.id) })
                            .opacity(event.messageKind == .update ? 0.76 : 1)
                    }
                }
            }
        }
        .contextMenu {
            Button("Copy message", systemImage: "doc.on.doc", action: copy)
            Button("Reply to message", systemImage: "arrowshape.turn.up.left") { reply(nil) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(user ? "Your message" : "Sidekick response")
        .accessibilityAction(named: "Copy message", copy)
        .accessibilityAction(named: "Reply to message") { reply(nil) }
        // A quiet reserved gutter avoids shifting the conversation when controls appear.
        .padding(.bottom, 20)
        .overlay(alignment: user ? .bottomTrailing : .bottomLeading) { hoverMeta }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(Motion.gated(Motion.quick, reduceMotion: motionOverride ?? systemReduced), value: hovered)
    }

    @ViewBuilder private var replyReference: some View {
        if let reference = event.reply {
            Button { conversation.show(messageID: reference.messageID) } label: {
                Label(reference.selectedText.map { String($0.prefix(100)) } ?? "Earlier message",
                      systemImage: "arrowshape.turn.up.left")
                    .lineLimit(2)
            }
            .buttonStyle(.borderless)
            .font(.caption).foregroundStyle(.secondary)
            .help("Show Original Message")
        }
    }

    @ViewBuilder private var hoverMeta: some View {
        if hovered || copied || hoverOverride == event.id {
            HStack(spacing: Space.s) {
                Text(SidekickTranscriptLayout.hoverDate(event.createdAt))
                    .font(.caption)
                    .help(event.createdAt.formatted(date: .complete, time: .shortened))
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless).controlSize(.small)
                .help(copied ? "Copied" : "Copy message")
                .accessibilityLabel(copied ? "Copied" : "Copy message")
            }
            .foregroundStyle(.secondary)
            .padding(.leading, user ? 0 : Self.gutter)
            .transition(.opacity)
        }
    }

    private var standaloneStatus: String? {
        guard event.outcome == .success || event.outcome == .failed else { return nil }
        let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !["done", "completed", "✓ done", "✓ completed"].contains(text.lowercased()) else { return nil }
        return text
    }
    private func copy() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(event.text, forType: .string)
        copied = true
    }
    private func reply(_ selected: String?) {
        conversation.replyReference = .init(messageID: event.id, selectedText: selected)
    }
}

/// Messages-style search results: sender, time and a snippet with the match in bold. A click
/// opens the transcript around that message. No selection binding, so arrow keys never navigate.
private struct SidekickSearchResults: View {
    let conversation: SidekickConversation
    @Bindable var presentation: SidekickPresentation

    var body: some View {
        Group {
            if presentation.error?.hasPrefix("Search") == true {
                ContentUnavailableView {
                    Label("Search Couldn’t Be Completed", systemImage: "magnifyingglass")
                } description: {
                    Text("Try again.")
                } actions: {
                    Button("Try Again") { Task { await presentation.find(conversation: conversation) } }
                }
            } else if presentation.searchResults.isEmpty {
                ContentUnavailableView.search(text: presentation.search)
            } else {
                List {
                    Section("From Your Saved Conversation") {
                        ForEach(presentation.searchResults, id: \.event.id) { record in
                            Button {
                                presentation.search = ""; presentation.searchShown = false
                                Task { await presentation.load(.around(record.event.id), conversation: conversation) }
                            } label: { row(record) }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("sidekick.searchResults")
            }
        }
        .frame(maxWidth: PageMetrics.readingColumn)
        .frame(maxWidth: .infinity)
    }

    private func row(_ record: SidekickConversationStore.Record) -> some View {
        let you = record.event.kind == .userMessage || record.event.kind == .answer
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(you ? "You" : "Sentient").font(.headline)
                Spacer()
                Text(SidekickTranscriptLayout.hoverDate(record.event.createdAt))
                    .font(.caption).foregroundStyle(.secondary)
                    .help(record.event.createdAt.formatted(date: .complete, time: .shortened))
            }
            Text(Self.snippet(record.event.text, query: presentation.search))
                .font(.callout).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .combine)
    }

    /// The first 700 characters, starting a little before a late match, with every
    /// case-insensitive match set in bold.
    static func snippet(_ text: String, query: String) -> AttributedString {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var excerpt = Substring(text)
        var prefix = ""
        if !needle.isEmpty, let first = text.range(of: needle, options: .caseInsensitive) {
            let offset = text.distance(from: text.startIndex, to: first.lowerBound)
            if offset > 80 {
                excerpt = text[text.index(first.lowerBound, offsetBy: -60)...]
                prefix = "…"
            }
        }
        var result = AttributedString(prefix + String(excerpt.prefix(700)))
        guard !needle.isEmpty else { return result }
        var searchStart = result.startIndex
        while searchStart < result.endIndex,
              let match = result[searchStart...].range(of: needle, options: .caseInsensitive) {
            result[match].inlinePresentationIntent = .stronglyEmphasized
            searchStart = match.upperBound
        }
        return result
    }
}
