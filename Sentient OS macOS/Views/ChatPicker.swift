//
//  ChatPicker.swift
//  Sentient OS macOS
//
//  The opt-in "Choose Chats & Groups" picker sheet, shared by the chat sources (WhatsApp + iMessage).
//  Lists the chats ACTIVE within the scan window (newest first, with message counts) as a checkmark
//  list, with a native search field and a Select menu (All DMs / All Groups / Clear Selection).
//  "Done" hands the selected chat ids (JIDs / GUIDs) back to the caller, which persists them.
//  DMs from numbers not in the user's contacts (ChatInfo.isSaved == false — iMessage only) hide
//  behind the "Show Unsaved Numbers" checkbox, off by default; a selected chat is never hidden.
//

import SwiftUI

struct ChatPicker: View {
    let sourceName: String                                   // "WhatsApp" / "iMessage" — for error/empty states
    let loadChats: @Sendable () throws -> [ChatInfo]
    let initialSelection: Set<String>
    var onDone: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chats: [ChatInfo] = []
    @State private var selection: Set<String>
    @State private var search = ""
    @State private var showUnsaved = false
    @State private var loaded = false
    @State private var loadError: String?

    init(sourceName: String, loadChats: @escaping @Sendable () throws -> [ChatInfo],
         initialSelection: Set<String>, onDone: @escaping (Set<String>) -> Void) {
        self.sourceName = sourceName
        self.loadChats = loadChats
        self.initialSelection = initialSelection
        self.onDone = onDone
        _selection = State(initialValue: initialSelection)
    }

    /// What the list shows: saved chats always; unsaved numbers only with the toggle on —
    /// except ones already selected, which must never be invisibly opted in.
    private var visible: [ChatInfo] {
        chats.filter { showUnsaved || $0.isSaved || selection.contains($0.id) }
    }
    private var filtered: [ChatInfo] {
        search.isEmpty ? visible : visible.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    private var unsavedCount: Int { chats.count { !$0.isSaved } }

    /// The source's own logo: the real Messages icon for iMessage, WhatsApp's mark, or none.
    private var logoAsset: String? {
        switch sourceName {
        case "WhatsApp": "WhatsAppMark"
        case "iMessage": "IMessageMark"
        default: nil
        }
    }

    private var countLine: String {
        "\(selection.count) selected · \(visible.count) active in the last \(ChatWindowing.lookbackDays) days"
    }

    var body: some View {
        VStack(spacing: 0) {
            ConnectorSheetHeader("Choose Chats & Groups", message: "Choose the \(sourceName) chats to include.") {
                ConnectorSheetLogo(asset: logoAsset)
            }
            filterBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ConnectorSheetFooter {
                if loaded {
                    Text(countLine)
                        .font(.callout).foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            } trailing: {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("connector.cancel")
                Button("Done") { onDone(selection); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!loaded)
                    .accessibilityIdentifier("connector.chats.done")
            }
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 560)
        .presentationSizing(.page)
        .task { await load() }
    }

    /// Search, the unsaved-numbers filter and the bulk selection, in one bar.
    private var filterBar: some View {
        HStack(spacing: Space.s) {
            ToolbarSearchField(text: $search, prompt: "Search Chats", identifier: "connector.chats.search", width: 240)
            Spacer()
            if unsavedCount > 0 {
                Toggle("Show Unsaved Numbers (\(unsavedCount))", isOn: $showUnsaved)
                    .toggleStyle(.checkbox)
            }
            Menu("Select") {
                Button("All DMs") { for c in filtered where !c.isGroup { selection.insert(c.id) } }
                Button("All Groups") { for c in filtered where c.isGroup { selection.insert(c.id) } }
                Divider()
                Button("Clear Selection") { selection.removeAll() }
            }
            .fixedSize()
        }
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.s)
    }

    @ViewBuilder private var content: some View {
        if let loadError {
            ContentUnavailableView {
                Label("Couldn’t Read \(sourceName)", systemImage: "exclamationmark.bubble")
            } description: {
                Text(loadError)
            }
        } else if !loaded {
            HStack(spacing: Space.s) {
                ProgressView().controlSize(.small)
                Text("Reading your chats…").font(.callout).foregroundStyle(.secondary)
            }
        } else if chats.isEmpty {
            ContentUnavailableView("No Active Chats", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Nothing in the last \(ChatWindowing.lookbackDays) days."))
        } else if filtered.isEmpty && search.isEmpty {
            ContentUnavailableView("Only Unsaved Numbers", systemImage: "person.crop.circle.badge.questionmark",
                                   description: Text("Turn on “Show Unsaved Numbers” to see them."))
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            List {
                ForEach(filtered) { chat in
                    ConnectorCheckRow(chat.name, subtitle: rowDetail(chat), isOn: Binding(
                        get: { selection.contains(chat.id) },
                        set: { on in if on { selection.insert(chat.id) } else { selection.remove(chat.id) } })) {
                        Image(systemName: chat.isGroup ? "person.3.fill" : "person.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
        }
    }

    private func rowDetail(_ chat: ChatInfo) -> String {
        let relative = chat.lastActive.formatted(.relative(presentation: .numeric))
        return "\(chat.isGroup ? "Group" : "DM") · \(chat.messageCount) \(chat.messageCount == 1 ? "message" : "messages") · \(relative)"
    }

    private func load() async {
        guard !loaded else { return }
        do {
            let loader = loadChats
            chats = try await Task.detached { try loader() }.value
        } catch {
            loadError = "\(error)"
        }
        loaded = true
    }
}

#Preview("Mixed saved & unsaved (iMessage)") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            chatPickerPreview.environment(\.colorScheme, scheme)
        }
    }
}

@MainActor private var chatPickerPreview: ChatPicker {
    ChatPicker(
        sourceName: "iMessage",
        loadChats: { [
            ChatInfo(id: "1", name: "Jesai UMass USA", isGroup: false, messageCount: 16,
                     lastActive: .now.addingTimeInterval(-3 * 86400)),
            ChatInfo(id: "2", name: "+14154042744", isGroup: false, messageCount: 2,
                     lastActive: .now.addingTimeInterval(-7 * 86400), isSaved: false),
            ChatInfo(id: "3", name: "+917428192241 & +19121366030", isGroup: true, messageCount: 1,
                     lastActive: .now.addingTimeInterval(-8 * 86400)),
            ChatInfo(id: "4", name: "Aryaman UMass, Gurmeher SF Ditto & 1 others", isGroup: true,
                     messageCount: 50, lastActive: .now.addingTimeInterval(-14 * 86400)),
            ChatInfo(id: "5", name: "Aarit UMass", isGroup: false, messageCount: 19,
                     lastActive: .now.addingTimeInterval(-21 * 86400)),
            ChatInfo(id: "6", name: "262966", isGroup: false, messageCount: 1,
                     lastActive: .now.addingTimeInterval(-40 * 86400), isSaved: false),
            ChatInfo(id: "7", name: "39781", isGroup: false, messageCount: 1,
                     lastActive: .now.addingTimeInterval(-42 * 86400), isSaved: false),
        ] },
        initialSelection: ["2"],   // a selected unsaved number — must stay visible with the toggle off
        onDone: { _ in })
}
