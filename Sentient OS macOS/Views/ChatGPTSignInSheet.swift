// Home's private ChatGPT sign-in, as a two-identity pairing sheet. Presentation never opens a
// browser; the user's button starts the shared setup flow. Only a login started by this sheet
// belongs to its cleanup.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI
import AppKit

struct ChatGPTSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var codex = CodexSetup.shared
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue
    @State private var startTask: Task<Void, Never>?
    @State private var startID = UUID()
    @State private var ownedLoginAttempt: UUID?

    private var busy: Bool { startTask != nil || codex.preparing || codex.installing }

    var body: some View {
        VStack(spacing: 0) {
            pairing
            Text("Sign In to ChatGPT")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.l)
            Text("Sign in to ChatGPT to continue using Sentient.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)
            stateBlock
                .padding(.top, Space.l)
            HStack(spacing: Space.s) {
                Spacer()
                Button("Not Now") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("connector.chatgpt.notNow")
                if !codex.loggingIn { signInButton }
            }
            .padding(.top, Space.xl)
        }
        .padding(.top, Space.xxl).padding(.horizontal, Space.xl).padding(.bottom, Space.l)
        .frame(width: 400)
        .presentationSizing(.fitted)
        .task(id: codex.loggingIn) {
            while !Task.isCancelled, codex.loggingIn, !codex.loggedIn, ModelBackend.current == .chatgpt {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                guard !Task.isCancelled, ModelBackend.current == .chatgpt else { return }
                await codex.refreshLoginStatus()
            }
        }
        .onChange(of: codex.loggedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
        .onChange(of: backendRaw) { _, _ in
            if backendRaw != ModelBackend.chatgpt.rawValue {
                cancelOwnedLogin()
                dismiss()
            }
        }
        .onDisappear { cancelOwnedLogin() }
    }

    /// Two identities joined by a link glyph: Sentient and ChatGPT.
    private var pairing: some View {
        HStack(spacing: Space.l) {
            BrandMarkView(size: 48)
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.tertiary)
            chatGPTLogo
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sentient and ChatGPT")
    }

    @ViewBuilder private var chatGPTLogo: some View {
        if let mark = NSImage(named: "ChatGPTMark") {
            LogoTile(size: 48) { Image(nsImage: mark).resizable().scaledToFit() }
        } else {
            IconTile(.engineChatGPT, size: 48)
        }
    }

    @ViewBuilder private var stateBlock: some View {
        VStack(spacing: Space.m) {
            if codex.loggingIn {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Finish signing in in your browser.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                LoginLinkButton(url: codex.loginURL)
            }
            if let status = codex.loginStatusLine, status.hasPrefix("✗") {
                StatusLabel(status.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines), tone: .error)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signInButton: some View {
        Button(action: signIn) {
            HStack(spacing: Space.s) {
                if busy { ProgressView().controlSize(.small) }
                Text("Sign In")
            }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(busy || !codex.installed)
        .accessibilityIdentifier("connector.chatgpt.signIn")
    }

    private func signIn() {
        guard !busy, ModelBackend.current == .chatgpt else { return }
        let request = UUID()
        startID = request
        startTask = Task {
            defer { if startID == request { startTask = nil } }
            let attempt = await codex.startLogin()
            guard !Task.isCancelled, startID == request, ModelBackend.current == .chatgpt else {
                if let attempt { await codex.cancelLogin(ifAttempt: attempt) }
                return
            }
            if let attempt { ownedLoginAttempt = attempt }
            if codex.loggedIn { dismiss() }
        }
    }

    private func cancelOwnedLogin() {
        startID = UUID()
        startTask?.cancel()
        startTask = nil
        if let attempt = ownedLoginAttempt {
            ownedLoginAttempt = nil
            Task {
                guard !codex.loggedIn else { return }
                await codex.cancelLogin(ifAttempt: attempt)
                if ModelBackend.current == .chatgpt { await codex.refreshLoginStatus() }
            }
        }
    }
}

#Preview("ChatGPT sign-in") {
    HStack(spacing: 0) {
        ChatGPTSignInSheet().environment(\.colorScheme, .light)
        ChatGPTSignInSheet().environment(\.colorScheme, .dark)
    }
}
