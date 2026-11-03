import SwiftUI
import AppKit

/// The Home conversation, laid out like Messages: your messages are accent bubbles on the right,
/// Sentient's answers are plain document text at the column's leading edge, with no avatar (the
/// bubbles already tell the speakers apart), in a 680 pt reading column on the system text
/// background (HomeView supplies the background and the floating Ask bar; this view draws none).
/// While the toolbar search has text, a results list replaces the transcript.
struct SidekickTranscript: View {
    let conversation: SidekickConversation
    let coordinator: CommandCoordinator
    @Bindable var presentation: SidekickPresentation
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduced: Bool { motionOverride ?? systemReduced }
    @State private var columnWidth: CGFloat = PageMetrics.readingColumn
    /// The reader's place, kept while Home is hidden behind another page (NAV-SPEC 6).
    @State private var place = SidekickTranscriptPlace()
    private static let contentSpace = "sidekick.transcript.content"
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
    /// The question the Ask bar's card is asking; while it waits there, the card is its one place.
    private var pendingQuestionID: String? {
        SidekickTranscriptLayout.pendingQuestion(presentation.rows, id: coordinator.run.recovery.content?.question?.id)
    }
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
        let pending = pendingQuestionID
        let display = SidekickTranscriptLayout.rows(presentation.rows.filter { $0.event.id != pending })
        let leaders = Self.runLeaders(display)
        let runID = coordinator.run.runID
        // A running task's work trails the rows until its own row shows it.
        let liveWork = !presentation.hasLater && coordinator.run.isRunning
            && !display.contains(where: { $0.showsWork && $0.record.event.taskID == runID })
        let lastItemID = liveWork ? "sidekick-live-work-\(runID)" : display.last?.id
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
                            SidekickMessageRow(record: row.record, showsWork: row.showsWork, timeBreak: row.timeBreak,
                                bubbleWidth: columnWidth * 0.75,
                                generation: generation, conversation: conversation, coordinator: coordinator,
                                presentation: presentation, active: active)
                        }
                        .padding(.top, leaders.contains(row.id) ? Space.l : Space.m)
                        // Content coordinates change only with layout, not on every scrolled frame.
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: { [place] frame in
                            place.rows[row.id] = frame
                        }
                        .id(row.id)
                        .transition(.opacity)
                    }
                    if presentation.hasLater {
                        pagingButton("Later Messages", symbol: "arrow.down") {
                            guard let last = presentation.rows.last else { return }
                            Task { await presentation.load(.later(last.sequence), conversation: conversation) }
                        }
                    } else if liveWork {
                        SidekickWorkDisclosure(conversation: conversation, taskID: runID,
                            state: presentation.taskStates[runID], presentation: presentation,
                            running: true, waiting: coordinator.run.recovery.isPending, active: active,
                            liveStatus: coordinator.run.statusLine)
                            .padding(.top, Space.m)
                    }
                    // The end marker is the column's bottom margin, so scrolling to it shows the last
                    // row's hover gutter above the Ask bar. (A 1 pt marker over a bottom padding left
                    // that margin under the bar, and the gutter's time and Copy on the bar's edge.)
                    Color.clear.frame(height: Space.m).id("sidekick-bottom")
                }
                .padding(.horizontal, Space.xl).padding(.top, Space.l)
                .frame(maxWidth: PageMetrics.readingColumn)
                .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * Space.xl } action: { columnWidth = max(200, $0) }
                .frame(maxWidth: .infinity)
                .scrollTargetLayout()
                .coordinateSpace(.named(Self.contentSpace))
            }
            // A conversation opens at its latest message, like Messages, before any scroll
            // request arrives (a newly built transcript no longer flashes its oldest rows).
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // A final response can acquire its activity height after the explicit scroll
            // request. Keep followers at the native bottom through those size changes;
            // deliberate history reading/selection keeps its existing viewport instead.
            .defaultScrollAnchor(presentation.canFollowLatest ? .bottom : nil, for: .sizeChanges)
            .onScrollGeometryChange(for: SidekickTranscriptPlace.Viewport.self) { geo in
                .init(top: geo.visibleRect.minY, height: geo.containerSize.height,
                      insetTop: geo.contentInsets.top, insetBottom: geo.contentInsets.bottom,
                      fromBottom: geo.contentSize.height - geo.visibleRect.maxY,
                      width: geo.containerSize.width, contentHeight: geo.contentSize.height)
            } action: { [place] old, viewport in
                place.viewport = viewport
                // A resize or a new inset keeps the content's offset. The reader at the end stays
                // there through it, while Home is hidden too, unless a gesture is under way. Any
                // change also settles a pin asked for at the previous one (it has landed, or the
                // reader moved).
                let keep = SidekickTranscriptPlace.Viewport.keepsEnd(from: old, to: viewport, pinPending: place.endPending)
                place.endPending = false
                if keep && !presentation.isScrolling { place.pinEnd(proxy) }
            }
            // Home stays mounted behind other pages. Leaving notes the reader's place; coming
            // back puts the transcript exactly there if anything moved it while it was hidden.
            .onChange(of: active) { _, isActive in
                if isActive { restorePlace(proxy, lastItemID: lastItemID) }
                else {
                    place.remember(order: display.map(\.id), lastItemID: lastItemID, generation: generation,
                                   scrollRequest: presentation.scrollRequest,
                                   following: presentation.canFollowLatest)
                }
            }
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
                var target = SidekickTranscriptLayout.destination(requestedTarget, records: presentation.rows)
                // The pending question has no row; the card asking it sits under the latest message.
                if target == pendingQuestionID { target = "sidekick-bottom" }
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

    /// Puts the transcript back where the reader left it when Home comes back. A destination
    /// chosen while Home was away (search, View in Chat, a notch reply) wins, and the reader's
    /// own scrolling ends the restore at once. `lastItemID` is the column's last item now.
    private func restorePlace(_ proxy: ScrollViewProxy, lastItemID: String?) {
        guard let saved = place.takeSaved(), saved.generation == presentation.generation,
              conversation.navigationRequest == nil, !presentation.searchShown,
              presentation.scrollRequest == saved.scrollRequest || presentation.scrollIsAutomatic else { return }
        let token = place.restoreToken
        let intent = presentation.readingIntentRevision
        let toEnd = saved.returnsToEnd(lastItemID: lastItemID, now: place.viewport)
        place.apply(saved, toEnd: toEnd, proxy: proxy)
        // Hidden rows can be re-measured as the page returns (width, safe areas, the Ask bar),
        // so check again once that layout has landed.
        Task { [place, presentation] in
            for pause in [40, 160, 420] {
                do { try await Task.sleep(for: .milliseconds(pause)) } catch { return }
                guard place.restoreToken == token, !presentation.isScrolling,
                      presentation.readingIntentRevision == intent,
                      presentation.scrollRequest == saved.scrollRequest || presentation.scrollIsAutomatic else { return }
                place.apply(saved, toEnd: toEnd, proxy: proxy)
            }
        }
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

/// Where the reader is in the transcript, measured without invalidating any view: the rows'
/// frames in content coordinates and the scroll viewport. `remember` notes the place when Home
/// is left; `apply` puts it back (the latest message, or the same row at the same height).
@MainActor final class SidekickTranscriptPlace {
    typealias Viewport = SidekickTranscriptLayout.Viewport
    typealias Saved = SidekickTranscriptLayout.SavedPlace
    /// The transcript's own "at the latest message" distance (see `onScrollGeometryChange`).
    static let latestDistance: CGFloat = 70
    var rows: [String: CGRect] = [:]
    var viewport = Viewport()
    /// A pin to the end asked for (pinEnd) and not yet followed by another viewport change. Until
    /// one comes, the reader counts as at the end, whichever of the page's updates runs first.
    var endPending = false
    private(set) var saved: Saved?
    /// Bumped whenever the place is noted again, which ends any restore still checking.
    private(set) var restoreToken = 0

    /// `following`: the reader follows the latest message (SidekickPresentation.canFollowLatest).
    /// Only then does "at the bottom" mean "the latest message"; a paused reader (text selected,
    /// paged history) keeps the same row instead, even if a reply arrives while Home is away, unless
    /// it was at the end and nothing new came (SavedPlace.returnsToEnd). `lastItemID`: the column's
    /// last item, a row or a live run's work.
    func remember(order: [String], lastItemID: String?, generation: UUID?, scrollRequest: Int, following: Bool) {
        restoreToken &+= 1
        lastAnchor = nil
        let ids = Set(order)
        rows = rows.filter { ids.contains($0.key) }
        guard viewport.height > 0 else { saved = nil; return }
        let visibleTop = viewport.top + viewport.insetTop
        let rowID = order.first { (rows[$0]?.maxY ?? -.infinity) > visibleTop }
        saved = Saved(atBottom: following && viewport.fromBottom < Self.latestDistance,
                      atEnd: viewport.atEnd || endPending, lastItemID: lastItemID, viewport: viewport, rowID: rowID,
                      rowTop: rowID.flatMap { rows[$0] }.map { $0.minY - viewport.top } ?? 0,
                      generation: generation, scrollRequest: scrollRequest)
    }

    func takeSaved() -> Saved? {
        defer { saved = nil }
        return saved
    }

    /// Scrolls back to `saved` without animation: to the end (`toEnd`, from Saved.returnsToEnd),
    /// or the same row at the same height.
    func apply(_ saved: Saved, toEnd: Bool, proxy: ScrollViewProxy) {
        if toEnd {
            // On every pass, even when the place looks right: a hidden page's measurements can lag
            // its first visible layout, and "near the end" (latestDistance) is not the end. Scrolling
            // to the end where it already is moves nothing.
            pinEnd(proxy)
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        guard let id = saved.rowID, let frame = rows[id], viewport.height > 0 else { return }
        let current = frame.minY - viewport.top
        guard abs(current - saved.rowTop) > 0.75 else { return }
        // scrollTo aligns the row's unit point with the same unit point of the visible area
        // (the viewport inside its insets): rowTop = insetTop + y * (visible - rowHeight).
        // A later pass corrects the previous anchor by what is still off.
        let span = viewport.height - viewport.insetTop - viewport.insetBottom - frame.height
        let y: CGFloat
        if abs(span) <= 1 { y = 0 }
        else if let last = lastAnchor, last.id == id { y = last.y + (saved.rowTop - current) / span }
        else { y = (saved.rowTop - viewport.insetTop) / span }
        lastAnchor = (id, y)
        withTransaction(instant) { proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: y)) }
    }
    private var lastAnchor: (id: String, y: CGFloat)?

    /// Puts the end marker on the Ask bar's edge at once, the last row's hover gutter above it.
    func pinEnd(_ proxy: ScrollViewProxy) {
        endPending = true
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo("sidekick-bottom", anchor: .bottom) }
    }
}

