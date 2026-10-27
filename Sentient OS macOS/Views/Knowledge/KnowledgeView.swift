//
//  KnowledgeView.swift
//  Sentient OS macOS
//
//  The Knowledge page — a minimal Obsidian-style reader / editor / manager over the real markdown
//  vault (~/Sentient OS - Knowledge Base/). Two-pane split: a folder outline (pinned "Overview" = the
//  root README, search, disclosure folders; create via the footer "+" or right-click) and a
//  rendered-markdown reader on the right. [[Wikilinks]] jump between notes (Back walks the trail);
//  the window toolbar carries Back / Reader–Constellation / Edit / Delete (→ Trash) / Reveal in Finder. Every edit/create/delete commits
//  locally and DEBOUNCE-syncs to the cloud MCP (VaultActivity.markChanged → the sidebar status line).
//  The toolbar's segmented switch swaps the reader for the "Constellation View" graph
//  (Graph/NightSkyView.swift) (⇧⌘G). Click a star to read that note; Back (or Esc) returns to the sky where you left it.
//
//  Replaced the old DatabaseView (a dev CycleStore-summaries inspector, still in Dev Tools via
//  SummariesView). Data: VaultTree.swift · rendering: MarkdownView.swift.
//  Doc: Views/Knowledge/Documentation - Knowledge Window (Constellation & Reader).md
//

import SwiftUI
import AppKit

struct KnowledgeView: View {
    var isPresented = true
    @State private var entranceReady = false

    @State private var vault: KnowledgeVault?
    @State private var loaded = false
    @State private var selection: URL?
    @State private var expanded: Set<URL> = []
    @State private var search = ""
    @State private var sidebarVisible = true

    // Navigation history (back / forward), so a wikilink jump can be undone.
    @State private var history: [URL] = []
    @State private var historyIndex = -1

    // The currently-open note's display content (title + body), recomputed on selection.
    @State private var note: (title: String, markdown: String)?

    // The markdown editor. `editing` swaps the rendered reader for a TextEditor over the RAW file
    // (frontmatter + H1 included — we edit the real bytes); `editText` is the live buffer and
    // `savedText` the last-committed copy (drift = unsaved edits). `mirrorEnabled` gates the header's
    // sync-status line. `pendingNav` parks a note-switch waiting on the unsaved-edits prompt.
    @State private var editing = false
    @State private var editText = ""
    @State private var savedText = ""
    @State private var mirrorEnabled = false
    @State private var pendingNav: PendingNav?
    @State private var showDiscardPrompt = false
    @FocusState private var editorFocused: Bool
    @FocusState private var searchFocused: Bool
    @FocusState private var createFieldFocused: Bool

    // The new-note / new-folder name prompt (raised by the right-click menus).
    @State private var showCreatePrompt = false
    @State private var createIsFolder = false
    @State private var createParent: URL?     // nil = the vault root
    @State private var createName = ""

    // The Night Sky graph view — the toolbar's Reader / Constellation switch leads to it; the page
    // opens on the Reader. The model outlives toggles, so the sky keeps its camera and star
    // positions across reader trips; `cameFromSky` makes Back return to the sky after a star click.
    @State private var mode: Mode = .reader
    @StateObject private var skyModel = NightSkyModel()
    @State private var cameFromSky = false

    /// Reader (the split view) or the Night Sky (the full-window galaxy).
    private enum Mode: Hashable { case reader, sky }

    /// A navigation parked behind the unsaved-edits prompt.
    private enum PendingNav { case open(URL), follow(URL), back, sky, leave((Bool) -> Void) }

