// Finish Setting Up: the inspector column Home shows while personal setup is pending, the
// in-column example page each feature row opens, the Today line that says Sidekick is ready, and
// the starter replies that end Today. The examples are local presentation only: they never
// create tasks or claim real results.
import SwiftUI

enum HomePersonalFeature: String, CaseIterable, Identifiable {
    case doubleTap, proactive, knowledge, sidekick
    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubleTap: "Double Tap"
        case .proactive: "Proactive Intelligence"
        case .knowledge: "Knowledge Base"
        case .sidekick: "Personal Sidekick"
        }
    }
    var detail: String {
        switch self {
        case .doubleTap: "Replies in your voice, in two taps."
        case .proactive: "Work prepared before you ask."
        case .knowledge: "Your projects, people, and commitments."
        case .sidekick: "Help that already knows your context."
        }
    }
    var symbol: String {
        switch self {
        case .doubleTap: "command"
        case .proactive: "sunrise"
        case .knowledge: "books.vertical"
        case .sidekick: "sparkles"
        }
    }
    /// The feature's tile (SPEC-00 2.5, Finish Setup feature rows).
    var tile: TileSpec {
        switch self {
        case .doubleTap: .featureDoubleTap
        case .proactive: .featureProactive
        case .knowledge: .featureKnowledge
        case .sidekick: .featureSidekick
        }
    }
}

/// The "Finish Setting Up" inspector: a grouped form with one row per feature (tile, title,
/// "See Example") and the one setup action at the bottom.
struct HomePersonalSetupPanel: View {
    /// The inspector's ideal width; HomeView sizes the column min 240 / ideal this / max 320.
    static let width: CGFloat = 260
    let selectedFeature: HomePersonalFeature?
    let emphasizeSetup: Bool
    let active: Bool
    var previewEnabled = true
    let onSelectFeature: (HomePersonalFeature) -> Void
    let onFinishSetup: () -> Void

