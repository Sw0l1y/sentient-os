// ConnectorActionButton.swift
// The connector sheets' push button: the step's primary is .borderedProminent and owns Return;
// "do it again" is .bordered. An arrow marks an action that opens the browser.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI

struct ConnectorActionButton: View {
    enum Kind { case connect, done, again }

    let title: String
    var kind: Kind = .connect
    var isLoading = false
    let action: () -> Void

    var body: some View {
        switch kind {
        case .connect:
            button
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Opens in your browser")
                .accessibilityIdentifier("connector.connect")
        case .done:
            button
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("connector.done")
        case .again:
            button
                .buttonStyle(.bordered)
                .help("Opens in your browser")
                .accessibilityIdentifier("connector.connect")
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Text(title)
                if kind != .done && !isLoading {
                    Image(systemName: "arrow.up.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(title)
    }
}

#Preview("Connector buttons") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(alignment: .trailing, spacing: Space.m) {
                ConnectorActionButton(title: "Connect Google Drive", action: {})
                ConnectorActionButton(title: "Connect Google Drive", kind: .again, action: {})
                ConnectorActionButton(title: "Done", kind: .done, action: {})
                ConnectorActionButton(title: "Waiting for Sign-In…", isLoading: true, action: {})
                    .disabled(true)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 640)
}