private struct SidekickMessageRow: View {
    let record: SidekickConversationStore.Record
    let showsWork: Bool
    /// The time separator drawn right above this message, if any.
    let timeBreak: Date?
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
    private struct ReadReceiptKey: Equatable {
        let generation: UUID?
        let messageID: String
        let visible: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if showsWork, SidekickWorkDisclosure.hasSummary(state: presentation.taskStates[event.taskID], running: running,
                                                            latestRun: coordinator.run.runID == event.taskID) {
                SidekickWorkDisclosure(conversation: conversation, taskID: event.taskID,
                    state: presentation.taskStates[event.taskID], presentation: presentation,
                    running: running, waiting: running && coordinator.run.recovery.isPending, active: active,
                    liveStatus: running ? coordinator.run.statusLine : "")
            }
            if event.kind == .taskFinished {
                if let status = standaloneStatus {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
                // Sentient's: unboxed document text on the column's leading edge, the same edge as
                // its work disclosure, tables and code. No avatar, like Messages and ChatGPT.
                VStack(alignment: .leading, spacing: Space.xs) {
                    replyReference
                    SidekickMarkdown(markdown: event.text, compact: event.messageKind == .update,
                        onReply: reply, onReplyToMessage: { reply(nil) },
                        onSelectionChange: { presentation.setSelection($0, messageID: event.id) })
                        .opacity(event.messageKind == .update ? 0.76 : 1)
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
                if let time = SidekickTranscriptLayout.hoverTime(event.createdAt, below: timeBreak) {
                    Text(time)
                        .font(.caption)
                        .help(event.createdAt.formatted(date: .complete, time: .shortened))
                }
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless).controlSize(.small)
                .help(copied ? "Copied" : "Copy message")
                .accessibilityLabel(copied ? "Copied" : "Copy message")
            }
            .foregroundStyle(.secondary)
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

/// Search results laid out like Mail's: per message, the sender and time, the request that began
/// its exchange (the subject line), then a plain-text snippet in secondary with each match in bold.
/// A click opens the transcript around that message. No selection binding, so arrow keys never
/// navigate.
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
                    Section {
                        ForEach(presentation.searchResults, id: \.event.id) { record in
                            Button {
                                presentation.search = ""; presentation.searchShown = false
                                Task { await presentation.load(.around(record.event.id), conversation: conversation) }
                            } label: { row(record) }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .help("Show in Conversation")
                        }
                    } header: {
                        // The search reads a bounded page, newest first: past it, say which ones these are.
                        if presentation.searchHasMore {
                            Text("\(presentation.searchResults.count) Most Recent Messages")
                        } else {
                            Text("^[\(presentation.searchResults.count) Message](inflect: true)")
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("sidekick.searchResults")
            }
        }
        // The page margin inside the reading column, as in the conversation and the Ask bar, so the
        // results share their edges (and the rows' text the Ask field's) at every window width.
        .padding(.horizontal, Space.xl)
        .centeredColumn()
    }

