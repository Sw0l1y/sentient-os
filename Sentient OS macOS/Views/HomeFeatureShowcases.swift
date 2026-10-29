// Small, interactive product examples for the Finish Setting Up previews. Each one previews the
// real surface it advertises (Today's rows, keycaps over a reply box, the graph, a chat turn).
// Every interaction changes local presentation only: synthetic content stays out of the
// conversation, sources, clipboard and task coordinator.
import SwiftUI
import AppKit

// MARK: - Proactive Intelligence (pattern: the Today list itself)

struct HomeProactiveShowcase: View {
    let width: CGFloat
    let reducedMotion: Bool
    let onNavigate: () -> Void
    @State private var opened: Example?

    private enum Example: String, CaseIterable, Identifiable {
        case followup, renewal
        var id: String { rawValue }
        var briefing: Briefing {
            switch self {
            case .followup:
                Briefing(id: "setup-example-followup", kind: .promise,
                    kicker: "Follow-up · Draft ready", title: "You ghosted Alex.",
                    body: "Your pilot notes are now a concise follow-up, with the SSO question included.",
                    offer: "Read the draft")
            case .renewal:
                Briefing(id: "setup-example-renewal", kind: .deadline,
                    kicker: "Renews tomorrow · $149", title: "That analytics trial is about to renew.",
                    body: "Your trial notes say Pulse wasn’t a fit. A cancellation plan is ready to review.",
                    offer: "Review the plan")
            }
        }
        var kind: String { self == .followup ? "Draft follow-up" : "Cancellation plan" }
        var heading: String { self == .followup ? "Northstar: next steps" : "Before Pulse renews" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let opened {
                ShowcaseBackButton(title: "Back to Your Cards", identifier: "personalSetup.proactive.back") {
                    change { self.opened = nil }
                }
                detail(opened)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("personalSetup.proactive.detail." + opened.rawValue)
                    .transition(.opacity)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Prepared overnight")
                        .font(.headline)
                    Spacer()
                    Text("2 ready")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HomeInsetGroup {
                    ForEach(Example.allCases) { example in
                        if example != Example.allCases.first {
                            Divider().padding(.leading, 30 + Space.m + Space.l)
                        }
                        HomeSuggestionRow(briefing: example.briefing, action: nil, phase: .offer,
                                          onOpen: { change { opened = example } },
                                          onOffer: { change { opened = example } },
                                          onOpenEnvelope: {},
                                          titleLineLimit: 3, previewLineLimit: 4)
                    }
                }
                .frame(maxWidth: width, alignment: .leading)
                Text("Sentient prepares the work. You decide what happens next.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A small letter-sheet layout: the tile and kind, the heading, the draft or plan, its sources.
    @ViewBuilder private func detail(_ example: Example) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .center, spacing: Space.m) {
                HomeSuggestionTile(briefing: example.briefing, action: nil, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.kind)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(example.heading)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }
            }
            if example == .followup {
                HomeInsetGroup {
                    VStack(alignment: .leading, spacing: Space.s) {
                        LabeledContent("To", value: "Alex Chen")
                        LabeledContent("Subject", value: "Northstar: next steps")
                        Divider()
                        Text("Hey Alex,\n\nHere’s the rollout plan: security review Thursday, then the wider team on Friday. I’ll send the SSO checklist ahead of the review.\n\nCould you confirm who should join from your side?")
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.l)
                }
                ShowcaseSources(first: "Alex’s email", firstSymbol: "envelope", second: "Pilot notes", secondSymbol: "doc.text")
            } else {
                HomeInsetGroup {
                    VStack(alignment: .leading, spacing: Space.m) {
                        LabeledContent("Renewal") {
                            Text("$149 / month, starting tomorrow").monospacedDigit()
                        }
                        Divider()
                        ShowcaseStep(number: 1, title: "Confirm the workspace", detail: "Check the plan and renewal date in billing.")
                        ShowcaseStep(number: 2, title: "Cancel the renewal", detail: "Keep access until the trial ends.")
                        ShowcaseStep(number: 3, title: "Save the confirmation", detail: "Bring the result back for you to review.")
                    }
                    .padding(Space.l)
                }
                ShowcaseSources(first: "Billing email", firstSymbol: "envelope", second: "Trial notes", secondSymbol: "doc.text")
            }
            Label("Nothing is sent or changed without your approval.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func change(_ update: () -> Void) {
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reducedMotion)) {
            update()
            onNavigate()
        }
    }
}

