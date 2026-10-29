import AppKit
import Combine
import SwiftUI

/// Inline task history. Only an expanded section reads activity; a bounded page keeps a
/// months-old conversation as inexpensive to render as a new one.
struct SidekickWorkDisclosure: View {
    let conversation: SidekickConversation
    let taskID: UUID
    let state: SidekickConversationStore.TranscriptTaskState?
    let presentation: SidekickPresentation
    var running = false
    var waiting = false
    var active = false
    var liveStatus = ""
    @State private var visible = false
    private var expanded: Bool { presentation.expandedWorkTasks.contains(taskID) }
    @State private var records: [SidekickConversationStore.Record] = []
    @State private var steps: [SidekickActivityPresentation.Step] = []
    private typealias Page = SidekickPresentation.WorkPage
    @State private var earlier = false
    private var currentPage: Page { presentation.workPage(taskID) ?? (running ? .latest : .after(0)) }
    private func selectPage(_ page: Page) { presentation.setWorkPage(page, taskID: taskID) }
    @State private var more = false
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var failed = false
    @State private var activityHeight: CGFloat = 0
    @State private var revision = 0
    @State private var loadToken = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduced: Bool { motionOverride ?? systemReduced }
    private var canExpand: Bool { running || state?.hasActivity == true || !steps.isEmpty || failureDescription != nil || failed }
    private var revealed: Bool { expanded && canExpand }
    private var progressNote: String? {
        guard running, !waiting, let note = SidekickTranscriptLayout.progressNote(liveStatus) else { return nil }
        let latest = conversation.messages.last { $0.event.taskID == taskID && $0.event.kind == .assistantMessage }
        return latest?.event.text.trimmingCharacters(in: .whitespacesAndNewlines) == note ? nil : note
    }
    private var failureDescription: String? {
        guard let ending = state?.finished?.event, ending.outcome == .failed || ending.outcome == .interrupted else { return nil }
        let text = ending.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    private struct LoadKey: Equatable {
        let task: UUID
        let generation: UUID?
        let expanded: Bool
        let revision: Int
        let page: Page
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if running && active && visible {
                TimelineView(.periodic(from: .now, by: 1)) { header(at: $0.date) }
            } else { header(at: Date()) }
            activityViewport
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
        .task(id: LoadKey(task: taskID, generation: conversation.generation, expanded: expanded, revision: revision, page: currentPage)) {
            guard expanded else { return }
            await load()
        }
        .onChange(of: presentation.readingIntentRevision) { _, _ in
            // Freeze the existing visible window as soon as the reader takes control.
            // Future commits can update its statuses without pushing its first rows away.
            if running, hasLoaded, currentPage == .latest, !presentation.canFollowLatest,
               let first = records.first {
                selectPage(.after(max(0, first.sequence - 1)))
            }
        }
        .onChange(of: presentation.canFollowLatest) { _, follows in
            if follows, running, !presentation.isBrowsingWork(taskID), currentPage != .latest {
                selectPage(.latest)
            }
        }
        .onChange(of: presentation.latestWorkPageRevision) { _, _ in
            if running { selectPage(.latest); revision &+= 1 }
        }
        .onChange(of: progressNote) { _, _ in
            guard running, active else { return }
            presentation.activityDidChange(taskID: taskID, generation: conversation.generation,
                                           intent: presentation.readingIntentRevision)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sidekickConversationChanged)
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)) { notification in
            guard expanded, let store = notification.object as? SidekickConversationStore,
                  store === conversation.store else { return }
            revision &+= 1
        }
    }

    /// Keep the bounded, previously loaded rows mounted so collapsing does not discard their
    /// detail disclosures or scroll positions. Reveal a viewport below the header, never move
    /// the rows through it. Measuring before the zero-height frame preserves intrinsic sizing.
    private var activityViewport: some View {
        activity
            .padding(.top, Space.s).padding(.bottom, Space.xs)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { max(0, ceil($0.size.height)) } action: { height in
                guard height.isFinite, abs(height - activityHeight) > 0.5 else { return }
                activityHeight = height
            }
            .frame(height: revealed ? activityHeight : 0, alignment: .top)
            .clipped()
            // A first asynchronous page or a nested detail changes the measured height. Give
            // that resize its own animation instead of snapping from the loading placeholder.
            // During live following, publish the real tail geometry immediately; the
            // transcript's scroll supplies the motion. Two concurrent height/scroll
            // animations otherwise leave the newest row below a transitional frame.
            .animation(reduced || (running && active && presentation.canFollowLatest)
                ? nil : Motion.gated(.easeInOut(duration: 0.24), reduceMotion: reduced), value: activityHeight)
            .animation(Motion.gated(.spring(response: 0.35, dampingFraction: 0.92), reduceMotion: reduced), value: expanded)
            .opacity(revealed ? 1 : 0)
            .animation(Motion.gated(.easeOut(duration: 0.14), reduceMotion: reduced), value: expanded)
            .disabled(!revealed)
            .allowsHitTesting(revealed)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(!revealed)
    }

    /// A native disclosure row: leading chevron, a real state glyph, and the work title.
    /// Not a DisclosureGroup, because the collapsed activity must stay mounted and measured
    /// (the transcript follows its geometry).
    @ViewBuilder private func header(at date: Date) -> some View {
        let title = SidekickTranscriptLayout.workLabel(state: state, running: running, waiting: waiting, now: date)
        let row = HStack(spacing: Space.s) {
            if canExpand {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10)
            }
            headerGlyph.frame(width: 16, height: 16)
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.contentShape(Rectangle())
        if canExpand {
            Button {
                withAnimation(Motion.gated(.spring(response: 0.35, dampingFraction: 0.92), reduceMotion: reduced)) {
                    presentation.toggleWork(taskID)
                }
            } label: { row }
            .buttonStyle(.borderless)
            .help(expanded ? "Hide Recorded Activity" : "Show Recorded Activity")
            .accessibilityLabel(title + (expanded ? ", hide activity" : ", show activity"))
            .accessibilityIdentifier("sidekick.work.\(taskID.uuidString)")
        } else {
            row
        }
    }

    @ViewBuilder private var headerGlyph: some View {
        if running && !waiting {
            ProgressView().controlSize(.mini)
        } else if let tone = headerTone, let symbol = tone.symbol {
            Image(systemName: symbol).foregroundStyle(tone.color)
                .accessibilityLabel(tone.accessibilityLabel)
        }
    }

    private var headerTone: StatusTone? {
        if waiting { return .info }
        return switch state?.finished?.event.outcome {
        case .success: .ok
        case .failed: .error
        case .stopped, .interrupted: .off
        case nil: nil
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let failureDescription {
                Text(String(failureDescription.prefix(800))).font(.callout)
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progressNote {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    ProgressView().controlSize(.mini)
                    Text(progressNote).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sidekick.liveProgress")
                }
                .font(.callout).foregroundStyle(.secondary)
            } else if running && steps.isEmpty && !failed {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.mini)
                    Text(waiting ? "Waiting for your answer…" : "Thinking…")
                        .accessibilityIdentifier("sidekick.thinking")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            if steps.isEmpty && (failed || (!running && (loading || !hasLoaded))) {
                HStack(spacing: Space.s) {
                    if failed {
                        StatusLabel("Activity couldn’t be loaded.", tone: .error)
                        Button("Try Again") { revision &+= 1 }
                            .buttonStyle(.borderless).controlSize(.small)
                    } else {
                        if expanded { ProgressView().controlSize(.mini) }
                        Text("Loading activity…").font(.callout).foregroundStyle(.secondary)
                    }
                }.frame(minHeight: 16)
            }
            ForEach(steps) { step in
                SidekickActivityRow(step: step, running: running)
            }
            if earlier || more || (running && currentPage != .latest) {
                HStack(spacing: Space.m) {
                    if earlier {
                        Button("Earlier Steps") {
                            guard let first = records.first else { return }
                            presentation.browseWork(taskID); selectPage(.before(first.sequence))
                        }
                    }
                    if more {
                        Button("Next Steps") {
                            guard let last = records.last else { return }
                            presentation.browseWork(taskID); selectPage(.after(last.sequence))
                        }
                    }
                    if running && currentPage != .latest {
                        Button("Latest Steps") {
                            presentation.followLatestWork(taskID); selectPage(.latest)
                        }
                    }
                    if expanded && loading { ProgressView().controlSize(.mini) }
                }
                .buttonStyle(.borderless).controlSize(.small)
                .disabled(loading)
            }
            if failed && !steps.isEmpty {
                HStack(spacing: Space.s) {
                    StatusLabel("Couldn’t refresh activity.", tone: .warning)
                    Button("Try Again") { revision &+= 1 }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
        }
        // Step glyphs line up under the header's state glyph (past the chevron and its spacing).
        .padding(.leading, 22)
        .accessibilityIdentifier("sidekick.activity.\(taskID.uuidString)")
        .id(SidekickPresentation.workTailID(taskID))
    }

    private func load() async {
        guard let store = conversation.store, let generation = conversation.generation else {
            failed = true
            return
        }
        loadToken &+= 1
        let token = loadToken, requestedPage = currentPage
        let intent = presentation.readingIntentRevision
        let following = running && active && requestedPage == .latest && presentation.canFollowLatest
        loading = true
        defer { if loadToken == token { loading = false } }
        do {
            let (result, projected) = try await Task.detached(priority: .userInitiated) {
                let result: SidekickConversationStore.TranscriptPage
                switch requestedPage {
                case .latest: result = try store.activityPage(taskID: taskID)
                case .before(let cursor): result = try store.activityPage(taskID: taskID, before: cursor)
                case .after(let cursor): result = try store.activityPage(taskID: taskID, after: cursor)
                }
                return (result, SidekickActivityPresentation.steps(result.records))
            }.value
            guard !Task.isCancelled, token == loadToken, conversation.generation == generation,
                  result.generation == generation else { return }
            if requestedPage == .latest, hasLoaded, intent != presentation.readingIntentRevision,
               !presentation.canFollowLatest, let first = records.first {
                selectPage(.after(max(0, first.sequence - 1)))
                return
            }
            let changed = records != result.records
            if changed { records = result.records; steps = projected }
            earlier = result.hasEarlier; more = result.hasLater
            if requestedPage == .latest, !presentation.canFollowLatest, let first = records.first {
                selectPage(.after(max(0, first.sequence - 1)))
            } else { selectPage(requestedPage) }
            failed = false; hasLoaded = true
            if changed && following {
                presentation.activityDidChange(taskID: taskID, generation: generation, intent: intent)
            }
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, token == loadToken, conversation.generation == generation else { return }
            failed = true; SidekickDiagnostics.failure(.historyRead, reason: .readFailed)
        }
    }
}

/// A Reminders-style checklist row: state glyph, the app's real icon, title over app name, and a
/// trailing status tag. "Details" opens the raw tool call in monospaced inset boxes.
private struct SidekickActivityRow: View {
    let step: SidekickActivityPresentation.Step
    let running: Bool
    @State private var details = false
    private var status: SidekickConversationEvent.Activity.Status? { step.record.event.activity?.status }

    var body: some View {
        DisclosureGroup(isExpanded: $details) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(step.record.event.activity?.name ?? "Activity")
                    .font(.caption.monospaced())
                if let activity = step.record.event.activity {
                    Text(activity.status.rawValue.capitalized).font(.caption)
                    if let arguments = activity.arguments { detail(arguments) }
                    if let result = activity.result { detail(result) }
                }
            }
            .foregroundStyle(.secondary).padding(.vertical, Space.xs)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                glyph.frame(width: 16, height: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                SidekickActivityIcon(identifier: step.appIdentifier, symbol: step.symbol)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title).font(.subheadline)
                    if let app = step.appName, !step.title.localizedCaseInsensitiveContains(app) {
                        Text(app).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Space.s)
                if let tag { Text(tag).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .tint(.secondary)
        .accessibilityIdentifier("sidekick.activityStep." + step.id)
    }

    @ViewBuilder private var glyph: some View {
        switch status {
        case .completed: toneGlyph(.ok)
        case .failed: toneGlyph(.error)
        case .interrupted: toneGlyph(.off)
        case .started: if running { ProgressView().controlSize(.mini) } else { toneGlyph(.off) }
        case nil: EmptyView()
        }
    }

    private func toneGlyph(_ tone: StatusTone) -> some View {
        Image(systemName: tone.symbol ?? "circle").foregroundStyle(tone.color)
            .accessibilityLabel(tone.accessibilityLabel)
    }

    private var tag: String? {
        switch status {
        case .failed: "Step incomplete"
        case .interrupted: "Not confirmed"
        case .started: "Started"
        case .completed, nil: nil
        }
    }

    private func detail(_ text: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text).font(.caption.monospaced())
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180).padding(Space.s)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
    }
}

/// The real application icon at 16 pt (Finder, Spotlight), or an SF Symbol where no app applies.
/// The symbol inherits the caller's foreground style, so it reads the same in the always-dark notch.
struct SidekickActivityIcon: View {
    let identifier: String?
    let symbol: String
    var body: some View {
        Group {
            if let image = Self.icon(identifier) {
                Image(nsImage: image).resizable().scaledToFit()
            } else { Image(systemName: symbol).font(.callout) }
        }.frame(width: 16, height: 16).accessibilityHidden(true)
    }

    /// Shares the app-wide icon cache with every other real-icon surface.
    private static func icon(_ identifier: String?) -> NSImage? {
        guard let identifier else { return nil }
        if identifier.hasPrefix("/"), identifier.lowercased().hasSuffix(".app") {
            return FileManager.default.fileExists(atPath: identifier) ? AppIconCache.image(forFile: identifier) : nil
        }
        return AppIconCache.image(bundleID: identifier)
    }
}
