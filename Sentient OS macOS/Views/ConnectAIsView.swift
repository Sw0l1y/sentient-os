//
//  ConnectAIsView.swift
//  Sentient OS macOS
//
//  The "Connect your AIs" page — pushed from Settings → Give AIs Knowledge.
//   · sharing OFF → the consent ask in plain view: the trust pillars (encrypted storage,
//     open-source server, sharing controls), "Turn On Sharing" (enables the mirror + first push)
//     and "Not Now", which pops back to Settings.
//   · sharing ON → a segmented ChatGPT · Claude · Other AIs picker and a toolbar switch carrying
//     the last synced time (off goes through the confirm-and-delete alert). ChatGPT/Claude show
//     their GuideSpec's video steps side by side, each with a take-me-there link; the masked
//     link + Copy and MirrorClient.systemPrompt ride the cards; Other AIs is the compact pair.
//  Tutorial clips load from the bundle by name (connect-chatgpt-1.mp4, …); a missing file renders
//  a placeholder, so recordings can land later with no code change.
//

import SwiftUI
import AppKit
import AVFoundation

struct ConnectAIsView: View {
    private enum AITab: String, CaseIterable, Identifiable {
        case claude = "Claude"
        case chatgpt = "ChatGPT"
        case other = "Other AIs"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var tab: AITab = .claude
    @State private var enabled = false
    @State private var shareURL: String?
    @State private var loaded = false
    @State private var busy = false
    @State private var confirmOff = false
    @State private var errorLine: String?
    @State private var copiedLink = false
    @State private var copiedPrompt = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                if loaded {
                    if enabled { guide } else { consent }
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if loaded && enabled { sharingToggle }
            }
        }
        .frame(minWidth: 760, minHeight: 600)
        .task { await refresh() }
        .alert("Stop sharing your knowledge base?", isPresented: $confirmOff) {
            Button("Keep Sharing", role: .cancel) {}
            Button("Stop & Delete Cloud Copy", role: .destructive) { disconnect() }
        } message: {
            Text(PrivacyCopy.sharingOff)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text(enabled ? "Connect your AIs" : "Share your knowledge with your AIs?")
                .font(.title.weight(.semibold))
            Text(enabled
                 ? "Offer your knowledge base to ChatGPT, Claude, and every AI you use. Private, over MCP, in two steps."
                 : "Your knowledge base lives on this Mac. You can offer it to ChatGPT, Claude, and the other AIs you choose.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    // MARK: - Sharing off: the consent ask in plain view. Where the data goes (the same trust
    // pillars Settings shows), an explicit yes, and "Not Now", which goes back to Settings.

    private var consent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                veilPillar("lock.fill", PrivacyCopy.sharingEncryption)
                veilPillar("chevron.left.forwardslash.chevron.right", PrivacyCopy.sharingOpenSource)
                veilPillar("key.fill", PrivacyCopy.sharingControl)
            }
            .padding(16)
            .frame(width: 460, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 0.5))
            .padding(.top, 24)
            HStack(spacing: 10) {
                Button("Not Now") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                Button { connect() } label: {
                    if busy {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Connecting…") }
                    } else {
                        Text("Turn On Sharing")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(busy)
            }
            .controlSize(.large)
            .padding(.top, 24)
            if let errorLine {
                Text(errorLine)
                    .font(.callout).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 14)
            }
        }
    }

    /// One trust pillar on the veil (the same shape as Settings → Give AIs Knowledge's pillars,
    /// so the story reads identically wherever the user meets it).
    private func veilPillar(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(.green)
        }
    }

    // MARK: - Sharing on: the per-AI guide

    private var guide: some View {
        VStack(spacing: 0) {
            Picker("AI", selection: $tab) {
                ForEach(AITab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .padding(.top, 24)
            ZStack {
                switch tab {
                case .chatgpt: videoRow(Self.chatgptGuide)
                case .claude:  videoRow(Self.claudeGuide)
                case .other:   otherPair
                }
            }
            .padding(.top, 20)
            Text("Then ask it: \u{201C}What do you know about me?\u{201D}")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
        }
    }

    /// One card of an AI's guide: the take-me-there link above it, the video, the copy control.
    private struct GuideStep {
        enum Control { case none, link, prompt }
        let title: String
        let caption: String
        let linkLabel: String
        let linkURL: String
        let control: Control
    }

    /// One AI's guide: its cards in order (videos load as "<videoPrefix>-<n>.mp4"), at the
    /// recordings' own aspect so aspect-fill never crops.
    private struct GuideSpec {
        let name: String
        let videoPrefix: String
        let videoAspect: CGFloat
        let steps: [GuideStep]
    }

    private static let chatgptGuide = GuideSpec(
        name: "ChatGPT", videoPrefix: "connect-chatgpt", videoAspect: 996.0 / 1080.0,
        steps: [
            GuideStep(title: "Turn on developer mode",
                      caption: "Settings → Security and login → Developer mode, switch it on.",
                      linkLabel: "Open ChatGPT's security settings",
                      linkURL: "https://chatgpt.com/plugins#settings/Security",
                      control: .none),
            GuideStep(title: "Paste your private link",
                      caption: "Plugins → New Plugin: name it Sentient OS, paste your link as the Server URL, No Auth, then Create.",
                      linkLabel: "Open ChatGPT's plugins",
                      linkURL: "https://chatgpt.com/plugins#settings/Connectors?create-connector=true&redirectAfter=%2Fplugins",
                      control: .link),
            GuideStep(title: "Tell ChatGPT to use it",
                      caption: "Settings → Personalization → Custom instructions, then paste.",
                      linkLabel: "Open ChatGPT's instructions",
                      linkURL: "https://chatgpt.com/plugins#settings/Personalization",
                      control: .prompt),
        ])
    private static let claudeGuide = GuideSpec(
        name: "Claude", videoPrefix: "connect-claude", videoAspect: 916.0 / 1080.0,
        steps: [
            GuideStep(title: "Paste your private link",
                      caption: "Settings → Connectors → Add custom connector, then paste your link.",
                      linkLabel: "Open Claude's connectors",
                      linkURL: "https://claude.ai/new#settings/customize-connectors",
                      control: .link),
            GuideStep(title: "Tell Claude to use it",
                      caption: "Settings → General → Instructions for Claude, then paste.",
                      linkLabel: "Open Claude's instructions",
                      linkURL: "https://claude.ai/new#settings/general",
                      control: .prompt),
        ])

    /// ChatGPT / Claude: the guide's video steps side by side, a take-me-there link above each.
    private func videoRow(_ g: GuideSpec) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(g.steps.enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 12) {
                    StepLink(title: s.linkLabel, urlString: s.linkURL)
                    videoStep(i + 1, s.title, video: "\(g.videoPrefix)-\(i + 1)",
                              aspect: g.videoAspect, caption: s.caption) {
                        stepControl(s.control)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func stepControl(_ c: GuideStep.Control) -> some View {
        switch c {
        case .link:   linkRow
        case .prompt: promptButton
        case .none:   EmptyView()
        }
    }

    /// Other AIs: the same two steps, compact, no videos.
    private var otherPair: some View {
        VStack(spacing: 11) {
            step(1, "Copy your private link",
                 "Add it as a connector wherever your AI takes MCP servers.") { linkRow }
            step(2, "Tell your AI to use it",
                 "Paste this into its instructions so it checks your knowledge base.") { promptButton }
            Text("Works with any AI that speaks MCP.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
    }

    // MARK: - The two shared controls (every tab pastes the same two things)

    private var linkRow: some View {
        HStack(spacing: 8) {
            Text(MirrorClient.maskedURL(shareURL))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Button { copy(shareURL ?? "", flag: $copiedLink) } label: {
                Label(copiedLink ? "Copied" : "Copy Link", systemImage: copiedLink ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    private var promptButton: some View {
        Button { copy(MirrorClient.systemPrompt, flag: $copiedPrompt) } label: {
            Label(copiedPrompt ? "Copied" : "Copy Instructions", systemImage: copiedPrompt ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.bordered)
    }

    private func copy(_ text: String, flag: Binding<Bool>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flag.wrappedValue = true
        Task { try? await Task.sleep(for: .seconds(1.8)); flag.wrappedValue = false }
    }

    // MARK: - The step cards

    /// A video step (ChatGPT / Claude tabs): clip on top, whisper + title + controls + caption below.
    private func videoStep<Controls: View>(_ n: Int, _ title: String, video: String, aspect: CGFloat,
                                           caption: String,
                                           @ViewBuilder controls: () -> Controls) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StepVideo(resource: video, aspect: aspect)
            Text("Step \(n)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.top, 12)
            Text(title).font(.headline)
                .padding(.top, 2)
            controls().padding(.top, 10)
            Text(caption).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 0.5))
    }

    /// A compact numbered step (the Other AIs tab).
    private func step<Controls: View>(_ n: Int, _ title: String, _ sub: String,
                                      @ViewBuilder controls: () -> Controls) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "\(n).circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                controls()
                Text(sub).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 460, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 0.5))
    }

    // MARK: - The sharing toggle (toolbar, sharing ON only): the synced stamp as its label, and a
    // real switch; off goes through the confirm.

    private var sharingToggle: some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small) }
            Text(pillLabel).font(.callout).foregroundStyle(.secondary)
            // The setter never writes `enabled` itself — flipping off only raises the confirm,
            // so "Keep Sharing" leaves the switch on; disconnect() is what actually turns it off.
            Toggle("Sharing", isOn: Binding(
                get: { enabled },
                set: { requested in if !requested { confirmOff = true } }))
                .labelsHidden().toggleStyle(.switch)
                .disabled(busy)
        }
        .help("Share your knowledge base with your AIs over MCP")
    }

    /// The synced stamp (the last successful push) answers "is my AIs' copy current?" at a
    /// glance; no stamp = enabled but not yet pushed.
    private var pillLabel: String {
        guard let pushed = MirrorClient.lastPush else { return "Sharing on" }
        return "Synced \(pushed.glanceStamp)"
    }

    // MARK: - MirrorClient plumbing (the SAME path Settings + the popover drive)

    @MainActor private func refresh() async {
        enabled = await MirrorClient.shared.isEnabled
        shareURL = await MirrorClient.shared.shareURL
        loaded = true
    }

    private func connect() {
        guard !busy else { return }
        busy = true; errorLine = nil
        Task { @MainActor in
            do {
                _ = try await MirrorClient.shared.enable()
                // First fill is best-effort: no vault yet / a transient push failure just means
                // the next cycle (or the on-launch catch-up) syncs it.
                do { try await MirrorClient.shared.push(); VaultActivity.shared.vaultDirty = false }
                catch {}
                shareURL = await MirrorClient.shared.shareURL
                enabled = true
            } catch {
                errorLine = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            busy = false
        }
    }

    private func disconnect() {
        guard !busy else { return }
        busy = true; errorLine = nil
        Task { @MainActor in
            await MirrorClient.shared.disable()
            enabled = false
            busy = false
        }
    }
}

// MARK: - The take-me-there link (under each video card)

/// The take-me-there link above each card: opens the AI's own screen in the browser.
private struct StepLink: View {
    let title: String
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                HStack(spacing: 3) {
                    Text(title)
                    Image(systemName: "arrow.up.right").imageScale(.small)
                }
            }
            .font(.callout)
        }
    }
}

// MARK: - The tutorial clip

/// A looping, muted tutorial clip loaded from the bundle by resource name. Until the Screen
/// Studio recordings land, a missing file renders a placeholder, so the page ships now and the
/// .mp4s drop in later with zero code changes.
private struct StepVideo: View {
    let resource: String   // e.g. "connect-chatgpt-1" → connect-chatgpt-1.mp4 in the bundle
    let aspect: CGFloat    // the recordings' own shape (GuideSpec.videoAspect) so fill never crops

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: resource, withExtension: "mp4") {
                LoopingVideo(url: url)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "play.circle")
                        .font(.largeTitle.weight(.light))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 0.5))
    }
}

/// AVPlayerLayer in an NSView — chromeless, muted, seamlessly looping (AVPlayerLooper).
private struct LoopingVideo: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {}

    static func dismantleNSView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player?.pause()
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var looper: AVPlayerLooper? }

    final class PlayerView: NSView {
        let playerLayer = AVPlayerLayer()
        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { fatalError("unused") }
        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)   // no stretchy implicit animation on resize
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

#Preview("Connect your AIs") {
    ConnectAIsView().frame(width: 920, height: 760)
}