    var body: some View {
        Group {
            if mode == .sky {
                skyPane
            } else {
                splitView
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(Theme.bg)
        .toolbar { knowledgeToolbar }
        .allowsHitTesting(isPresented)
        .disabled(!isPresented)
        .accessibilityHidden(!isPresented)
        .task(id: isPresented) {
            guard isPresented else { deactivate(); return }
            MainNavigation.shared.leaveKnowledge = requestLeave
            VaultActivity.shared.editorBusy = editing
            await loadVault()
            guard !Task.isCancelled else { return }
            entranceReady = true
        }
        .onChange(of: ProcessingCoordinator.shared.knowledgeRevision) { _, _ in
            if isPresented && !editing { Task { await loadVault() } }
        }
        .onDisappear(perform: deactivate)
        .alert("You have unsaved edits", isPresented: $showDiscardPrompt) {
            Button("Save") { promptSave() }
            Button("Discard", role: .destructive) { promptDiscard() }
            Button("Cancel", role: .cancel) { cancelPendingNavigation() }
        } message: {
            Text("Save your changes to this note, or discard them?")
        }
        .alert(createIsFolder ? "New folder" : "New note", isPresented: $showCreatePrompt) {
            TextField(createIsFolder ? "Folder name" : "Note name", text: $createName)
                .focused($createFieldFocused)
            Button("Create") { performCreate() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: showCreatePrompt) { _, shown in
            if shown { claimCreateFieldFocus() }
        }
        .onChange(of: isPresented) { _, shown in
            if !shown { deactivate() }
        }
    }

    /// The reader half: the familiar sidebar + rendered-markdown split.
    private var splitView: some View {
        HSplitView {
            if sidebarVisible { sidebar.frame(minWidth: 220, idealWidth: 260, maxWidth: 380) }
            reader.frame(minWidth: 420)
        }
        // Window-open focus lands in the search box, not the sidebar's "+" button. defaultFocus
        // declares it; the delayed onAppear claim backs it up (AppKit assigns the initial key
        // view a beat after SwiftUI's appear — same pattern as PromptBar's launch focus).
        .defaultFocus($searchFocused, isPresented)
        .task(id: isPresented) {
            guard isPresented else { return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard !Task.isCancelled else { return }
            searchFocused = true
        }
    }

    /// The Constellation View takes the whole page. The toolbar switch, Esc, and ⇧⌘G lead back.
    private var skyPane: some View {
        NightSkyView(vault: vault, vaultLoaded: loaded, model: skyModel,
                     entranceReady: entranceReady, isActive: isPresented,
                     onOpen: { openFromSky($0) },
                     onExit: { requestMode(.reader) })

    }

    private func loadVault() async {
        // A plain directory walk (~a handful of folders) — cheap enough to do inline on open.
        let v = KnowledgeVault.load()
        vault = v
        loaded = true
        let enabled = await MirrorClient.shared.isEnabled
        guard !Task.isCancelled else { return }
        mirrorEnabled = enabled
        // A nightly refresh may replace files while this page is away. Keep the reading place
        // when it still exists, refresh its content, and recover to Overview when it vanished.
        if let selection, v?.allNotes.contains(where: { $0.url == selection }) == true || selection == v?.readme {
            if !editing { note = KnowledgeVault.read(selection) }
            return
        }
        history = []; historyIndex = -1
        selection = nil; note = nil
        if let r = v?.readme { open(r) }                          // greet with the portrait
        else if let first = v?.allNotes.first { open(first.url) }
    }

    /// The retained page cannot rely on disappearance for cleanup. Keep its draft/camera,
    /// but release transient focus, sheets, hover, and the app-wide editing/navigation gates.
    private func deactivate() {
        showCreatePrompt = false; showDiscardPrompt = false
        editorFocused = false; searchFocused = false; createFieldFocused = false
        cancelPendingNavigation()
        MainNavigation.shared.leaveKnowledge = nil
        VaultActivity.shared.editorBusy = false
        skyModel.endDrag(); skyModel.clearHover()
        // Do not clear entranceReady here: the outgoing sky must survive the reverse reveal.
    }

    // MARK: Navigation + a wikilink back-trail

    /// Back is offered ONLY after following a wikilink — browsing the tree starts a fresh trail.
    private var canGoBack: Bool { historyIndex > 0 }

    /// Open a note from the sidebar (or on first load): a clean start, so no Back button shows.
    private func open(_ url: URL) {
        history = [url]; historyIndex = 0
        cameFromSky = false      // a fresh trail forgets the sky (openFromSky re-sets it)
        select(url)
    }

    // MARK: The Night Sky (mode switching + the star → reader → back-to-sky loop)

    /// Switch reader ⟷ sky. Entering the sky funnels through the same unsaved-edits guard as
    /// every other navigation.
    private func requestMode(_ new: Mode) {
        guard new != mode else { return }
        if new == .sky {
            if editing { if isDirty { pendingNav = .sky; showDiscardPrompt = true; return }; exitEdit() }
            enterSky()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { mode = .reader }
        }
    }

    private func enterSky() {
        if cameFromSky, let sel = selection { skyModel.highlight(sel) }   // "you were just here"
        withAnimation(.easeInOut(duration: 0.3)) { mode = .sky }
    }

    /// A star was clicked: land in the reader on that note, and let Back lead home to the sky.
    private func openFromSky(_ url: URL) {
        withAnimation(.easeInOut(duration: 0.3)) { mode = .reader }
        open(url)
        cameFromSky = true
    }

    /// Follow a wikilink: push onto the trail (truncating anything we'd gone back past), so Back
    /// returns to the note we jumped from.
    private func follow(_ url: URL) {
        if historyIndex < history.count - 1 { history.removeSubrange((historyIndex + 1)...) }
        if history.last != url { history.append(url); historyIndex = history.count - 1 }
        select(url)
    }

    /// Read a note + reveal it in the tree (expand its ancestor folders). No history side-effects.
    private func select(_ url: URL) {
        selection = url
        note = KnowledgeVault.read(url)
        if let v = vault { expanded.formUnion(v.ancestors(of: url)) }
    }

    private func goBack() { guard canGoBack else { return }; historyIndex -= 1; select(history[historyIndex]) }

    // MARK: Navigation guards (never silently drop unsaved edits)

    /// Sidebar/initial selection, wikilink jumps, and Back all funnel through these. While editing
    /// with unsaved changes → park the target and raise the prompt; editing but clean → quietly leave
    /// edit mode and proceed; not editing → straight through.
    private func requestOpen(_ url: URL) {
        if editing { if isDirty { pendingNav = .open(url); showDiscardPrompt = true; return }; exitEdit() }
        open(url)
    }
    private func requestFollow(_ url: URL) {
        if editing { if isDirty { pendingNav = .follow(url); showDiscardPrompt = true; return }; exitEdit() }
        follow(url)
    }
    private func requestBack() {
        if editing { if isDirty { pendingNav = .back; showDiscardPrompt = true; return }; exitEdit() }
        backAction()
    }

    private func requestLeave(_ action: @escaping (Bool) -> Void) {
        if editing && isDirty {
            cancelPendingNavigation()
            pendingNav = .leave(action)
            showDiscardPrompt = true
        } else {
            if editing { exitEdit() }
            action(true)
        }
    }

    private func cancelPendingNavigation() {
        if case .leave(let completion) = pendingNav { completion(false) }
        pendingNav = nil
    }

    /// Back walks the wikilink trail; with the trail exhausted, it returns to the Night Sky if
    /// that's where this reading trip began.
    private func backAction() {
        if canGoBack { goBack() } else if cameFromSky { enterSky() }
    }

    // MARK: The markdown editor

    private var isDirty: Bool { editing && editText != savedText }

    /// Enter edit mode over the RAW file (frontmatter + H1 included — we edit the real bytes, never a
    /// reconstruction). Refreshes whether the cloud mirror is on, so Save knows if it should sync.
    private func beginEdit() {
        guard let url = selection else { return }
        let raw: String
        do { raw = try String(contentsOf: url, encoding: .utf8) }
        catch {
            Diagnostics.report(.knowledgeFailed, phase: .read, reason: "editor_source", error: error)
            raw = note?.markdown ?? ""
        }
        editText = raw; savedText = raw
        editing = true
        VaultActivity.shared.editorBusy = true
        Task { mirrorEnabled = await MirrorClient.shared.isEnabled }
    }

    /// Esc — cancel editing. Dirty → prompt (no parked nav, so Save/Discard just settle in place);
    /// clean → leave edit mode.
    private func cancelEdit() {
        guard editing else { return }
        if isDirty { pendingNav = nil; showDiscardPrompt = true } else { exitEdit() }
    }

    /// Commit the buffer to disk and leave edit mode. Cloud sync is DEBOUNCED (markChanged), so Save
    /// is instant locally — no per-note spinner; the sidebar's status line shows the sync. No changes
    /// → just leave. `completion` continues a parked note-switch from the unsaved-edits prompt.
    private func save(then completion: (() -> Void)? = nil) {
        guard editing, let url = selection else { completion?(); return }
        guard editText != savedText else { exitEdit(); completion?(); return }
        do {
            try editText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Diagnostics.report(.knowledgeFailed, phase: .write, reason: "save_note", error: error)
            Log("Knowledge editor: save failed — \(ErrorLabel(error))")
            cancelPendingNavigation() // also reply “cancel” to an AppKit quit waiting on this save
            return   // stay in edit mode so the user's text isn't lost
        }
        savedText = editText
        note = KnowledgeVault.read(url)            // refresh the rendered view behind us
        exitEdit()
        VaultActivity.shared.markChanged()         // schedules the debounced mirror sync
        completion?()
    }

    private func exitEdit() {
        editing = false
        VaultActivity.shared.editorBusy = false
    }

    // The unsaved-edits prompt's three answers.
    private func promptSave()    { save { performPendingNav() } }
    private func promptDiscard() { exitEdit(); performPendingNav() }
    private func performPendingNav() {
        guard let p = pendingNav else { return }
        pendingNav = nil
        switch p {
        case .open(let u):   open(u)
        case .follow(let u): follow(u)
        case .back:          backAction()
        case .sky:           enterSky()
        case .leave(let action): action(true)
        }
    }

    // MARK: Managing the vault (create / delete → macOS Trash · all debounce-synced)

    /// Re-scan the vault after a filesystem change. URLs are stable, so `expanded`/`selection` survive
    /// (a now-missing selection is handled by the caller).
    private func reloadVault() { vault = KnowledgeVault.load() }

    /// Move a note OR a folder to the macOS Trash (recoverable). If the open note was the trashed
    /// item — or lived anywhere inside a trashed folder — land back on Overview.
    private func deleteItem(_ url: URL) {
        guard url != vault?.readme else { return }   // never trash the vault index
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            Diagnostics.report(.knowledgeFailed, phase: .remove, reason: "trash_item", error: error)
            Log("Knowledge: delete failed — \(ErrorLabel(error))")
            return
        }
        let lostSelection = selection == url || (selection?.path.hasPrefix(url.path + "/") ?? false)
        reloadVault()
        if lostSelection {
            if let r = vault?.readme { open(r) }
            else { selection = nil; note = nil; history = []; historyIndex = -1 }
        }
        VaultActivity.shared.markChanged()
    }

    /// Raise the name prompt for a new note/folder inside `parent` (nil = the vault root).
    private func promptCreate(folder: Bool, in parent: URL?) {
        createIsFolder = folder; createParent = parent; createName = ""; showCreatePrompt = true
    }

    /// The create alert opens with its initial key view on the button row, not the TextField —
    /// so typing lands nowhere until the user clicks the field. Claim it a beat after
    /// presentation (same delayed-claim pattern as PromptBar's launch focus): the FocusState
    /// claim for when SwiftUI honors `.focused` inside alert content, and an AppKit
    /// first-responder walk as the backstop — matched by the field's placeholder, so it can
    /// never grab the sidebar's search box or any other field.
    private func claimCreateFieldFocus() {
        let placeholder = createIsFolder ? "Folder name" : "Note name"
        for delay: TimeInterval in [0.1, 0.35] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard isPresented, showCreatePrompt else { return }
                createFieldFocused = true
                for window in NSApp.windows where window.isVisible {
                    guard let field = Self.editableField(in: window.contentView,
                                                         placeholder: placeholder) else { continue }
                    if field.currentEditor() == nil { window.makeFirstResponder(field) }
                    return
                }
            }
        }
    }

    /// Depth-first hunt for an editable NSTextField identified by its placeholder.
    private static func editableField(in view: NSView?, placeholder: String) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable, field.placeholderString == placeholder {
            return field
        }
        for sub in view.subviews {
            if let field = editableField(in: sub, placeholder: placeholder) { return field }
        }
        return nil
    }

