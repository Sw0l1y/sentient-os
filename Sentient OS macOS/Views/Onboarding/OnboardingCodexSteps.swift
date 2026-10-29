//
//  OnboardingCodexSteps.swift
//  Sentient OS macOS
//
//  Onboarding's codex login, as numbered live steps — a pure renderer over the SHARED CodexSetup
//  engine (the same instance the dev tools' CodexSetupView drives; zero setup logic lives here).
//
//  OnboardingCodexLoginPanel is the ChatGPT panel inside Choose Your AI's engine picker
//  (OnboardingFrontierModelView): three StatusRows (log in, finish in the browser, ready) whose
//  tones show where the user is. Step 1's button opens the OAuth page, then the panel NOTICES
//  the finished sign-in on its own (a 2s `codex login status` poll while the browser is out;
//  the step adds a re-check on app foreground) — no "I'm done" button. The login button awaits
//  CodexSetup.ensureCurrent before opening the browser, including for existing installs.
//  Also home to the shared onboarding bits: OnboardingWhisper · OnboardingDoneLine ·
//  MonoWaitLine · OnboardingStatusText.
//
//  (Computer-use setup is deliberately NOT in onboarding — it happens later, elsewhere.)
//

import SwiftUI
import AppKit

// MARK: - The ChatGPT panel: log in to codex

struct OnboardingCodexLoginPanel: View {
    @State private var codex = CodexSetup.shared
    @State private var preparationTask: Task<Void, Never>?
    @State private var loginRequestID = UUID()
    @State private var ownedLoginAttempt: UUID?
    @AppStorage(ModelBackend.key) private var backendRaw = ModelBackend.chatgpt.rawValue

    private var backend: ModelBackend { ModelBackend(rawValue: backendRaw) ?? .chatgpt }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Codex runs on your own ChatGPT subscription, so a plan you already pay for powers everything: knowledge base, morning cards, Sidekick, and the Gmail and Calendar connectors. Recommended, and the most battle-tested engine.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                loginSteps
                OnboardingStatusText(codex.loginStatusLine)
            }
            .padding(Space.xs)
        }
        .task(id: codex.loggingIn) {
            // The sign-in watcher (replaces the old "I've finished" button): while the browser
            // flow is out, quietly re-check `codex login status` every 2s — step 3 turns green
            // by itself the moment auth.json lands. (Switching tabs cancels this; the step's
            // foreground re-check still notices a finished sign-in.)
            guard codex.loggingIn else { return }
            while !Task.isCancelled, codex.loggingIn, !codex.loggedIn {
                try? await Task.sleep(for: .seconds(2))
                await codex.refreshLoginStatus()
            }
        }
        .onDisappear { cancelOwnedLogin() }
    }

    /// The numbered steps, or the install failure with its retry when the download gave up.
    @ViewBuilder private var loginSteps: some View {
        if codex.installGaveUp && !codex.installed && !codex.loggedIn && !codex.loggingIn {
            // Failed downloads remain retryable through the same verified installer.
            StatusRow("Sentient couldn’t finish downloading Codex.", tile: .codex, tone: .error) {
                Button("Try Again", action: prepareAndLogin)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(codex.preparing || codex.installing)
            }
            Text("Check your internet connection and available disk space, then try again. Your saved login and tasks are preserved.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Lazy install (decision 2026-08-21): step 1's click installs or updates Codex; a
            // broken existing executable can be repaired here too. Sign-in follows only after
            // preparation succeeds.
            StatusRow("1. Log In with ChatGPT", tone: codex.loggedIn || codex.loggingIn ? .ok : .info) {
                if !codex.loggedIn && !codex.loggingIn {
                    Button("Log In with ChatGPT", action: prepareAndLogin)
                        .buttonStyle(.bordered)
                        .disabled(codex.preparing || codex.installing)
                }
            }
            StatusRow("2. Finish in Your Browser",
                      detail: codex.loggingIn && !codex.loggedIn ? "Waiting for the browser sign-in…" : nil,
                      tone: codex.loggedIn ? .ok : (codex.loggingIn ? .working : .off)) {
                if codex.loggingIn && !codex.loggedIn {
                    LoginLinkButton(url: codex.loginURL)
                }
            }
            StatusRow("3. Codex Is Ready", tone: codex.loggedIn ? .ok : .off) {
                if codex.loggedIn && backend != .chatgpt {
                    // A custom engine won Test & Select earlier — logging in doesn't switch
                    // by itself (browsing never disturbs a live engine); this does.
                    Button("Use ChatGPT", action: useChatGPT)
                        .buttonStyle(.bordered)
                        .disabled(codex.preparing || codex.installing)
                }
            }
            .accessibilityValue(codex.loggedIn ? "Logged in to Codex" : "")
        }
    }

    private func useChatGPT() {
        preparationTask = Task {
            guard await codex.ensureCurrent(), !Task.isCancelled else { return }
            backendRaw = ModelBackend.chatgpt.rawValue
        }
    }

    private func prepareAndLogin() {
        preparationTask?.cancel()
        let request = UUID()
        loginRequestID = request
        preparationTask = Task {
            defer { if loginRequestID == request { preparationTask = nil } }
            guard await codex.ensureCurrent(), !Task.isCancelled, loginRequestID == request else { return }
            let attempt = await codex.startLogin()
            guard !Task.isCancelled, loginRequestID == request else {
                if let attempt { await codex.cancelLogin(ifAttempt: attempt) }
                return
            }
            if let attempt { ownedLoginAttempt = attempt }
        }
    }

    /// Leaving this tab releases its callback server and runtime lease. A later login started
    /// by Settings belongs to that surface, and a completed private sign-in remains saved.
    private func cancelOwnedLogin() {
        loginRequestID = UUID()
        preparationTask?.cancel()
        preparationTask = nil
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

// MARK: - Shared onboarding bits

/// A quiet secondary line (kept for WP12's permission pages).
struct OnboardingWhisper: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// A "this step is done" line: the OK status label.
struct OnboardingDoneLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        StatusLabel(text, tone: .ok)
    }
}

/// A small spinner beside a secondary line — something is happening on its own (waiting for
/// the browser sign-in, the background codex install, the upgrade watch).
struct MonoWaitLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: Space.s) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// The engine's latest status line as a status label, toned by its prefix: "✗" is an error,
/// "✓" is OK, anything else is information. The prefix itself is dropped (the glyph shows it).
struct OnboardingStatusText: View {
    let status: String?
    init(_ status: String?) { self.status = status }

    var body: some View {
        if let status, !status.isEmpty {
            StatusLabel(Self.text(status), tone: Self.tone(status))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func tone(_ status: String) -> StatusTone {
        if status.hasPrefix("✗") { return .error }
        if status.hasPrefix("✓") { return .ok }
        return .info
    }

    private static func text(_ status: String) -> String {
        guard status.hasPrefix("✗") || status.hasPrefix("✓") else { return status }
        return String(status.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}

#Preview("Onboarding — codex login panel") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingCodexLoginPanel()
                .frame(width: 560)
                .padding(Space.xl)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
