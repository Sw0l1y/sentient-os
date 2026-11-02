// SchoolFeedSheet.swift
// "Connect Schoology": how to get the calendar's iCal link, a field to paste it, and Connect,
// which reads the feed once and shows "Found N assignments" or a plain error before anything is
// saved. When connected, the same sheet manages it: the count, the last refresh, a field for a
// new link when the school stopped sharing, and Disconnect (forgets the Keychain link and removes
// the School notes Sentient wrote). The link is never shown back, logged or put in a note.
// Shared by Settings and onboarding through KnowledgeSourcesPicker.
// Doc: Settings/Documentation - Settings.md

import SwiftUI
import AppKit

struct SchoolFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SchoolFeedSource.connectedKey) private var connected = false
    @AppStorage(SchoolFeedSource.countKey) private var count = 0
    @AppStorage(SchoolFeedSource.refreshedKey) private var refreshedAt = 0.0
    @AppStorage(SchoolFeedSource.issueKey) private var issue = ""
    @State private var link = ""
    @State private var checking = false
    /// The snapshot a successful Connect just read ("Found N assignments").
    @State private var found: SchoolSnapshot?
    @State private var message: String?
    @State private var confirmDisconnect = false
    @State private var disconnecting = false

    private var running: Bool { PipelineActivity.shared.isRunning }
    private var currentIssue: SchoolFeedSource.Issue? { SchoolFeedSource.Issue(rawValue: issue) }
    /// The school stopped sharing (or the link is gone): only a new link fixes it.
    private var needsNewLink: Bool { currentIssue == .revoked || currentIssue == .missingLink }
    /// The sheet's job is to take a link: not connected yet, or connected with a dead link.
    private var takesLink: Bool { found == nil && (!connected || needsNewLink) }

    var body: some View {
        VStack(spacing: 0) {
            ConnectorSheetHeader(connected && found == nil ? "Schoology" : "Connect Schoology",
                                 message: "Sentient reads the assignments and due dates on your Schoology calendar, so it can tell you what’s due. It never signs in to Schoology.") {
                IconTile(symbol: "graduationcap", color: .gray, size: 40)
            }
            ConnectorSheetBody(maxHeight: 480) {
                Form {
                    if let found {
                        foundSection(found)
                    } else {
                        if connected { statusSection }
                        if takesLink {
                            stepsSection
                            linkSection
                        }
                    }
                    if running && found == nil {
                        Section { StatusLabel("You can change Schoology after analysis finishes.", tone: .info) }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            ConnectorSheetFooter {
                if connected && found == nil {
                    Button("Disconnect…", role: .destructive) { confirmDisconnect = true }
                        .buttonStyle(.bordered)
                        .disabled(running || checking || disconnecting)
                        .accessibilityIdentifier("connector.school.disconnect")
                }
            } trailing: {
                if takesLink {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("connector.cancel")
                    Button("Connect", action: connect)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking || running)
                        .accessibilityIdentifier("connector.school.connect")
                } else {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(disconnecting)
                        .accessibilityIdentifier("connector.school.done")
                }
            }
        }
        .connectorSheetSizing()
        .confirmationDialog("Disconnect Schoology?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive, action: disconnect)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sentient forgets the link and removes the School notes it wrote. You can connect again with the iCal link from Schoology.")
        }
    }

    // MARK: - Sections

    private var stepsSection: some View {
        Section {
            step(1, "In Schoology on the web, open Settings, then Account Settings.")
            step(2, "Next to Share Your Schoology Calendar, choose Enable.")
            step(3, "Copy the iCal link and paste it below.")
        } header: {
            Text(needsNewLink ? "Get a New Calendar Link" : "Get Your Calendar Link")
        } footer: {
            Text("Assignments from ALEKS, McGraw Hill and Savvas appear when your teacher posts them in Schoology with a due date.")
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "\(number).circle").foregroundStyle(.secondary)
        }
    }

    private var linkSection: some View {
        Section {
            TextField("iCal Link", text: $link, prompt: Text("webcal://… or https://…"))
                .autocorrectionDisabled()
                .disabled(checking || running)
                .onSubmit(connect)
                .accessibilityIdentifier("connector.school.link")
            if checking {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Checking the link…").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let message { StatusLabel(message, tone: .error) }
        } footer: {
            Label("The link works like a password for your calendar. Sentient keeps it only in this Mac’s Keychain and never puts it in your notes.",
                  systemImage: "lock.fill")
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Assignments") {
                Text(count.formatted()).monospacedDigit()
            }
            LabeledContent("Last Refreshed") {
                Text(refreshedAt > 0 ? Date(timeIntervalSince1970: refreshedAt).formatted(date: .abbreviated, time: .shortened) : "Not yet")
            }
            if let currentIssue, !running, let text = SchoolFeedSource.issueMessage(currentIssue.rawValue) {
                StatusLabel(text, tone: currentIssue.needsAttention ? .warning : .info)
            }
        } footer: {
            Text("Counts assignments due from the past week through the next \(SchoolSnapshot.futureDays) days. Sentient refreshes them during each analysis.")
        }
    }

    private func foundSection(_ snapshot: SchoolSnapshot) -> some View {
        Section {
            StatusLabel("Found \(RunIssue.count(snapshot.assignments.count, "assignment"))", tone: .ok)
                .accessibilityIdentifier("connector.school.found")
            if !snapshot.courses.isEmpty {
                LabeledContent("Classes") {
                    Text(snapshot.courses.prefix(4).joined(separator: ", ") + (snapshot.courses.count > 4 ? " and \(snapshot.courses.count - 4) more" : ""))
                        .multilineTextAlignment(.trailing)
                }
            }
        } footer: {
            Text(snapshot.assignments.isEmpty
                 ? "Nothing is due from the past week through the next \(SchoolSnapshot.futureDays) days. Sentient checks again during each analysis."
                 : "Due from the past week through the next \(SchoolSnapshot.futureDays) days. Sentient keeps them current in Knowledge › School during each analysis.")
        }
    }

    // MARK: - Actions

    private func connect() {
        let input = link
        guard !checking, !running, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        checking = true
        message = nil
        Task { @MainActor in
            defer { checking = false }
            do {
                let snapshot = try await SchoolFeedSource.connect(input)
                SchoolFeedSource.publishToVault(snapshot)
                link = ""
                found = snapshot
                Log("SchoolFeed: connected, items=\(snapshot.assignments.count)")
            } catch is CancellationError {
            } catch {
                message = SchoolFeedSource.connectMessage(error)
                Log("SchoolFeed: link check failed (\(IterativeRun.schoolCode(error)))")
            }
        }
    }

    private func disconnect() {
        disconnecting = true
        Task { @MainActor in
            await SchoolFeedSource.disconnect()
            disconnecting = false
            dismiss()
        }
    }
}

#Preview("Connect Schoology") {
    HStack(spacing: 0) {
        SchoolFeedSheet().environment(\.colorScheme, .light)
        SchoolFeedSheet().environment(\.colorScheme, .dark)
    }
}