    private func performCreate() {
        let dir = createParent ?? vault?.root ?? VaultGenerator.vaultRoot
        if createIsFolder { createFolder(named: createName, in: dir) }
        else { createNote(named: createName, in: dir) }
    }

    private func createNote(named raw: String, in dir: URL) {
        let url = Self.uniqueURL(in: dir, name: Self.cleanName(raw, fallback: "Untitled"), ext: "md")
        let title = url.deletingPathExtension().lastPathComponent
        do {
            try "# \(title)\n\n".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Diagnostics.report(.knowledgeFailed, phase: .create, reason: "create_note", error: error)
            Log("Knowledge: create note failed — \(ErrorLabel(error))")
            return
        }
        reloadVault()
        if let v = vault { expanded.formUnion(v.ancestors(of: url)) }   // reveal its folder chain
        open(url)
        beginEdit()                        // drop straight into typing the body
        VaultActivity.shared.markChanged()
    }

    private func createFolder(named raw: String, in dir: URL) {
        let url = Self.uniqueURL(in: dir, name: Self.cleanName(raw, fallback: "New Folder"), ext: nil)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            Diagnostics.report(.knowledgeFailed, phase: .create, reason: "create_folder", error: error)
            Log("Knowledge: create folder failed — \(ErrorLabel(error))")
            return
        }
        reloadVault()
        if let v = vault { expanded.formUnion(v.ancestors(of: url)) }   // reveal the parent chain
        expanded.insert(url)                                            // and open the new folder
        VaultActivity.shared.markChanged()
    }

    /// A safe filename from user input: swap path separators, trim, cap length; fall back if empty.
    private static func cleanName(_ raw: String, fallback: String) -> String {
        let s = raw.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? fallback : String(s.prefix(120))
    }

    /// `dir/name.ext` (or `dir/name` for a folder), suffixing " 2", " 3"… if it already exists — so we
    /// never overwrite.
    private static func uniqueURL(in dir: URL, name: String, ext: String?) -> URL {
        func make(_ n: String) -> URL {
            let base = dir.appendingPathComponent(n, isDirectory: ext == nil)
            return ext.map { base.appendingPathExtension($0) } ?? base
        }
        var candidate = make(name)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) { candidate = make("\(name) \(i)"); i += 1 }
        return candidate
    }

    private var searchResults: [VaultNode] {
        guard let v = vault, !search.isEmpty else { return [] }
        return v.allNotes.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
            sidebarList
            Divider()
            sidebarFooter
        }
        .background(Theme.panel)
    }

    /// The tree's foot, Finder-style: the create menu, then the note count and sync state.
    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            newMenu
            VStack(alignment: .leading, spacing: 2) {
                Text(countText).font(.caption.weight(.medium))
                statusLine
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var countText: String {
        let n = vault?.titleIndex.count ?? 0
        return "\(n) note\(n == 1 ? "" : "s")"
    }

    /// Creates at the vault root; folders and empty list space offer the same via right-click.
    private var newMenu: some View {
        Menu {
            Button { promptCreate(folder: false, in: nil) } label: { Label("New Note", systemImage: "doc.badge.plus") }
            Button { promptCreate(folder: true, in: nil) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New note or folder")
    }

    /// "On this Mac" (mirror off) or the live cloud-MCP sync state. @Observable → live.
    /// AES-256-GCM seals the vault on this Mac before upload; the relay stores ciphertext and
    /// decrypts in memory for authorised requests.
    private var statusLine: some View {
        Group {
            if mirrorEnabled {
                switch VaultActivity.shared.syncState {
                case .synced:  Label("Synced", systemImage: "lock.icloud")
                        .help("Synced to your encrypted cloud MCP copy")
                case .pending: Label("Sync pending", systemImage: "icloud")
                        .help("Changes will sync to your encrypted cloud MCP copy soon")
                case .syncing: Label("Syncing…", systemImage: "arrow.clockwise.icloud")
                        .help("Syncing to your encrypted cloud MCP copy")
                }
            } else {
                Label("On this Mac", systemImage: "internaldrive")
                    .help("Saved on this Mac only")
            }
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var searchField: some View {
        TextField("Search", text: $search, prompt: Text("Search notes"))
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
    }

    /// The folder tree as a native outline. Selecting a note goes through `requestOpen`, so
    /// unsaved edits still prompt before the switch.
    private var sidebarList: some View {
        List(selection: Binding(get: { selection }, set: { url in
            if let url, url != selection { requestOpen(url) }
        })) {
            if search.isEmpty {
                if let readme = vault?.readme {
                    Label("Overview", systemImage: "text.book.closed").tag(readme)
                }
                ForEach(vault?.nodes ?? []) { node in
                    KnowledgeTreeNode(node: node, expanded: $expanded,
                                      onCreate: { promptCreate(folder: $1, in: $0) },
                                      onDelete: { deleteItem($0) })
                }
            } else if searchResults.isEmpty {
                Text("No Matches").foregroundStyle(.secondary)
            } else {
                ForEach(searchResults) { node in
                    KnowledgeTreeNode(node: node, expanded: $expanded,
                                      onCreate: { promptCreate(folder: $1, in: $0) },
                                      onDelete: { deleteItem($0) })
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .contextMenu {   // right-click empty list space → create at the vault ROOT
            Button { promptCreate(folder: false, in: nil) } label: { Label("New Note", systemImage: "doc.badge.plus") }
            Button { promptCreate(folder: true, in: nil) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
        }
    }

    // MARK: Reader

    private var reader: some View {
        readerContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
    }

    /// Knowledge's window-toolbar items. Empty while another page is showing: the page stays
    /// mounted behind the others, and its items must not leak into their toolbars.
    @ToolbarContentBuilder private var knowledgeToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if isPresented && mode == .reader {
                Button { sidebarVisible.toggle() } label: {
                    Label(sidebarVisible ? "Hide Notes List" : "Show Notes List", systemImage: "list.bullet.indent")
                }
                .help(sidebarVisible ? "Hide notes list" : "Show notes list")
                if canGoBack || cameFromSky {
                    Button(action: requestBack) { Label("Back", systemImage: "chevron.left") }
                        .help(canGoBack ? "Previous note" : "Back to the constellation")
                }
            }
        }
        ToolbarItem(placement: .principal) {
            if isPresented {
                Picker("View", selection: Binding(get: { mode }, set: { requestMode($0) })) {
                    Text("Reader").tag(Mode.reader)
                    Text("Constellation").tag(Mode.sky)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Switch views (⇧⌘G)")
                .background {
                    Button("Switch View") { requestMode(mode == .sky ? .reader : .sky) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                        .hidden()
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if isPresented && mode == .reader && selection != nil {
                editToolbarItem
                if !editing { deleteToolbarButton }
                revealToolbarButton
            }
        }
    }

    /// Move the open note to the macOS Trash (icon-only, between Edit and Reveal — reading mode only).
    /// Hidden for the README/Overview — the vault's index shouldn't be one misclick from gone.
    @ViewBuilder
    private var deleteToolbarButton: some View {
        if let url = selection, url != vault?.readme {
            Button(role: .destructive) { deleteItem(url) } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help("Move to Trash")
        }
    }

    @ViewBuilder
    private var revealToolbarButton: some View {
        if let url = selection {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .labelStyle(.iconOnly)
            .help("Reveal in Finder")
        }
    }

    /// The Edit ⟷ Save toggle in the titlebar. Save commits locally; the mirror sync is DEBOUNCED
    /// (see the sidebar's status line), so there's no per-note spinner here.
    @ViewBuilder
    private var editToolbarItem: some View {
        if editing {
            Button { save() } label: { Label("Save", systemImage: "checkmark") }
                .labelStyle(.titleAndIcon)
        } else {
            Button { beginEdit() } label: { Label("Edit", systemImage: "square.and.pencil") }
                .labelStyle(.titleAndIcon)
                .help("Edit this note")
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        if editing, let url = selection {
            editorView(url)
        } else if let note, let url = selection {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        MonoCaps(url.lastPathComponent, size: 9, tracking: 2, color: Theme.Ink.deepMuted)
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.bottom, 11)
                        Text(note.title)
                            .font(.largeTitle.weight(.bold)).foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(.bottom, 22)
                        MarkdownView(markdown: note.markdown,
                                     exists: { vault?.resolve($0) != nil },
                                     onNavigate: { title in if let u = vault?.resolve(title) { requestFollow(u) } },
                                     onExternal: { NSWorkspace.shared.open($0) })
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 46).padding(.top, 18).padding(.bottom, 90)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onChange(of: selection) { _, _ in proxy.scrollTo("top", anchor: .top) }
            }
        } else if loaded && vault == nil {
            emptyState(title: "No knowledge base yet",
                       subtitle: "Your knowledge will appear here after analysis. You can use Sidekick while it is being built.")
        } else if loaded {
            emptyState(title: "Select a note", subtitle: nil)
        } else {
            Color.clear   // pre-load: no flash
        }
    }

    /// Edit mode — a plain-text editor over the raw markdown, in the same reading column so the swap
    /// feels in place. Wikilinks/headers show as their literal source here (you're editing the file).
    /// Esc cancels (prompting if there are unsaved changes).
    private func editorView(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoCaps(url.lastPathComponent, size: 9, tracking: 2, color: Theme.Ink.deepMuted)
                .lineLimit(1).truncationMode(.middle)
                .padding(.bottom, 12)
            TextEditor(text: $editText)
                .font(.body)
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 44).padding(.top, 18).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear { if isPresented { editorFocused = true } }
        .onExitCommand { cancelEdit() }
    }

    private func emptyState(title: String, subtitle: String?) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "books.vertical")
        } description: {
            if let subtitle { Text(subtitle) }
        }
    }
}

// MARK: - Sidebar rows

/// One outline node: a folder disclosing its children, or a selectable note (tagged by URL).
private struct KnowledgeTreeNode: View {
    let node: VaultNode
    @Binding var expanded: Set<URL>
    let onCreate: (URL, Bool) -> Void   // (parent folder, isFolder)
    let onDelete: (URL) -> Void

    var body: some View {
        if node.isFolder {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded.contains(node.url) },
                set: { open in if open { expanded.insert(node.url) } else { expanded.remove(node.url) } }
            )) {
                ForEach(node.children) { child in
                    KnowledgeTreeNode(node: child, expanded: $expanded, onCreate: onCreate, onDelete: onDelete)
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .contextMenu {   // create INSIDE this folder
                        Button { onCreate(node.url, false) } label: { Label("New Note", systemImage: "doc.badge.plus") }
                        Button { onCreate(node.url, true) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                        Divider()
                        revealAndTrash
                    }
            }
        } else {
            Label(node.name, systemImage: "doc.text")
                .lineLimit(1)
                .tag(node.url)
                .contextMenu { revealAndTrash }
        }
    }

    @ViewBuilder private var revealAndTrash: some View {
        Button { NSWorkspace.shared.activateFileViewerSelecting([node.url]) } label: { Label("Reveal in Finder", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { onDelete(node.url) } label: { Label("Move to Trash", systemImage: "trash") }
    }
}

#Preview("Knowledge") {
    KnowledgeView().frame(width: 1100, height: 720).preferredColorScheme(.dark)
}