// MARK: - Double Tap (pattern: Mail compose with a QuickType-style draft)

struct HomeDoubleTapShowcase: View {
    let reducedMotion: Bool
    let compact: Bool
    @State private var replay = 0
    @State private var draftVisible = true
    @State private var pressedKey = 0
    @State private var replaying = false
    @Environment(\.pixelLength) private var pixelLength
    private let draft = "Hey Alex, yes, let’s expand the pilot. I’ll send the SSO checklist before Thursday’s review; we’re still on track for Friday."
    private var key: ShortcutKey { ShortcutPreferences.current }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Space.m : Space.l) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                if !compact {
                    Text("Northstar rollout")
                        .font(.headline)
                }
                Spacer(minLength: Space.s)
                Button {
                    if reducedMotion { draftVisible.toggle() }
                    else { replaying = true; replay &+= 1 }
                } label: {
                    Label(reducedMotion ? (draftVisible ? "Hide Draft" : "Show Draft") : "Replay",
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(replaying)
                .accessibilityIdentifier("personalSetup.doubleTap.replay")
            }

            keyboard

            HomeInsetGroup {
                HStack(alignment: .top, spacing: Space.m) {
                    Text("AC")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Alex Chen").font(.headline)
                            Spacer(minLength: Space.s)
                            Text("Northstar · To you")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text("Can we expand the pilot? What do you need from us before the rollout?")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Space.l)
                Divider()
                VStack(alignment: .leading, spacing: Space.s) {
                    Label("Your reply", systemImage: "arrowshape.turn.up.left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    replyField
                    if !compact {
                        ShowcaseSources(first: "Pilot notes", firstSymbol: "doc.text", second: "Thursday review", secondSymbol: "calendar")
                    }
                }
                .padding(Space.l)
            }

            if !compact {
                Text("Your voice, with the details you didn’t have to type.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: replay) {
            guard replay > 0, !reducedMotion else { return }
            defer { replaying = false; pressedKey = 0 }
            do {
                withAnimation(Motion.gated(.easeOut(duration: 0.12), reduceMotion: reducedMotion)) {
                    draftVisible = false; pressedKey = 1
                }
                try await Task.sleep(for: .milliseconds(140))
                pressedKey = 0
                try await Task.sleep(for: .milliseconds(100))
                pressedKey = 2
                try await Task.sleep(for: .milliseconds(160))
                try Task.checkCancellation()
                withAnimation(Motion.gated(Motion.standard, reduceMotion: reducedMotion)) { draftVisible = true }
            } catch { }
        }
    }

    /// The user's own keyboard row with the configured key lit; one cap when the column is narrow.
    @ViewBuilder private var keyboard: some View {
        Group {
            if compact {
                HStack(spacing: Space.s) {
                    KeyCap(key: key, pressed: pressedKey != 0, highlighted: true)
                    Text("× 2")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                KeyCapRow(highlighting: key, pressed: pressedKey != 0)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Two taps of " + key.spokenLabel)
    }

    private var replyField: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
        return ZStack(alignment: .topLeading) {
            // Reserve the finished reply's space so replay animates words, not layout.
            Text(draft).hidden().accessibilityHidden(true)
            if draftVisible {
                Text(draft)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("personalSetup.doubleTap.draft")
                    .transition(.opacity)
            } else {
                Text("Your reply…")
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
            }
        }
        .font(.body)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: compact ? 0 : 66, alignment: .topLeading)
        .padding(Space.m)
        .background(Color(nsColor: .textBackgroundColor), in: shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: pixelLength))
    }
}

// MARK: - Knowledge Base (pattern: a Freeform-style map with a note drill-in)

struct HomeKnowledgeShowcase: View {
    let reducedMotion: Bool
    let compact: Bool
    let isActive: Bool
    let availableHeight: CGFloat
    let onNavigate: () -> Void
    let onClose: () -> Void
    @StateObject private var sky = HomeKnowledgeShowcase.exampleSky()
    @State private var selectedURL: URL?
    @State private var viewport: CGSize = .zero
    @Environment(\.pixelLength) private var pixelLength

    private enum Note: String, CaseIterable, Identifiable {
        case project, person, commitment
        var id: String { rawValue }
        var title: String {
            switch self { case .project: "Northstar pilot"; case .person: "Alex Chen"; case .commitment: "Friday rollout" }
        }
        var shortTitle: String {
            switch self { case .project: "Northstar"; case .person: "Alex"; case .commitment: "Friday" }
        }
    }

    private static func exampleSky() -> NightSkyModel {
        let graph = SkyGraph.onboardingExample()
        return .preview(graph: graph, hovering: graph.nodes.firstIndex { $0.title == Note.project.title }, minimumZoom: 0.1)
    }
    private var selected: SkyNode? { sky.graph?.nodes.first { $0.url == selectedURL } }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Space.s : Space.m) {
            if let selected, let graph = sky.graph {
                ShowcaseBackButton(title: "Back to the Constellation", identifier: "personalSetup.knowledge.back") {
                    sky.highlight(selected.url)
                    navigate(to: nil)
                }
                note(selected, in: graph)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("personalSetup.knowledge.note." +
                        (Note.allCases.first { $0.title == selected.title }?.rawValue ?? "selected"))
            } else {
                constellation
            }
        }
    }

    @ViewBuilder private var constellation: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
        // Exactly the production graph view, model, simulation and renderer. No KnowledgeVault is
        // loaded and every URL stays in this sample. WP5 draws the graph; this only frames it.
        NightSkyView(vault: nil, model: sky,
                     animationsEnabled: isActive && !reducedMotion, showsHUD: false,
                     takesKeyboardFocus: false, onOpen: { navigate(to: $0) }, onExit: onClose)
            .frame(height: min(compact ? 188 : 320, max(96, availableHeight - (compact ? 38 : 66))))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: pixelLength))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                guard size.width > 0, size.height > 0, viewport != size else { return }
                viewport = size
                sky.fitToContent(in: size)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Example knowledge constellation")
            .accessibilityIdentifier("personalSetup.knowledge.sky")
        if !compact, let graph = sky.graph {
            Text("\(graph.nodes.count) notes · \(graph.domains.count) constellations · Hover, drag, or zoom")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        // Also a keyboard and VoiceOver route into the same sample notes.
        HStack(spacing: Space.s) {
            Text("Explore")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Note.allCases) { note in
                Button(note.shortTitle) {
                    if let node = sky.graph?.nodes.first(where: { $0.title == note.title }) { navigate(to: node.url) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Explore " + note.title)
                .accessibilityIdentifier("personalSetup.knowledge." + note.rawValue)
            }
        }
    }

    private func note(_ selected: SkyNode, in graph: SkyGraph) -> some View {
        HomeInsetGroup {
            VStack(alignment: .leading, spacing: compact ? Space.s : Space.m) {
                HStack(spacing: Space.s) {
                    Circle()
                        .fill(SkyRenderer.domainColor(selected.domain))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(selected.domain >= 0 ? graph.domains[selected.domain] : "Overview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(selected.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(selected.preview)
                    .font(.body)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let index = graph.nodes.firstIndex(where: { $0.url == selected.url }) {
                    let related = graph.adjacency[index].filter { !graph.nodes[$0].isRoot }.sorted {
                        let leftCrosses = graph.nodes[$0].domain != selected.domain
                        let rightCrosses = graph.nodes[$1].domain != selected.domain
                        return leftCrosses != rightCrosses ? leftCrosses : $0 < $1
                    }.prefix(3)
                    if !related.isEmpty {
                        Divider()
                        Text("Connected notes")
                            .font(.headline)
                        ForEach(Array(related), id: \.self) { index in
                            Button { navigate(to: graph.nodes[index].url) } label: {
                                Label(graph.nodes[index].title, systemImage: "link")
                                    .foregroundStyle(Color(nsColor: .linkColor))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(compact ? Space.m : Space.l)
        }
    }

    private func navigate(to url: URL?) {
        guard url == nil || sky.graph?.nodes.contains(where: { $0.url == url }) == true else { return }
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reducedMotion)) {
            selectedURL = url
            onNavigate()
        }
    }
}

// MARK: - Personal Sidekick (pattern: a Messages exchange)

struct HomeSidekickShowcase: View {
    let reducedMotion: Bool
    let compact: Bool
    let onNavigate: () -> Void
    @State private var briefOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Space.m : Space.l) {
            if briefOpen {
                ShowcaseBackButton(title: "Back to the Conversation", identifier: "personalSetup.sidekick.back") {
                    change { briefOpen = false }
                }
                HomeInsetGroup {
                    VStack(alignment: .leading, spacing: Space.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Call brief")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Northstar, in three points")
                                .font(.title3.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                        }
                        ShowcaseStep(number: 1, title: "The team wants to expand", detail: "Alex is ready to grow the pilot from 20 to 80 seats.")
                        ShowcaseStep(number: 2, title: "SSO is the open question", detail: "Confirm the identity provider and who owns the security review.")
                        ShowcaseStep(number: 3, title: "Keep Friday on track", detail: "Send the checklist before Thursday’s review, then confirm the rollout.")
                        ShowcaseSources(first: "Pilot notes", firstSymbol: "doc.text", second: "Alex’s email", secondSymbol: "envelope")
                    }
                    .padding(Space.l)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("personalSetup.sidekick.brief")
            } else {
                // Your turn: an accent bubble on the trailing side, as in Messages.
                Text("Prep me for tomorrow’s Northstar call.")
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                // Sidekick's turn: document text beside the brand mark, as in a Home conversation.
                HStack(alignment: .top, spacing: Space.s) {
                    BrandMarkView(size: 16)
                        .frame(width: 24, alignment: .leading)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: compact ? Space.s : Space.m) {
                        Text("Alex wants to expand the pilot. SSO is the last blocker, and you promised the checklist before Thursday’s review.")
                            .font(.body)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        if !compact {
                            ShowcaseSources(first: "Pilot notes", firstSymbol: "doc.text", second: "Alex’s email", secondSymbol: "envelope")
                        }
                        HomeInsetGroup {
                            HStack(spacing: Space.m) {
                                Image(systemName: "doc.text.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Northstar call brief").font(.headline)
                                    Text("3 talking points")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: Space.s)
                                Button("Open Brief") { change { briefOpen = true } }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .accessibilityIdentifier("personalSetup.sidekick.openBrief")
                            }
                            .padding(Space.m)
                        }
                    }
                }
            }
        }
    }

    private func change(_ update: () -> Void) {
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reducedMotion)) {
            update()
            onNavigate()
        }
    }
}