    var body: some View {
        Form {
            Section {
                ForEach(HomePersonalFeature.allCases) { feature in
                    featureRow(feature)
                }
            } header: {
                Text("Finish setting up Sentient to unlock:")
                    .textCase(nil)
            } footer: {
                if emphasizeSetup {
                    Text("Your first task is done. Add your context next.")
                }
            }
            Section {
                Button(action: onFinishSetup) {
                    Text("Finish Setup…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("personalSetup.finish")
                .accessibilityHint("Connect three sources to build your personal context")
            }
        }
        .formStyle(.grouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personalSetup.panel")
    }

    private func featureRow(_ feature: HomePersonalFeature) -> some View {
        let selected = selectedFeature == feature
        return HStack(alignment: .top, spacing: Space.m) {
            IconTile(feature.tile, size: 30)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(feature.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                Button("See Example") { onSelectFeature(feature) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!previewEnabled)
                    .help(previewEnabled ? "Show an example" : "Examples are available after your current task")
                    .accessibilityLabel(feature.title + ". " + feature.detail)
                    .accessibilityValue(selected ? "Example open" : "Example closed")
                    .accessibilityHint("Show an example without sending a request")
                    .accessibilityIdentifier("personalSetup.feature." + feature.rawValue)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xs)
        .listRowBackground(selected ? Color.accentColor.opacity(0.12) : nil)
    }
}

/// Today's line once Sidekick can take requests. `compact` is kept for the init and ignored.
struct HomeSidekickInvitation: View {
    var compact = false

    var body: some View {
        Text("Sidekick is ready now. Ask it anything.")
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("sidekick.readyInvitation")
    }
}

/// The starters that end Today, like Messages' suggested replies: capsule buttons that fill the
/// draft and never send.
struct HomeSidekickSuggestions: View {
    struct Suggestion: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let prompt: String
    }
    static let suggestions = [
        Suggestion(id: "summarize", title: "Summarize a page", symbol: "doc.text",
                   prompt: "Summarize the page I’m looking at. Highlight the key takeaways and any next steps."),
        Suggestion(id: "compare", title: "Compare tools", symbol: "rectangle.split.2x1",
                   prompt: "Help me compare [tool A] and [tool B] for [use case]. Find pricing and the key trade-offs."),
        Suggestion(id: "research", title: "Research a company", symbol: "magnifyingglass",
                   prompt: "Research [company] and give me a concise brief on its product, customers, and competitors."),
        Suggestion(id: "tasks", title: "Turn notes into tasks", symbol: "checklist",
                   prompt: "Turn these notes into a clear task list with priorities: [paste notes]")
    ]
    let onSelect: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) {
                ForEach(Self.suggestions) { suggestion in
                    chip(suggestion).fixedSize()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s, alignment: .leading),
                                GridItem(.flexible(), spacing: Space.s, alignment: .leading)],
                      alignment: .leading, spacing: Space.s) {
                ForEach(Self.suggestions) { suggestion in
                    chip(suggestion)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Try Sidekick")
    }

    private func chip(_ suggestion: Suggestion) -> some View {
        Button { onSelect(suggestion.prompt) } label: {
            Label(suggestion.title, systemImage: suggestion.symbol)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier("sidekick.suggestion." + suggestion.id)
        .accessibilityHint("Fill the message box; review before sending")
    }
}

/// A feature's example as an in-column drill-in, like a System Settings sub-pane: a Back chevron
/// at the top left, the feature's title, then the interactive showcase. The Ask bar stays below.
struct HomePersonalFeaturePreview: View {
    let feature: HomePersonalFeature
    let onClose: () -> Void
    var isActive = true
    var availableHeight: CGFloat = 520
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var pageRevision = 0
    @State private var headerHeight: CGFloat = 53
    private var reducedMotion: Bool { motionOverride ?? systemReducedMotion }

    var body: some View {
        GeometryReader { geometry in
            let column = min(geometry.size.width, PageMetrics.readingColumn)
            VStack(alignment: .leading, spacing: 0) {
                header
                    .frame(maxWidth: PageMetrics.readingColumn, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        example(width: max(1, column - Space.xl * 2))
                            .padding(.horizontal, Space.xl)
                            .padding(.vertical, Space.l)
                            .frame(maxWidth: PageMetrics.readingColumn, alignment: .leading)
                            .frame(maxWidth: .infinity)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                onContentHeightChange($0 + headerHeight + 1)   // the header and its divider
                            }
                            .id("showcase-top")
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: pageRevision) { _, _ in
                        proxy.scrollTo("showcase-top", anchor: .top)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personalSetup.preview." + feature.rawValue)
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            Button(action: onClose) {
                Label("Back", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Close example (Escape)")
            .accessibilityLabel("Close " + feature.title + " example")
            .accessibilityIdentifier("personalSetup.preview.close")
            IconTile(feature.tile, size: 20)
            Text(feature.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: Space.s)
            Text("Example")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.l)
    }

    @ViewBuilder private func example(width: CGFloat) -> some View {
        switch feature {
        case .doubleTap:
            HomeDoubleTapShowcase(reducedMotion: reducedMotion, compact: width < 430)
        case .proactive:
            HomeProactiveShowcase(width: width, reducedMotion: reducedMotion, onNavigate: { pageRevision &+= 1 })
        case .knowledge:
            HomeKnowledgeShowcase(reducedMotion: reducedMotion, compact: width < 430, isActive: isActive,
                                  availableHeight: max(0, availableHeight - 95),
                                  onNavigate: { pageRevision &+= 1 }, onClose: onClose)
        case .sidekick:
            HomeSidekickShowcase(reducedMotion: reducedMotion, compact: width < 430, onNavigate: { pageRevision &+= 1 })
        }
    }
}

#if DEBUG
#Preview("Finish Setting Up inspector") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            HomePersonalSetupPanel(selectedFeature: .knowledge, emphasizeSetup: true, active: false,
                                   onSelectFeature: { _ in }, onFinishSetup: {})
                .frame(width: HomePersonalSetupPanel.width, height: 520)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Today line and starters") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(alignment: .leading, spacing: Space.l) {
                HomeSidekickInvitation()
                HomeSidekickSuggestions { _ in }
            }
            .padding(Space.xl)
            .frame(width: 680)
            .background(Color(nsColor: .textBackgroundColor))
            .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Double Tap example") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            HomePersonalFeaturePreview(feature: .doubleTap, onClose: {})
                .frame(width: 620, height: 480)
                .background(Color(nsColor: .textBackgroundColor))
                .environment(\.colorScheme, scheme)
        }
    }
}
#endif
