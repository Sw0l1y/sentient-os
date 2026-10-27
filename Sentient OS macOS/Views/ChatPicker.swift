//
//  ChatPicker.swift
//  Sentient OS macOS
//
//  The opt-in "Choose chats & groups" sheet, shared by the chat sources (WhatsApp + iMessage).
//  Lists the chats ACTIVE within the scan window (newest first, with message counts), with
//  search + per-chat checkboxes + bulk All-DMs / All-groups / Clear. "Done" hands the selected
//  chat ids (JIDs / GUIDs) back to the caller, which persists them and lights up the source chip.
//  DMs from numbers not in the user's contacts (ChatInfo.isSaved == false — iMessage only) hide
//  behind the "Show unsaved numbers" checkbox, off by default; a selected chat is never hidden.
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

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 560)
        .background(Theme.bg)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Choose chats & groups").font(.title2.weight(.semibold))
            Text(loaded
                 ? "\(selection.count) selected · \(visible.count) active in the last \(ChatWindowing.lookbackDays) days"
                 : "Reading your chats…")
                .font(.footnote).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            TextField("Search chats", text: $search, prompt: Text("Search chats"))
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 7) {
                bulk("All DMs")    { for c in filtered where !c.isGroup { selection.insert(c.id) } }
                bulk("All groups") { for c in filtered where c.isGroup  { selection.insert(c.id) } }
                bulk("Clear")      { selection.removeAll() }
                Spacer()
                if unsavedCount > 0 { unsavedToggle }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    /// The "show unsaved numbers" checkbox.
    private var unsavedToggle: some View {
        Toggle("Show unsaved numbers (\(unsavedCount))", isOn: $showUnsaved)
            .toggleStyle(.checkbox)
    }

    private func bulk(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    @ViewBuilder private var content: some View {
        if let loadError {
            ContentUnavailableView {
                Label("Couldn't Read \(sourceName)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            }
        } else if !loaded {
            centered { ProgressView() }
        } else if chats.isEmpty {
            ContentUnavailableView("No Active Chats", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Nothing in the last \(ChatWindowing.lookbackDays) days."))
        } else if filtered.isEmpty {
            if search.isEmpty {
                ContentUnavailableView("Only Unsaved Numbers", systemImage: "person.crop.circle.badge.questionmark",
                                       description: Text("Turn on “Show unsaved numbers” to see them."))
            } else {
                ContentUnavailableView.search(text: search)
            }
        } else {
            List(filtered) { chat in
                Toggle(isOn: Binding(
                    get: { selection.contains(chat.id) },
                    set: { on in if on { selection.insert(chat.id) } else { selection.remove(chat.id) } })) {
                    row(chat)
                }
                .toggleStyle(.checkbox)
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
        }
    }

    private func row(_ chat: ChatInfo) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(chat.name).lineLimit(1)
                Text("\(chat.isGroup ? "Group" : "DM") · \(chat.messageCount) msgs · \(chat.lastActive.formatted(.relative(presentation: .numeric)))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } icon: {
            Image(systemName: chat.isGroup ? "person.3" : "person").foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Text("\(selection.count) selected").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Done") { onDone(selection); dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!loaded)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func centered<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        VStack(spacing: 8) { Spacer(); inner(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
