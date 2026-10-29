// AppleMailPicker.swift
// Explicit account opt-in as an account checklist, Mail-specific access errors, and retry.
// Opening never enables a source.
// Doc: Settings/Documentation - Settings.md

import SwiftUI

struct AppleMailPicker: View {
    var onDone: (Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [AppleMailAccount] = []
    @State private var selected = Set<String>()
    @State private var researchEnabled = false
    @State private var loading = true
    @State private var failed = false
    @State private var failureMessage = ""
    @State private var accessIssue = false
    #if DEBUG
    private var previewing = false
    #endif

    init(initialSelection: Set<String>, onDone: @escaping (Set<String>) -> Void) {
        self.onDone = onDone
        _selected = State(initialValue: initialSelection)
        _researchEnabled = State(initialValue: AppleMailResearchAccess.scope != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectorSheetHeader("Apple Mail", message: "Choose the accounts to include.") {
                ConnectorSheetLogo(asset: "AppleMailMark")
            }
            Form {
                Section("Accounts") { accountRows }
                Section {
                    Toggle("Read Emails for Proactive Suggestions", isOn: $researchEnabled)
                } footer: {
                    Text("Your chosen AI can read actual email text from these accounts to check and prepare suggestions. A cloud AI processes that text with its provider. This access only reads mail.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            ConnectorSheetFooter {
                Text("\(selected.count) selected")
                    .font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit()
                if !selected.isEmpty {
                    Button("Deselect All") { selected.removeAll() }
                        .buttonStyle(.link)
                        .disabled(loading)
                }
            } trailing: {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("connector.cancel")
                Button("Done", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || (failed && !selected.isEmpty))
                    .accessibilityIdentifier("connector.mail.done")
            }
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 420, idealHeight: 520)
        .presentationSizing(.form)
        .task {
            #if DEBUG
            if previewing { return }
            #endif
            await load()
        }
    }

    @ViewBuilder private var accountRows: some View {
        if loading {
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small)
                Text("Loading accounts…").font(.callout).foregroundStyle(.secondary)
            }
        } else if failed {
            StatusLabel(failureMessage, tone: .error)
            HStack {
                if accessIssue {
                    Button("Open Full Disk Access…") { Permissions.openFullDiskAccessSettings() }
                }
                Button("Try Again") { Task { await load() } }
            }
        } else if accounts.isEmpty {
            ContentUnavailableView {
                Label("No Mail Accounts", systemImage: "envelope")
            } description: {
                Text("Add an account in Apple Mail, then try again.")
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else {
            ForEach(accounts) { account in
                ConnectorCheckRow(account.name, isOn: Binding(get: { selected.contains(account.id) }, set: {
                    if $0 { selected.insert(account.id) } else { selected.remove(account.id) }
                })) {
                    IconTile(.emailAndCalendar)
                }
            }
            ForEach(Array(selected.subtracting(accounts.map(\.id))).sorted(), id: \.self) { id in
                ConnectorCheckRow("Unavailable account",
                                  isOn: Binding(get: { selected.contains(id) }, set: { if !$0 { selected.remove(id) } })) {
                    IconTile(.emailAndCalendar)
                }
            }
        }
    }

    private func save() {
        AppleMailResearchAccess.save(accounts: researchEnabled ? selected : []); onDone(selected); dismiss()
    }

    private func load() async {
        loading = true; failed = false; accessIssue = false
        do { accounts = try await Task.detached(priority: .utility) { try AppleMailSource.accounts() }.value }
        catch {
            failed = true
            if case AppleMailError.unsupportedSchema = error {
                failureMessage = "This version of Apple Mail isn’t supported yet."
            } else {
                accessIssue = true
                failureMessage = "Allow Full Disk Access in System Settings, then relaunch Sentient."
            }
        }
        loading = false
    }

    #if DEBUG
    static var researchPreview: AppleMailPicker {
        var view = AppleMailPicker(initialSelection: ["work"]) { _ in }
        view.previewing = true
        view._accounts = State(initialValue: [.init(id: "work", name: "Work"), .init(id: "personal", name: "Personal")])
        view._loading = State(initialValue: false)
        view._researchEnabled = State(initialValue: true)
        return view
    }
    #endif
}

#if DEBUG
#Preview {
    HStack(spacing: 0) {
        AppleMailPicker.researchPreview.environment(\.colorScheme, .light)
        AppleMailPicker.researchPreview.environment(\.colorScheme, .dark)
    }
}
#endif