// MARK: - Shared pieces

/// Where an example's facts came from: a quiet footnote line, like a citation under an answer.
private struct ShowcaseSources: View {
    let first: String
    let firstSymbol: String
    let second: String
    let secondSymbol: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.m) { labels }
            VStack(alignment: .leading, spacing: Space.xs) { labels }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sources: " + first + ", " + second)
    }
    @ViewBuilder private var labels: some View {
        Text("Sources")
            .fontWeight(.semibold)
        Label(first, systemImage: firstSymbol).lineLimit(1)
        Label(second, systemImage: secondSymbol).lineLimit(1)
    }
}

/// An in-example Back, written as a link with a chevron.
private struct ShowcaseBackButton: View {
    let title: String
    let identifier: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.left")
        }
        .buttonStyle(.link)
        .accessibilityIdentifier(identifier)
    }
}

/// One numbered step of a plan or brief.
private struct ShowcaseStep: View {
    let number: Int
    let title: String
    let detail: String
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "\(number).circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityLabel("Step \(number)")
        }
    }
}

#if DEBUG
#Preview("Showcases") {
    HStack(alignment: .top, spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    HomeProactiveShowcase(width: 560, reducedMotion: true, onNavigate: {})
                    HomeDoubleTapShowcase(reducedMotion: true, compact: false)
                    HomeSidekickShowcase(reducedMotion: true, compact: false, onNavigate: {})
                }
                .padding(Space.xl)
            }
            .frame(width: 620, height: 900)
            .background(Color(nsColor: .textBackgroundColor))
            .environment(\.colorScheme, scheme)
        }
    }
}
#endif
