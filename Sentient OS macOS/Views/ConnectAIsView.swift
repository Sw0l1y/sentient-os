//
//  ConnectAIsView.swift
//  Sentient OS macOS
//
//  The Connect Your AIs page, pushed from Settings › Share with AIs (a Settings detail page in
//  SettingsView's NavigationStack; the window title stays "Share with AIs").
//   · sharing OFF → the consent step as a system empty state: the question, the three trust
//     pillars (encrypted storage, open-source server, sharing controls), "Not Now" (pops back) and
//     "Turn On Sharing" (enables the mirror and makes the first push).
//   · sharing ON → a grouped form: a segmented Claude · ChatGPT · Other AIs switch, the private
//     link (masked, "Copy Link" copies the full URL) and "Copy Instructions", then one numbered
//     section per step of the chosen AI, each with its take-me-there link and tutorial clip.
//     A toolbar switch carries the last synced time; turning it off goes through the
//     confirm-and-delete alert.
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
        Group {
            if !loaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !enabled {
                consent
            } else {
                guide
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .toolbar {
            if loaded && enabled {
                ToolbarItem(placement: .primaryAction) { sharingToggle }
            }
        }
        .task { await refresh() }
        .alert("Stop Sharing Your Knowledge Base?", isPresented: $confirmOff) {
            Button("Keep Sharing", role: .cancel) {}
            Button("Stop & Delete Cloud Copy", role: .destructive) { disconnect() }
        } message: {
            Text(PrivacyCopy.sharingOff)
        }
    }

    // MARK: - Sharing off: the consent step

    private var consent: some View {
        ContentUnavailableView {
            Label {
                Text("Share Your Knowledge with Your AIs?")
            } icon: {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
        } description: {
            Text("Your knowledge base lives on this Mac. You can offer it to ChatGPT, Claude, and the other AIs you choose.")
        } actions: {
            VStack(spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Label(PrivacyCopy.sharingEncryption, systemImage: "lock.fill")
                    Label(PrivacyCopy.sharingOpenSource, systemImage: "chevron.left.forwardslash.chevron.right")
                    Label(PrivacyCopy.sharingControl, systemImage: "key.fill")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440, alignment: .leading)

                HStack(spacing: Space.m) {
                    Button("Not Now") { dismiss() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                        .disabled(busy)
                    Button { connect() } label: {
                        if busy {
                            HStack(spacing: Space.s) {
                                ProgressView().controlSize(.small)
                                Text("Connecting…")
                            }
                        } else {
                            Text("Turn On Sharing")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy)
                }
                .controlSize(.large)

                if let errorLine {
                    StatusLabel(errorLine, tone: .error)
                        .frame(maxWidth: 440)
                }
            }
        }
    }

    // MARK: - Sharing on: the guide

    private var guide: some View {
        PaneForm {
            Section {
                Picker("AI", selection: $tab) {
                    ForEach(AITab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Connect Your AIs")
            } footer: {
                Text("Offer your knowledge base to ChatGPT, Claude, and every AI you use. Private, over MCP, in two steps.")
            }

            Section("Your Private Link") {
                LabeledContent {
                    Button(copiedLink ? "Copied" : "Copy Link") { copy(shareURL ?? "", flag: $copiedLink) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } label: {
                    Text(MirrorClient.maskedURL(shareURL))
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent {
                    Button(copiedPrompt ? "Copied" : "Copy Instructions") { copy(MirrorClient.systemPrompt, flag: $copiedPrompt) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } label: {
                    Text("Instructions for Your AI")
                }
            }

            stepSections(for: spec(tab))

            Section {} footer: {
                Text("Then ask it: \u{201C}What do you know about me?\u{201D}")
            }
        }
    }

    private func spec(_ tab: AITab) -> GuideSpec {
        switch tab {
        case .claude: Self.claudeGuide
        case .chatgpt: Self.chatgptGuide
        case .other: Self.otherGuide
        }
    }

    /// One numbered Section per step. A step's copy control (`GuideStep.Control`) is the private
    /// link section above, so steps carry none of their own.
    @ViewBuilder private func stepSections(for g: GuideSpec) -> some View {
        ForEach(Array(g.steps.enumerated()), id: \.offset) { i, s in
            Section {
                Text(s.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if !s.linkURL.isEmpty, let url = URL(string: s.linkURL) {
                    Link(s.linkLabel, destination: url)
                        .buttonStyle(.link)
                }
                if !g.videoPrefix.isEmpty {
                    StepVideo(resource: "\(g.videoPrefix)-\(i + 1)", aspect: g.videoAspect)
                        .frame(maxWidth: 420)
                        .frame(maxWidth: .infinity)
                }
            } header: {
                Text("\(i + 1). \(s.title)")
            } footer: {
                if !g.footer.isEmpty && i == g.steps.count - 1 {
                    Text(g.footer)
                }
            }
        }
    }

    /// One step of an AI's guide.
    private struct GuideStep {
        enum Control { case none, link, prompt }
        let title: String
        let caption: String
        let linkLabel: String
        let linkURL: String
        let control: Control
    }

    /// One AI's guide: its steps in order (videos load as "<videoPrefix>-<n>.mp4"), at the
    /// recordings' own aspect so nothing is cropped. An empty prefix means no videos.
    private struct GuideSpec {
        let name: String
        let videoPrefix: String
        let videoAspect: CGFloat
        let steps: [GuideStep]
        var footer: String = ""
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
    private static let otherGuide = GuideSpec(
        name: "Other AIs", videoPrefix: "", videoAspect: 1,
        steps: [
            GuideStep(title: "Copy your private link",
                      caption: "Add it as a connector wherever your AI takes MCP servers.",
                      linkLabel: "", linkURL: "", control: .link),
            GuideStep(title: "Tell your AI to use it",
                      caption: "Paste this into its instructions so it checks your knowledge base.",
                      linkLabel: "", linkURL: "", control: .prompt),
        ],
        footer: "Works with any AI that speaks MCP.")

    private func copy(_ text: String, flag: Binding<Bool>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flag.wrappedValue = true
        Task { try? await Task.sleep(for: .seconds(1.8)); flag.wrappedValue = false }
    }

    // MARK: - The sharing switch (toolbar, sharing ON only): the synced stamp as its label

    private var sharingToggle: some View {
        HStack(spacing: Space.s) {
            if busy { ProgressView().controlSize(.small) }
            Text(syncedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            // The setter never writes `enabled` itself: flipping off only raises the confirm,
            // so "Keep Sharing" leaves the switch on; disconnect() is what actually turns it off.
            Toggle("Sharing", isOn: Binding(
                get: { enabled },
                set: { requested in if !requested { confirmOff = true } }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(busy)
        }
        .help("Share your knowledge base with your AIs over MCP")
    }

    /// The synced stamp (the last successful push) answers "is my AIs' copy current?" at a
    /// glance; no stamp = enabled but not yet pushed.
    private var syncedLabel: String {
        MirrorClient.lastPush.map { "Synced \($0.glanceStamp)" } ?? "Sharing on"
    }

    // MARK: - MirrorClient plumbing (the SAME path Settings and the popover drive)

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

// MARK: - The tutorial clip

/// A looping, muted tutorial clip loaded from the bundle by resource name, in a rounded frame at
/// the recording's own aspect. A missing file renders a placeholder, so the .mp4s can drop in
/// later with no code change.
private struct StepVideo: View {
    let resource: String   // e.g. "connect-chatgpt-1" → connect-chatgpt-1.mp4 in the bundle
    let aspect: CGFloat    // the recordings' own shape (GuideSpec.videoAspect)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
        Group {
            if let url = Bundle.main.url(forResource: resource, withExtension: "mp4") {
                LoopingVideo(url: url)
            } else {
                ZStack {
                    Rectangle().fill(.background.secondary)
                    Image(systemName: "play.circle")
                        .font(.largeTitle.weight(.light))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.separator))
        .accessibilityLabel("Tutorial video")
    }
}

/// AVPlayerLayer in an NSView: chromeless, muted, seamlessly looping (AVPlayerLooper).
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

#Preview("Connect Your AIs") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            NavigationStack { ConnectAIsView() }
                .frame(width: 720, height: 760)
                .environment(\.colorScheme, scheme)
        }
    }
}
