// The optional personal-context invitation lives beside the working Sidekick surface.
// These examples are local presentation only: they never create tasks or claim real results.
import SwiftUI

enum HomePersonalFeature: String, CaseIterable, Identifiable {
    case doubleTap, proactive, knowledge, sidekick
    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubleTap: "Double Tap"
        case .proactive: "Proactive Intelligence"
        case .knowledge: "Knowledge base"
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
}

struct HomePersonalSetupPanel: View {
    static let width: CGFloat = 360
    let selectedFeature: HomePersonalFeature?
    let emphasizeSetup: Bool
    let active: Bool
    var previewEnabled = true
    let onSelectFeature: (HomePersonalFeature) -> Void
    let onFinishSetup: () -> Void
    @State private var hoveredFeature: HomePersonalFeature?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Finish Sentient Setup to unlock:")
                .font(.title.weight(.medium))
                .foregroundStyle(SidekickStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            ForEach(HomePersonalFeature.allCases) { feature in
                featureButton(feature)
                Rectangle().fill(.quinary).frame(height: 1)
            }

            // The rewards lead directly to the one setup action.
            Button(action: onFinishSetup) {
                HStack(spacing: 16) {
                    Text("Finish setup").font(.body.weight(.medium))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").font(.callout.weight(.medium))
                }
                .foregroundStyle(Color(white: 0.08))
                .padding(.horizontal, 17).frame(height: 46)
                .background(.white, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(SidekickPressStyle())
            .background(GlowHalo(active: emphasizeSetup, intensity: 0.27, period: 12, animating: active))
            .padding(.top, 20)
            .accessibilityIdentifier("personalSetup.finish")
            .accessibilityHint("Connect three sources to build your personal context")
        }
        .padding(26)
        .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
            .strokeBorder(Theme.stroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personalSetup.panel")
    }

    private func featureButton(_ feature: HomePersonalFeature) -> some View {
        let selected = selectedFeature == feature
        let fillOpacity: Double = selected ? 0.045 : (previewEnabled && hoveredFeature == feature ? 0.025 : 0)
        return Button { onSelectFeature(feature) } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: feature.symbol)
                    .font(.body.weight(.medium))
                    .frame(width: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title).font(.body.weight(.medium))
                        .foregroundStyle(SidekickStyle.ink)
                    Text(feature.detail).font(.body)
                        .foregroundStyle(SidekickStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.medium)).padding(.top, 4)
            }
            .foregroundStyle(selected ? SidekickStyle.ink : SidekickStyle.secondary)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(fillOpacity),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(selected ? 0.08 : 0), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        // Outset the button, not its text: every row keeps the same alignment, with
        // a real clickable gutter around the icon and disclosure arrow.
        .padding(.horizontal, -12).padding(.vertical, 3)
        .onHover { hovering in
            if hovering { hoveredFeature = feature }
            else if hoveredFeature == feature { hoveredFeature = nil }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredFeature)
        .animation(.easeOut(duration: 0.12), value: selectedFeature)
        .disabled(!previewEnabled)
        .help(previewEnabled ? "Show an example" : "Examples are available after your current task")
        .accessibilityLabel(feature.title + ". " + feature.detail)
        .accessibilityValue(selected ? "Example open" : "Example closed")
        .accessibilityHint("Show an example without sending a request")
        .accessibilityIdentifier("personalSetup.feature." + feature.rawValue)
    }
}

struct HomeSidekickInvitation: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sidekick is ready.")
                .font(.system(size: compact ? 30 : 34, weight: .medium))
                .foregroundStyle(SidekickStyle.ink)
            Text("What can I take off your hands?")
                .font(.system(size: compact ? 24 : 27, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sidekick.readyInvitation")
    }
}

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
            HStack(spacing: 7) {
                ForEach(Self.suggestions) { suggestion in suggestionButton(suggestion).fixedSize(horizontal: true, vertical: false) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                ForEach(Self.suggestions) { suggestion in suggestionButton(suggestion) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Try Sidekick")
    }

    private func suggestionButton(_ suggestion: Suggestion) -> some View {
        Button { onSelect(suggestion.prompt) } label: {
            HStack(spacing: 7) {
                Image(systemName: suggestion.symbol).font(.callout)
                Text(suggestion.title).font(.subheadline).lineLimit(1)
            }
            .foregroundStyle(SidekickStyle.secondary)
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 43)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(SidekickPressStyle())
        .accessibilityIdentifier("sidekick.suggestion." + suggestion.id)
        .accessibilityHint("Fill the message box; review before sending")
    }
}

struct HomePersonalFeaturePreview: View {
    let feature: HomePersonalFeature
    let onClose: () -> Void
    var isActive = true
    var availableHeight: CGFloat = 520
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var pageRevision = 0
    private var reducedMotion: Bool { motionOverride ?? systemReducedMotion }

    var body: some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.subheadline.weight(.medium))
                        .foregroundStyle(SidekickStyle.secondary)
                        .frame(width: 30, height: 30)
                        .background(.quinary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close example (Escape)")
                .accessibilityLabel("Close " + feature.title + " example")
                .accessibilityIdentifier("personalSetup.preview.close")
                Text(feature.title).font(.body.weight(.medium))
                    .foregroundStyle(SidekickStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("EXAMPLE").font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(SidekickStyle.secondary)
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            Rectangle().fill(.quinary).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    example(width: max(1, geometry.size.width - 40))
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            onContentHeightChange($0 + 55) // fixed close/title row and hairline
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
        .background(Color(white: 0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personalSetup.preview." + feature.rawValue)
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
#Preview("Personal setup reward panel") {
    HomePersonalSetupPanel(selectedFeature: nil, emphasizeSetup: false, active: false,
                           onSelectFeature: { _ in }, onFinishSetup: {})
        .frame(width: HomePersonalSetupPanel.width).padding(30).background(SidekickStyle.base).preferredColorScheme(.dark)
}

#Preview("Personal setup Double Tap example") {
    HomePersonalFeaturePreview(feature: .doubleTap, onClose: {})
        .frame(width: 580, height: 360).padding(30).background(SidekickStyle.base).preferredColorScheme(.dark)
}
#endif
