// Shared sign-in link copy action, with short feedback that resets for each login attempt.
// Copying never launches or restarts a login. The waiting status stays in the owning panel.
// A secondary control: it never claims Return, and a row caller may set .controlSize(.small).
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI
import AppKit

struct LoginLinkButton: View {
    let url: URL?
    @State private var copied = false
    @State private var copyFailed = false
    @State private var feedbackID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    var body: some View {
        VStack(spacing: Space.xs) {
            Button(action: copy) {
                Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "link")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .disabled(url == nil)
            .help("Copy the sign-in link to open it in another browser on this Mac.")
            .accessibilityLabel(copied ? "Sign-in link copied" : "Copy sign-in link")
            .accessibilityIdentifier("connector.copyLink")
            if copyFailed {
                StatusLabel("Couldn’t copy the link. Please try again.", tone: .error)
            }
        }
        .animation(Motion.gated(Motion.quick, reduceMotion: motionOverride ?? reduceMotion), value: copied)
        .onChange(of: url) { _, _ in resetFeedback() }
        .task(id: feedbackID) {
            guard feedbackID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            resetFeedback()
        }
    }

    private func copy() {
        guard let url else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        copied = pasteboard.setString(url.absoluteString, forType: .string)
        copyFailed = !copied
        feedbackID = UUID()
    }

    private func resetFeedback() {
        copied = false
        copyFailed = false
        feedbackID = nil
    }
}

#Preview("Sign-in link waiting") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(alignment: .leading, spacing: 14) {
                LoginLinkButton(url: URL(string: "https://example.com"))
                Text("Finish signing in in your browser.")
                    .font(.body).foregroundStyle(.secondary)
                MonoWaitLine("waiting for the browser sign-in…")
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 900)
}
