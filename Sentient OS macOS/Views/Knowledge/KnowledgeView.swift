//
//  KnowledgeView.swift
//  Sentient OS macOS
//
//  The Knowledge page, shaped like Notes: a notes list (KnowledgeNotesList: the pinned "Overview" =
//  the root README, disclosure folders, a sync/count strip) beside a document reader on the text
//  background, with a Note Info inspector (KnowledgeNoteInfo.swift). The toolbar carries the list
//  toggle, Back, the Reader | Graph switch (⇧⌘G), New Note…/New Folder…, Edit/Done, More (Reveal
//  in Finder, Move to Trash), Search Notes and Note Info. [[Wikilinks]] jump between notes (Back
//  walks the trail). Every edit/create/delete commits locally and DEBOUNCE-syncs to the cloud MCP
//  (VaultActivity.markChanged → the list's sync strip). Graph mode swaps the page for the node map
//  (Graph/NightSkyView.swift); click a node to read it, and Back (or Esc) returns to the graph.
//
//  Data: VaultTree.swift · rendering: MarkdownView.swift.
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
    @FocusState private var createFieldFocused: Bool
    /// Bumped to focus the toolbar's Search Notes field (an NSSearchField, not a SwiftUI focusable).
    @State private var searchFocusTick = 0

    // Note Info: the inspector's visibility, and the open note's facts (folder, edited date, linked
    // notes). Rebuilt by `refreshNoteInfo()` on selection, save and graph changes; never in `body`.
    @State private var showInfo = false
    @State private var noteInfo: KnowledgeNoteInfo?

    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduce: Bool { motionOverride ?? systemReduced }

    // The new-note / new-folder name prompt (raised by the New menu and the right-click menus).
    @State private var showCreatePrompt = false
    @State private var createIsFolder = false
    @State private var createParent: URL?     // nil = the vault root
    @State private var createName = ""

    // The graph — the toolbar's Reader / Graph switch leads to it; the page opens on the Reader.
    // The model outlives toggles, so the graph keeps its camera and node positions across reader
    // trips; `cameFromSky` makes Back return to the graph after a node click. The reader also reads
    // the model's graph for each note's linked notes.
    @State private var mode: Mode = .reader
    @StateObject private var skyModel = NightSkyModel()
    @State private var cameFromSky = false

    /// Reader (the list + document split) or the Graph (the full-page node map).
    private enum Mode: Hashable { case reader, sky }

    /// A navigation parked behind the unsaved-edits prompt.
    private enum PendingNav { case open(URL), follow(URL), back, sky, leave((Bool) -> Void) }

    var body: some View {
        Group {
            if mode == .sky {
                skyPane
            } else {
                readerSplit
            }
        }
        .frame(minWidth: 680, minHeight: 480)
        .toolbar { knowledgeToolbar }
        .pageSubtitle(vault == nil ? "No notes yet" : countText, page: .knowledge)
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
        .onChange(of: graphShape) { _, _ in refreshNoteInfo() }
        .onChange(of: search) { _, query in
            // Results are listed in the Reader's notes list, so typing in Graph mode switches to it.
            if !query.isEmpty && mode == .sky { requestMode(.reader) }
        }
        .onDisappear(perform: deactivate)
        .alert("Do you want to save the changes you made to “\(note?.title ?? "this note")”?",
               isPresented: $showDiscardPrompt) {
            Button("Save") { promptSave() }
                .keyboardShortcut(.defaultAction)
            Button("Don’t Save", role: .destructive) { promptDiscard() }
            Button("Cancel", role: .cancel) { cancelPendingNavigation() }
        } message: {
            Text("Your changes will be lost if you don’t save them.")
        }
        .alert(createIsFolder ? "New Folder" : "New Note", isPresented: $showCreatePrompt) {
            TextField(createIsFolder ? "Folder name" : "Note name", text: $createName)
                .focused($createFieldFocused)
            Button("Create") { performCreate() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: showCreatePrompt) { _, shown in
            if shown { claimCreateFieldFocus() }
        }
        .onChange(of: isPresented) { _, shown in
            if !shown { deactivate() }
        }
    }

    /// Reader mode: the notes list beside the document, with the Note Info inspector.
    /// Without a knowledge base the page is one empty state, with no empty list beside it.
    private var readerSplit: some View {
        HSplitView {
            if sidebarVisible && !(loaded && vault == nil) {
                KnowledgeNotesList(vault: vault, selection: selection, search: search, expanded: $expanded,
                                   mirrorEnabled: mirrorEnabled, onOpen: requestOpen,
                                   onCreate: { folder, parent in promptCreate(folder: folder, in: parent) },
                                   onTrash: deleteItem,
                                   onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) })
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            }
            readerPane
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .inspector(isPresented: Binding(get: { isPresented && showInfo && mode == .reader && selection != nil },
                                        set: { showInfo = $0 })) {
            KnowledgeNoteInspector(info: noteInfo, onOpen: requestFollow,
                                   onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) })
                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        // Window-open focus lands in Search Notes. AppKit assigns the initial key view a beat after
        // SwiftUI's appear, so the request waits 100 ms. Only in Reader mode: the graph keeps the
        // keyboard for Esc.
        .task(id: isPresented) {
            guard isPresented else { return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard !Task.isCancelled else { return }
            searchFocusTick += 1
        }
    }

    /// Graph mode takes the whole page. The toolbar switch, Esc and ⇧⌘G lead back.
    private var skyPane: some View {
        NightSkyView(vault: vault, vaultLoaded: loaded, model: skyModel,
                     entranceReady: entranceReady, isActive: isPresented,
                     onOpen: { openFromSky($0) },
                     onExit: { requestMode(.reader) })
    }

    /// Changes when the graph is rebuilt with different notes or links, so Note Info follows it.
    private var graphShape: [Int] {
        guard let g = skyModel.graph else { return [] }
        return [g.nodes.count, g.edges.count]
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
        } else {
            history = []; historyIndex = -1
            selection = nil; note = nil
            if let r = v?.readme { open(r) }                          // greet with the portrait
            else if let first = v?.allNotes.first { open(first.url) }
        }
        // The reader's linked notes and link counts come from the graph, so build it here too
        // (idempotent; the graph view reloads on entry exactly as before).
        await skyModel.load(vault: v)
        refreshNoteInfo()
    }

    /// Rebuild the open note's facts for the metadata line and Note Info.
    private func refreshNoteInfo() {
        guard let url = selection, let v = vault else { noteInfo = nil; return }
        let title = note?.title ?? url.deletingPathExtension().lastPathComponent
        noteInfo = KnowledgeNoteInfo.make(url: url, title: title, vault: v, graph: skyModel.graph)
    }

    /// The retained page cannot rely on disappearance for cleanup. Keep its draft/camera,
    /// but release transient focus, sheets, hover, and the app-wide editing/navigation gates.
    private func deactivate() {
        showCreatePrompt = false; showDiscardPrompt = false
        editorFocused = false; createFieldFocused = false
        searchFocusTick = 0       // the field is rebuilt on return; it takes focus only when asked
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

    // MARK: The graph (mode switching + the node → reader → back-to-graph loop)

    /// Switch reader ⟷ graph. Entering the sky funnels through the same unsaved-edits guard as
    /// every other navigation.
    private func requestMode(_ new: Mode) {
        guard new != mode else { return }
        if new == .sky {
            if editing { if isDirty { pendingNav = .sky; showDiscardPrompt = true; return }; exitEdit() }
            enterSky()
        } else {
            withAnimation(Motion.gated(Motion.standard, reduceMotion: reduce)) { mode = .reader }
        }
    }

    private func enterSky() {
        if cameFromSky, let sel = selection { skyModel.highlight(sel) }   // "you were just here"
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reduce)) { mode = .sky }
    }

    /// A node was clicked: land in the reader on that note, and let Back lead home to the graph.
    private func openFromSky(_ url: URL) {
        withAnimation(Motion.gated(Motion.standard, reduceMotion: reduce)) { mode = .reader }
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
        refreshNoteInfo()
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

    /// Back walks the wikilink trail; with the trail exhausted, it returns to the graph if
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

    /// Commit the buffer to disk and leave edit mode. Cloud sync is DEBOUNCED (markChanged), so Done
    /// is instant locally — no per-note spinner; the notes list's sync strip shows the sync. No changes
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
        refreshNoteInfo()                          // the edited date moved
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
    /// never grab the toolbar's search field or any other field.
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

    /// "12 notes" — the window subtitle and the notes list's strip.
    private var countText: String {
        let n = vault?.titleIndex.count ?? 0
        return "\(n) note\(n == 1 ? "" : "s")"
    }

    /// Where New Note… and New Folder… create: the open note's folder, or the vault root.
    private var createParentForSelection: URL? {
        selection.flatMap { $0 == vault?.readme ? nil : $0.deletingLastPathComponent() }
    }

    // MARK: Toolbar

    /// Knowledge's window-toolbar items. Empty while another page is showing: the page stays
    /// mounted behind the others, and its items must not leak into their toolbars.
    @ToolbarContentBuilder private var knowledgeToolbar: some ToolbarContent {
        if isPresented {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(Motion.gated(Motion.standard, reduceMotion: reduce)) { sidebarVisible.toggle() }
                } label: {
                    Label(sidebarVisible ? "Hide Notes List" : "Show Notes List", systemImage: "sidebar.left")
                }
                .help(sidebarVisible ? "Hide Notes List" : "Show Notes List")
                .disabled(mode == .sky)
            }
            if mode == .reader && (canGoBack || cameFromSky) {
                ToolbarItem(placement: .navigation) {
                    Button(action: requestBack) { Label("Back", systemImage: "chevron.left") }
                        .help(canGoBack ? "Previous Note" : "Back to Graph")
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("View", selection: Binding(get: { mode }, set: { requestMode($0) })) {
                    Text("Reader").tag(Mode.reader)
                    Text("Graph").tag(Mode.sky)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Switch Views (⇧⌘G)")
                .background {
                    Button("Switch View") { requestMode(mode == .reader ? .sky : .reader) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                        .hidden()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Note…") { promptCreate(folder: false, in: createParentForSelection) }
                    Button("New Folder…") { promptCreate(folder: true, in: createParentForSelection) }
                } label: {
                    Label("New", systemImage: "square.and.pencil")
                }
                .help("New Note or Folder")
                .disabled(vault == nil || editing)
            }
            if mode == .reader, let sel = selection {
                ToolbarItem(placement: .primaryAction) {
                    Button(editing ? "Done" : "Edit") { if editing { save() } else { beginEdit() } }
                        .help(editing ? "Save Changes" : "Edit This Note")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([sel]) }
                        Divider()
                        Button("Move to Trash", role: .destructive) { deleteItem(sel) }
                            .disabled(editing || sel == vault?.readme)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .help("More")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                ToolbarSearchField(text: $search, prompt: "Search Notes", identifier: "knowledge.search",
                                   width: 200, focusRequest: searchFocusTick,
                                   onSubmit: { if let first = searchResults.first { requestOpen(first.url) } })
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showInfo.toggle() } label: {
                    Label("Note Info", systemImage: "info.circle")
                }
                .help(showInfo ? "Hide Note Info" : "Show Note Info")
                .disabled(mode == .sky || selection == nil)
            }
        }
    }

    // MARK: Reader

    @ViewBuilder
    private var readerPane: some View {
        if editing, let url = selection {
            editorView(url)
        } else if let note, let url = selection {
            readerDocument(url, note)
        } else if loaded && vault == nil {
            ContentUnavailableView("No Knowledge Base Yet", systemImage: "books.vertical",
                                   description: Text("Your knowledge will appear here after analysis. You can use Sidekick while it’s being built."))
        } else if loaded {
            ContentUnavailableView("No Note Selected", systemImage: "doc.text",
                                   description: Text("Choose a note from the list."))
        } else {
            Color.clear   // pre-load: no flash
        }
    }

    /// The open note as a document: title, a metadata line, the Markdown body, then the notes it
    /// links with.
    private func readerDocument(_ url: URL, _ note: (title: String, markdown: String)) -> some View {
        let info = noteInfo?.url == url ? noteInfo : nil      // cached; never built in body
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Color.clear.frame(height: 0).id("top")
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(note.title)
                            .font(.title.bold())
                            .textSelection(.enabled)
                            .accessibilityAddTraits(.isHeader)
                        if let info, !info.metadataLine.isEmpty {
                            Text(info.metadataLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    MarkdownView(markdown: note.markdown,
                                 exists: { vault?.resolve($0) != nil },
                                 onNavigate: { title in if let u = vault?.resolve(title) { requestFollow(u) } },
                                 onExternal: { NSWorkspace.shared.open($0) })
                    if let links = info?.linked, !links.isEmpty {
                        Divider().padding(.vertical, Space.l)
                        Text("Linked Notes")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(links) { link in
                                Button(link.title) { requestFollow(link.url) }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.xxl)
                .padding(.vertical, Space.xl)
                .centeredColumn(maxWidth: PageMetrics.documentColumn)
            }
            .onChange(of: selection) { _, _ in proxy.scrollTo("top", anchor: .top) }
        }
    }

    /// Edit mode: a plain-text editor over the raw Markdown, in the same reading column so the swap
    /// happens in place. Wikilinks and headers show as their literal source here (you're editing the
    /// file). Esc cancels (prompting if there are unsaved changes).
    private func editorView(_ url: URL) -> some View {
        TextEditor(text: $editText)
            .font(.body)
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .focused($editorFocused)
            .onExitCommand { cancelEdit() }
            .onAppear { if isPresented { editorFocused = true } }
            .padding(.horizontal, Space.xxl)
            .padding(.vertical, Space.xl)
            .centeredColumn(maxWidth: PageMetrics.documentColumn)
            .accessibilityLabel("Note Text")
    }
}

#Preview("Knowledge") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            KnowledgeView().frame(width: 1000, height: 680)
                .environment(\.colorScheme, scheme)
        }
    }
}