    private func row(_ record: SidekickConversationStore.Record) -> some View {
        let you = record.event.kind == .userMessage || record.event.kind == .answer
        // A request found by the search is its own subject; a reply shows what it answered.
        let request = record.event.kind == .userMessage ? nil : presentation.searchRequests[record.event.taskID]
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(you ? "You" : "Sentient").font(.headline)
                Spacer()
                Text(SidekickTranscriptLayout.hoverDate(record.event.createdAt))
                    .font(.caption).foregroundStyle(.secondary)
                    .help(record.event.createdAt.formatted(date: .complete, time: .shortened))
            }
            if let request {
                Text(SidekickTranscriptLayout.excerpt(request, query: "")).font(.subheadline).lineLimit(1)
            }
            Text(Self.snippet(record.event, query: presentation.search))
                .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
    }

    /// The words around the first match as the transcript shows them: Sentient's Markdown as text
    /// (never its syntax), your messages literally. Each case-insensitive match is bold and primary.
    static func snippet(_ event: SidekickConversationEvent, query: String) -> AttributedString {
        let rendered = event.kind == .assistantMessage || event.kind == .question
        let plain = rendered ? SidekickMarkdownCache.shared.document(event.text).plainText : event.text
        var result = AttributedString(SidekickTranscriptLayout.excerpt(plain, query: query))
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return result }
        var searchStart = result.startIndex
        while searchStart < result.endIndex,
              let match = result[searchStart...].range(of: needle, options: .caseInsensitive) {
            result[match].inlinePresentationIntent = .stronglyEmphasized
            result[match].foregroundColor = Color.primary
            searchStart = match.upperBound
        }
        return result
    }
}
