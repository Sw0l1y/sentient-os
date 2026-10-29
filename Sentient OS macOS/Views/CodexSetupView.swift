//
//  CodexSetupView.swift
//  Sentient OS macOS
//
//  The single Codex setup sheet: all three setup steps in one Components-style form, driven
//  entirely by the shared `CodexSetup` engine. This view is a pure trigger + status renderer (ZERO
//  setup logic lives here), so the real onboarding flow can present its own screen over the very
//  same engine without re-implementing anything.
//    1. Install the Codex CLI   2. Log in (browser OAuth)   3. Install the computer-use driver
//
//  Opened today from the dev tools' Codex Setup button.
//

import SwiftUI

struct CodexSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var codex = CodexSetup.shared

    var body: some View {
        VStack(spacing: 0) {
            ConnectorSheetHeader("Codex Setup",
                                 message: "Three steps to let Sentient act for you with Codex computer use.") {
                IconTile(.codex, size: 40)
            }
            Form {
                Section {
                    installRow
                    statusRow(codex.installStatus)
                } header: {
                    Text("Codex CLI")
                } footer: {
                    Text("Downloads Sentient’s verified Codex package into its own private folder. Repair preserves your login and saved tasks.")
                }
                if let loginFooter {
                    Section {
                        loginRow
                        statusRow(codex.loginStatusLine)
                    } header: {
                        Text("Sign In")
                    } footer: {
                        Text(loginFooter)
                    }
                } else {
                    Section {
                        loginRow
                        statusRow(codex.loginStatusLine)
                    } header: {
                        Text("Sign In")
                    }
                }
                Section {
                    driverRow
                    statusRow(ComputerUseSetup.current.status)
                } header: {
                    Text("Computer Use Driver")
                } footer: {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(driverFooterLines, id: \.self) { Text($0) }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            ConnectorSheetFooter {
                escapeTwin
            } trailing: {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 560)
        .frame(minHeight: 560, idealHeight: 640)
        .presentationSizing(.form)
        .onAppear {
            ComputerUseSetup.current.refresh()
            Task { await codex.refreshInstalled() }
            Task { await codex.refreshLoginStatus() }
        }
    }

    // MARK: Step 1 — install

    private var installRow: some View {
        StatusRow("Codex CLI", tile: .codex, detail: codex.installed ? "Installed" : "Not installed",
                  tone: codex.installing ? .working : (codex.installed ? .ok : .off)) {
            Button(codex.installed ? "Repair" : "Install") { Task { await codex.installCodex() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(codex.installing)
        }
    }

    // MARK: Step 2 — sign in

    @ViewBuilder private var loginRow: some View {
        if codex.loggedIn {
            StatusRow("OpenAI Account", tile: TileSpec.codex, detail: "Signed in", tone: .ok) {
                Button("Log In Again") { Task { await codex.startLogin(force: true) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else if codex.loggingIn {
            StatusRow("OpenAI Account", tile: TileSpec.codex, detail: "Waiting for the browser", tone: .working) {
                Button("I’ve Finished Signing In") { Task { await codex.confirmLogin() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else {
            StatusRow("OpenAI Account", tile: TileSpec.codex, detail: "Not signed in", tone: .off) {
                Button("Log In…") { Task { await codex.startLogin() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!codex.installed)
            }
        }
    }

    private var loginFooter: String? {
        if codex.loggedIn {
            return "Signed in with your OpenAI account. Codex is in every plan, free included, so there’s no subscription to check."
        }
        if codex.loggingIn {
            return "A browser window opened for you to sign in. Finish there, then click I’ve Finished Signing In."
        }
        return nil
    }

    // MARK: Step 3 — the computer-use driver

    private var driverRow: some View {
        let ready = ComputerUseSetup.current.ready
        return StatusRow(ComputerUseBackend.current.name, tile: .computerUse,
                         detail: ready ? "Installed" : "Not installed",
                         tone: ComputerUseSetup.current.isInstalling ? .working : (ready ? .ok : .off)) {
            driverButton
        }
    }

    @ViewBuilder private var driverButton: some View {
        if ComputerUseSetup.current.ready {
            Button("Reinstall") { Task { await ComputerUseSetup.current.install(force: true) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(ComputerUseSetup.current.isInstalling)
        } else {
            Button("Install") { Task { await ComputerUseSetup.current.install() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(ComputerUseSetup.current.isInstalling)
        }
    }

    private var driverFooterLines: [String] {
        var lines: [String] = []
        if ComputerUseSetup.current.ready {
            lines.append("\(ComputerUseBackend.current.name) is installed; Sentient can act inside your apps in the background.")
        }
        lines.append(ComputerUseBackend.current == .openAI
            ? "Downloads the verified, signed computer-use helper from Sentient into its private Codex folder."
            : "Downloads the pinned CUA driver, verifies its checksum and signature, and installs it for Sentient.")
        lines.append("This window just triggers the shared setup engine; onboarding calls the exact same code.")
        return lines
    }

    // MARK: Building blocks

    /// A setup engine's ✓/✗ status line: the tone glyph, then selectable monospaced text.
    @ViewBuilder private func statusRow(_ s: String?) -> some View {
        if let s {
            let tone: StatusTone = s.hasPrefix("✓") ? .ok : s.hasPrefix("✗") ? .error : .info
            let stripped = (tone == .info ? s : String(s.dropFirst()))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Label {
                Text(stripped)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(tone == .error ? .primary : .secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: tone.symbol ?? "info.circle")
                    .foregroundStyle(tone.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tone.accessibilityLabel): \(stripped)")
        }
    }

    /// Esc closes the sheet too. Nothing here is cancelable, so there is no visible Cancel; this
    /// invisible twin stays in the hierarchy so its shortcut keeps working.
    private var escapeTwin: some View {
        Button("Close") { dismiss() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

#Preview("Codex setup") {
    HStack(spacing: 0) {
        CodexSetupView().environment(\.colorScheme, .light)
        CodexSetupView().environment(\.colorScheme, .dark)
    }
}
