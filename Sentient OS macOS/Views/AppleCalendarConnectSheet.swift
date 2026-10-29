// AppleCalendarConnectSheet.swift
// User-triggered Calendar consent and explicit per-calendar selection, shared by Settings
// and onboarding. Merely opening the sheet or running analysis never asks for permission.
// Doc: Settings/Documentation - Settings.md

import SwiftUI
import EventKit
import AppKit

struct AppleCalendarConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authorization = EKEventStore.authorizationStatus(for: .event)
    @State private var calendars: [AppleCalendarSource.CalendarInfo] = []
    @State private var selected = AppleCalendarSource.selectedIDs
    @State private var loading = false
    @State private var loaded = false
    @State private var message: String?
    @AppStorage(AppleCalendarSource.issueKey) private var readIssue = ""

    var body: some View {
        VStack(spacing: 0) {
            ConnectorSheetHeader("Apple Calendar", message: "Choose the calendars Sentient reads on this Mac.") {
                ConnectorSheetLogo(asset: "AppleCalendarMark")
            }
            Form {
                if authorization == .fullAccess { calendarSections } else { accessSection }
                noticeSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            ConnectorSheetFooter {
                Text("\(selected.count) selected")
                    .font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit()
                if authorization == .fullAccess && !selected.isEmpty {
                    Button("Clear Selection") { selected.removeAll() }
                        .buttonStyle(.link)
                        .disabled(loading)
                }
            } trailing: {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("connector.cancel")
                Button("Save Selection", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || !loaded || authorization != .fullAccess || PipelineActivity.shared.isRunning)
                    .accessibilityIdentifier("connector.calendar.save")
            }
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 420, idealHeight: 520)
        .presentationSizing(.form)
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await refresh() }
        }
    }

    // MARK: - With Full Access: calendars grouped under their account

    @ViewBuilder private var calendarSections: some View {
        if !loaded && message == nil {
            Section {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Loading calendars…").font(.callout).foregroundStyle(.secondary)
                }
            }
        } else if !loaded {
            Section {
                StatusRow("Calendars", detail: "Couldn’t read", tone: .warning, fixTitle: "Refresh",
                          fix: { Task { await refresh() } })
                    .disabled(loading)
            }
        } else if calendars.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No Calendars", systemImage: "calendar")
                } description: {
                    Text("Add an account in Apple Calendar, then refresh.")
                } actions: {
                    Button("Refresh") { Task { await refresh() } }
                        .disabled(loading)
                }
            }
        } else {
            ForEach(accountGroups) { group in
                Section {
                    ForEach(group.calendars) { calendar in
                        ConnectorCheckRow(calendar.title, isOn: Binding(get: { selected.contains(calendar.id) }, set: { value in
                            if value { selected.insert(calendar.id) } else { selected.remove(calendar.id) }
                        }))
                    }
                } header: {
                    HStack {
                        Text(group.account)
                        Spacer()
                        if group.id == accountGroups.first?.id { refreshButton }
                    }
                }
            }
        }
        if loaded && !missing.isEmpty {
            Section {
                StatusRow("Unavailable Calendars", detail: "\(missing.count)", tone: .warning,
                          fixTitle: "Remove", fix: removeMissing)
            } footer: {
                Text("\(missing.count) previously selected calendars are unavailable. Refresh or remove them to resume analysis.")
            }
        }
    }

    /// Calendars grouped by account, in the first-seen order of `calendars`.
    private var accountGroups: [CalendarGroup] {
        var groups: [CalendarGroup] = []
        for calendar in calendars {
            if let index = groups.firstIndex(where: { $0.account == calendar.account }) {
                groups[index].calendars.append(calendar)
            } else {
                groups.append(CalendarGroup(account: calendar.account, calendars: [calendar]))
            }
        }
        return groups
    }

    private var refreshButton: some View {
        Button { Task { await refresh() } } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("Refresh")
        .accessibilityLabel("Refresh")
        .disabled(loading)
    }

    private var missing: Set<String> { selected.subtracting(Set(calendars.map(\.id))) }

    private func removeMissing() { selected.subtract(missing) }

    private func save() {
        AppleCalendarSource.saveSelection(selected)
        dismiss()
    }

    // MARK: - Without Full Access: a Privacy-style row with its fix

    @ViewBuilder private var accessSection: some View {
        Section {
            switch authorization {
            case .notDetermined, .writeOnly:
                StatusRow("Calendar Access", detail: accessDetail, tone: .warning,
                          fixTitle: "Allow Calendar Access…", fix: { Task { await connect() } })
                    .disabled(loading)
            case .denied:
                StatusRow("Calendar Access", detail: accessDetail, tone: .warning,
                          fixTitle: "Open Privacy Settings…", fix: {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                })
            case .restricted:
                StatusRow("Calendar Access", detail: accessDetail, tone: .off)
            default:
                StatusRow("Calendar Access", detail: accessDetail, tone: .warning)
            }
        } footer: {
            Text(permissionExplanation)
        }
    }

    private var accessDetail: String {
        switch authorization {
        case .writeOnly: "Add events only"
        case .denied: "Denied"
        case .restricted: "Restricted"
        default: "Not allowed"
        }
    }

    // MARK: - Notices

    @ViewBuilder private var noticeSection: some View {
        let issue = PipelineActivity.shared.isRunning ? nil : AppleCalendarSource.issueMessage(readIssue)
        if issue != nil || message != nil || PipelineActivity.shared.isRunning {
            Section {
                if let issue { StatusLabel(issue, tone: .warning) }
                if let message { StatusLabel(message, tone: .error) }
                if PipelineActivity.shared.isRunning {
                    StatusLabel("You can change calendar selections after analysis finishes.", tone: .info)
                }
            }
        }
    }

    private var permissionExplanation: String {
        switch authorization {
        case .restricted: "Calendar access is restricted on this Mac. Your administrator can help change it."
        case .denied: "Calendar access is off. Enable Full Access for Sentient in System Settings to read your selected calendars."
        default: "macOS calls permission to read calendars ‘Full Access’. Sentient uses it here only to read the calendars you choose. No separate sign-in is needed."
        }
    }

    private func connect() async {
        guard !loading else { return }
        loading = true; message = nil
        do { _ = try await AppleCalendarSource.requestAccess() }
        catch { message = "Calendar access could not be requested. Try again or check System Settings." }
        loading = false
        await refresh()
    }

    private func refresh() async {
        guard !loading else { return }
        authorization = EKEventStore.authorizationStatus(for: .event)
        guard authorization == .fullAccess else { calendars = []; loaded = false; return }
        loading = true; message = nil
        defer { loading = false }
        do {
            calendars = try await Task.detached(priority: .userInitiated) { try AppleCalendarSource.calendars() }.value
            loaded = true
        } catch {
            loaded = false
            message = "Your calendars could not be read. Check access in System Settings, then refresh."
        }
        authorization = EKEventStore.authorizationStatus(for: .event)
    }
}

/// One account's calendars, as Calendar's sidebar groups them.
private struct CalendarGroup: Identifiable {
    let account: String
    var calendars: [AppleCalendarSource.CalendarInfo]
    var id: String { account }
}

#Preview("Apple Calendar connection") {
    HStack(spacing: 0) {
        AppleCalendarConnectSheet().environment(\.colorScheme, .light)
        AppleCalendarConnectSheet().environment(\.colorScheme, .dark)
    }
}
