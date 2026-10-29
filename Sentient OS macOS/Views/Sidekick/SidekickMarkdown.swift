import AppKit
import SwiftUI

/// User requests are literal text; asterisks, links and code fences remain exactly as typed.
struct SidekickPlainText: View {
    let text: String
    var onReply: ((String) -> Void)? = nil
    var onReplyToMessage: (() -> Void)? = nil
    var onSelectionChange: ((Bool) -> Void)? = nil
    /// White text on an accent bubble that hugs its text (your messages in the transcript).
    var bubble = false
    @State private var selected = false

    var body: some View {
        SidekickSelectableMarkdown(fragment: .plain(text), source: text,
            style: .init(compact: false, heading: nil, code: false, bold: false, alignment: .left, bubble: bubble),
            wrapping: true, onReply: onReply, onReplyToMessage: onReplyToMessage) { value in
                selected = value; onSelectionChange?(value)
            }
            .onDisappear { if selected { selected = false; onSelectionChange?(false) } }
    }
}

/// Shared by Home and the notch. Reply callbacks contain an exact substring of `markdown`,
/// suitable for SidekickConversation.replyReference(selectedText:). No WebView or image fetches.
struct SidekickMarkdown: View {
    let markdown: String
    var compact = false
    var onReply: ((String) -> Void)? = nil
    var onReplyToMessage: (() -> Void)? = nil
    var onSelectionChange: ((Bool) -> Void)? = nil
    @State private var selectedFragments = Set<String>()
    @State private var visibleBlocks = 80
    @State private var showRemainder = false
    @State private var copiedBlock: Int?

    var body: some View {
        let document = SidekickMarkdownCache.shared.document(markdown)
        VStack(alignment: .leading, spacing: compact ? 9 : 12) {
            ForEach(Array(document.blocks.prefix(visibleBlocks).enumerated()), id: \.offset) { index, block in
                blockView(block, index: index, source: document.source)
            }
            if document.blocks.count > visibleBlocks {
                Button("Show More") { visibleBlocks += 80 }
                    .buttonStyle(.link)
            } else if let remainder = document.remainder {
                DisclosureGroup("Show Remaining Text", isExpanded: $showRemainder) {
                    selectable(remainder, source: document.source, id: "remainder")
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: markdown) { _, _ in
            visibleBlocks = 80; showRemainder = false; copiedBlock = nil
            if !selectedFragments.isEmpty { selectedFragments.removeAll(); onSelectionChange?(false) }
        }
        .onDisappear {
            if !selectedFragments.isEmpty { selectedFragments.removeAll(); onSelectionChange?(false) }
        }
        .task(id: copiedBlock) {
            guard copiedBlock != nil else { return }
            do { try await Task.sleep(for: .seconds(1.8)); copiedBlock = nil } catch { }
        }
    }

    @ViewBuilder private func blockView(_ block: SidekickMarkdownDocument.Block, index: Int, source: String) -> some View {
        switch block {
        case .text(let fragment, let decoration):
            decorated(decoration) {
                selectable(fragment, source: source, id: "\(index)", heading: decoration.heading)
                    .padding(.top, decoration.heading == nil ? 0 : (compact ? 4 : 8))
            }
        case .code(let fragment, let language, let decoration):
            decorated(decoration) {
                // An inset code box like Xcode's documentation viewer: a quiet fill, a small
                // header with the language and a Copy button, then the horizontally scrolling code.
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(language?.isEmpty == false ? language! : "Code")
                            .lineLimit(1).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(fragment.text, forType: .string)
                            copiedBlock = index
                        } label: {
                            Label(copiedBlock == index ? "Copied" : "Copy", systemImage: copiedBlock == index ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless).controlSize(.small)
                        .accessibilityLabel(copiedBlock == index ? "Code copied" : "Copy code")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    Divider()
                    ScrollView(.horizontal) {
                        selectable(fragment, source: source, id: "\(index)", code: true, wrapping: false)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(12)
                    }
                }
                // `10` is Radius.group; this file compiles standalone and cannot name Views/Design.
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        case .table(let table, let decoration):
            decorated(decoration) {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                            if rowIndex > 0 { Divider() }
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(table.columns.enumerated()), id: \.offset) { columnIndex, column in
                                    let cell = row.cells.first { $0.column == columnIndex }
                                    selectable(cell?.fragment ?? .plain(""), source: source,
                                        id: "\(index):\(rowIndex):\(columnIndex)", bold: row.header,
                                        alignment: alignment(column.alignment))
                                        .frame(width: columnWidth(table, columnIndex), alignment: .leading)
                                        .padding(.horizontal, 12).padding(.vertical, compact ? 8 : 10)
                                }
                            }
                            .background { if row.header { Rectangle().fill(.quaternary) } }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                }
            }
        case .rule: Divider().padding(.vertical, compact ? 2 : 5)
        }
    }

    /// The body text size for this density, so list markers and table columns match the text.
    private static func bodySize(_ compact: Bool) -> CGFloat {
        SidekickSelectableMarkdown.Style(compact: compact, heading: nil, code: false, bold: false, alignment: .left).pointSize
    }

    private func decorated<Content: View>(_ decoration: SidekickMarkdownDocument.Decoration,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if decoration.quoteDepth > 0 {
                Rectangle().fill(.tertiary).frame(width: 3)
                    .padding(.leading, CGFloat(min(decoration.quoteDepth - 1, 4)) * 8)
            }
            if decoration.listDepth > 0 {
                Text(decoration.marker ?? " ")
                    .font(.system(size: Self.bodySize(compact), weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 22, alignment: .trailing).padding(.top, 1)
                    .padding(.leading, CGFloat(min(decoration.listDepth - 1, 12)) * 18)
                    .accessibilityHidden(decoration.marker == nil)
            }
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func selectable(_ fragment: SidekickMarkdownDocument.Fragment, source: String, id: String,
                            heading: Int? = nil, code: Bool = false, wrapping: Bool = true,
                            bold: Bool = false, alignment: NSTextAlignment = .left) -> some View {
        SidekickSelectableMarkdown(fragment: fragment, source: source,
            style: .init(compact: compact, heading: heading, code: code, bold: bold, alignment: alignment),
            wrapping: wrapping, onReply: onReply, onReplyToMessage: onReplyToMessage) { selected in
                let wasSelected = !selectedFragments.isEmpty
                if selected { selectedFragments.insert(id) } else { selectedFragments.remove(id) }
                let nowSelected = !selectedFragments.isEmpty
                if nowSelected != wasSelected { onSelectionChange?(nowSelected) }
            }
    }
    private func columnWidth(_ table: SidekickMarkdownDocument.Table, _ column: Int) -> CGFloat {
        let measured = table.rows.compactMap { row -> CGFloat? in
            guard let cell = row.cells.first(where: { $0.column == column }) else { return nil }
            let font = NSFont.systemFont(ofSize: Self.bodySize(compact), weight: row.header ? .semibold : .regular)
            return (cell.fragment.text as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return min(compact ? 220 : 300, max(compact ? 88 : 110, ceil(measured) + 6))
    }
    private func alignment(_ value: PresentationIntent.TableColumn.Alignment) -> NSTextAlignment {
        switch value { case .left: .left; case .center: .center; case .right: .right; @unknown default: .left }
    }
}

@MainActor private final class SidekickMarkdownCache {
    static let shared = SidekickMarkdownCache()
    private final class Entry: NSObject {
        let value: SidekickMarkdownDocument
        init(_ value: SidekickMarkdownDocument) { self.value = value }
    }
    private let cache = NSCache<NSString, Entry>()
    private init() { cache.countLimit = 80; cache.totalCostLimit = 12 * 1_024 * 1_024 }
    func document(_ source: String) -> SidekickMarkdownDocument {
        let key = source as NSString
        if let entry = cache.object(forKey: key) { return entry.value }
        let document = SidekickMarkdownDocument(markdown: source)
        cache.setObject(Entry(document), forKey: key, cost: source.utf8.count * 4)
        return document
    }
}

struct SidekickSelectableMarkdown: NSViewRepresentable {
    struct Style: Equatable {
        var compact: Bool
        var heading: Int?
        var code: Bool
        var bold: Bool
        var alignment: NSTextAlignment
        /// White text inside an accent bubble, hugging its natural width.
        var bubble = false
        /// The window uses the macOS text styles (body 13, headings 17/15/13). The notch's compact
        /// sizes are measured by SidekickNotchMessageLayout and stay exactly as they were.
        var pointSize: CGFloat {
            if code { return compact ? 11.5 : 12 }
            if let heading {
                let level = min(max(heading - 1, 0), 4)
                return compact ? 17 - CGFloat(level) * 1.2 : [17, 15, 13][min(level, 2)]
            }
            return compact ? 12.5 : 13
        }
    }
    let fragment: SidekickMarkdownDocument.Fragment
    let source: String
    let style: Style
    let wrapping: Bool
    let onReply: ((String) -> Void)?
    var onReplyToMessage: (() -> Void)? = nil
    let onSelectionChange: (Bool) -> Void

    func makeNSView(context: Context) -> SidekickMarkdownTextView {
        let view = SidekickMarkdownTextView()
        view.drawsBackground = false; view.isEditable = false; view.isSelectable = true
        view.isRichText = true; view.importsGraphics = false; view.allowsUndo = false
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        // SwiftUI's sizeThatFits owns both dimensions. AppKit autoresizing during a
        // measurement can invalidate the surrounding scroll layout before it settles.
        view.isVerticallyResizable = false; view.isHorizontallyResizable = false
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = view
        view.systemSelectedTextAttributes = view.selectedTextAttributes
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: SidekickMarkdownTextView, context: Context) {
        view.interactionEnabled = context.environment.isEnabled
        // A black notch can force SwiftUI's dark scheme independently of the user's desktop.
        // Carry it into AppKit too, so dynamic label/link colors never become black on black.
        let appearance: NSAppearance.Name = context.environment.colorScheme == .dark ? .darkAqua : .aqua
        if view.appearance?.name != appearance { view.appearance = NSAppearance(named: appearance) }
        if view.chromeIsBubble != style.bubble { Self.applyChrome(view, bubble: style.bubble) }
        if onReply == nil || view.source != source || view.rendered != fragment.attributed || view.style != style {
            view.dismissSelectionReply()
        }
        view.onReply = onReply; view.onReplyToMessage = onReplyToMessage; view.onSelectionChange = onSelectionChange
        view.source = source; view.fragment = fragment
        guard view.rendered != fragment.attributed || view.style != style else { return }
        let sameText = view.string == fragment.text
        let selection = view.selectedRange()
        view.rendered = fragment.attributed; view.style = style
        view.textStorage?.setAttributedString(Self.styled(fragment.attributed, style: style))
        if sameText, NSMaxRange(selection) <= view.string.utf16.count { view.setSelectedRange(selection) }
        else { view.setSelectedRange(NSRange(location: 0, length: 0)) }
        view.invalidateIntrinsicContentSize()
    }
    /// System link colour and selection on the reading surface; white links and a translucent
    /// white selection inside an accent bubble, where the system colours would not read.
    private static func applyChrome(_ view: SidekickMarkdownTextView, bubble: Bool) {
        view.chromeIsBubble = bubble
        if bubble {
            view.linkTextAttributes = [.foregroundColor: NSColor.alternateSelectedControlTextColor,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue]
            view.selectedTextAttributes = [.backgroundColor: NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.35)]
        } else {
            view.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
            if let system = view.systemSelectedTextAttributes { view.selectedTextAttributes = system }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: SidekickMarkdownTextView, context: Context) -> CGSize? {
        Self.measuredSize(view, proposedWidth: proposal.width, style: style, wrapping: wrapping)
    }
    static func measuredSize(_ view: SidekickMarkdownTextView, proposedWidth: CGFloat?, style: Style, wrapping: Bool) -> CGSize? {
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        func naturalWidth() -> CGFloat {
            view.attributedString().boundingRect(with: NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]).width
        }
        let width: CGFloat
        if wrapping {
            let proposed = max(1, proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? 320)
            // A bubble hugs short text, like Messages; long text still wraps at the proposal.
            width = style.bubble ? max(1, min(proposed, ceil(naturalWidth()) + 2)) : proposed
        } else {
            width = max(1, ceil(naturalWidth()) + 2)
        }
        let size = NSSize(width: width, height: .greatestFiniteMagnitude)
        if container.containerSize != size { container.containerSize = size }
        layout.ensureLayout(for: container)
        let height = max(ceil(style.pointSize * 1.25), ceil(layout.usedRect(for: container).height) + 1)
        return CGSize(width: width, height: height)
    }
    static func dismantleNSView(_ view: SidekickMarkdownTextView, coordinator: ()) {
        view.dismissSelectionReply()
        if view.selectedRange().length > 0 { view.reportSelection(false) }
        view.onReply = nil; view.onReplyToMessage = nil; view.onSelectionChange = nil
    }

    static func styled(_ input: AttributedString, style: Style) -> NSAttributedString {
        let result = NSMutableAttributedString(string: String(input.characters))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.alignment = style.alignment
        let base = style.code ? NSFont.monospacedSystemFont(ofSize: style.pointSize, weight: .regular)
            : NSFont.systemFont(ofSize: style.pointSize, weight: style.heading != nil || style.bold ? .semibold : .regular)
        let ink = style.bubble ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor
        result.addAttributes([.font: base, .foregroundColor: ink, .paragraphStyle: paragraph],
            range: NSRange(location: 0, length: result.length))
        for run in input.runs {
            let range = NSRange(run.range, in: input)
            let intent = run.inlinePresentationIntent ?? []
            var font = base
            if intent.contains(.code) {
                font = NSFont.monospacedSystemFont(ofSize: style.pointSize * 0.94, weight: .regular)
                result.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.10), range: range)
            }
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            result.addAttribute(.font, value: font, range: range)
            if intent.contains(.strikethrough) { result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            if let link = run.link, SidekickMarkdownTextView.permitted(link) {
                result.addAttribute(.link, value: link, range: range)
            }
        }
        return result
    }
}

final class SidekickMarkdownTextView: NSTextView, NSTextViewDelegate {
    // Opacity keeps the conversation alive behind the overview. AppKit must also stop
    // exposing its native text views to hit testing/accessibility while SwiftUI disables it.
    var interactionEnabled = true {
        didSet {
            guard oldValue != interactionEnabled else { return }
            setAccessibilityHidden(!interactionEnabled)
            if !interactionEnabled {
                dismissSelectionReply()
                reportSelection(false)
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            }
        }
    }
    var source = ""
    var fragment = SidekickMarkdownDocument.Fragment.plain("")
    var rendered: AttributedString?
    var style: SidekickSelectableMarkdown.Style?
    var onReply: ((String) -> Void)?
    var onReplyToMessage: (() -> Void)?
    var onSelectionChange: ((Bool) -> Void)?
    /// Which link and selection colours are applied (nil until the first update).
    var chromeIsBubble: Bool?
    /// AppKit's own selection attributes, restored when a view stops being a bubble.
    var systemSelectedTextAttributes: [NSAttributedString.Key: Any]?
    private var reportedSelection = false
    private var selectionReplyDelay: Task<Void, Never>?
    private var draggingSelection = false

    override var acceptsFirstResponder: Bool { interactionEnabled && super.acceptsFirstResponder }
    override func hitTest(_ point: NSPoint) -> NSView? {
        interactionEnabled ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard interactionEnabled else { return }
        draggingSelection = true
        dismissSelectionReply()
        super.mouseDown(with: event) // AppKit tracks the complete drag before returning.
        draggingSelection = false
        scheduleSelectionReply()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { dismissSelectionReply() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview !== superview { dismissSelectionReply() }
        super.viewWillMove(toSuperview: newSuperview)
    }
    override func resignFirstResponder() -> Bool {
        dismissSelectionReply()
        let resigned = super.resignFirstResponder()
        if resigned { reportSelection(false) }
        return resigned
    }
    override func becomeFirstResponder() -> Bool {
        guard interactionEnabled else { return false }
        let became = super.becomeFirstResponder()
        if became { reportSelection(selectedRange().length > 0) }
        return became
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard interactionEnabled else { return nil }
        dismissSelectionReply()
        return messageContextMenu(addingTo: super.menu(for: event) ?? NSMenu())
    }
    /// Extend AppKit's selection menu without replacing Copy/Look Up or their validation.
    /// The same full source backs every paragraph, code block, table cell and remainder.
    func messageContextMenu(addingTo menu: NSMenu) -> NSMenu {
        let identifiers = Set(["sidekick.replySelection", "sidekick.replyMessage", "sidekick.copyMessage", "sidekick.messageSeparator"])
        for item in menu.items where identifiers.contains(item.identifier?.rawValue ?? "") { menu.removeItem(item) }
        var actions: [NSMenuItem] = []
        func action(_ title: String, selector: Selector, id: String, symbol: String) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; item.identifier = NSUserInterfaceItemIdentifier(id)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            actions.append(item)
        }
        if onReply != nil, fragment.sourceQuote(for: selectedRange(), in: source) != nil {
            action("Reply to selection", selector: #selector(replyToSelection), id: "sidekick.replySelection",
                   symbol: "arrowshape.turn.up.left")
        }
        if onReplyToMessage != nil {
            action("Reply to message", selector: #selector(replyToMessage(_:)), id: "sidekick.replyMessage",
                   symbol: "arrowshape.turn.up.left")
        }
        action("Copy message", selector: #selector(copyMessage(_:)), id: "sidekick.copyMessage", symbol: "doc.on.doc")
        if menu.numberOfItems > 0 {
            let separator = NSMenuItem.separator()
            separator.identifier = NSUserInterfaceItemIdentifier("sidekick.messageSeparator")
            actions.append(separator)
        }
        for (index, item) in actions.enumerated() { menu.insertItem(item, at: index) }
        return menu
    }
    @objc private func copyMessage(_ sender: Any?) { if interactionEnabled { copyMessage(to: .general) } }
    @discardableResult func copyMessage(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(source, forType: .string)
    }
    @objc private func replyToMessage(_ sender: Any?) {
        guard interactionEnabled, let onReplyToMessage else { return }
        dismissSelectionReply()
        setSelectedRange(NSRange(location: selectedRange().location, length: 0))
        onReplyToMessage()
    }
    @objc fileprivate func replyToSelection() {
        guard interactionEnabled, let quote = fragment.sourceQuote(for: selectedRange(), in: source) else { return }
        dismissSelectionReply()
        onReply?(quote)
        setSelectedRange(NSRange(location: selectedRange().location, length: 0))
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        reportSelection(interactionEnabled && selectedRange().length > 0)
        scheduleSelectionReply()
    }
    fileprivate func cancelSelectionReplyDelay() {
        selectionReplyDelay?.cancel(); selectionReplyDelay = nil
    }
    func dismissSelectionReply() {
        cancelSelectionReplyDelay()
        SidekickSelectionReply.shared.dismiss(ifOwnedBy: self)
    }
    #if DEBUG
    /// The isolated UI lab may capture this exact child window; production capture filters
    /// continue to exclude children. No screenshot or presentation is triggered by this getter.
    static var selectionReplyWindowForTesting: NSWindow? { SidekickSelectionReply.shared.visibleWindow }
    #endif
    private func scheduleSelectionReply() {
        cancelSelectionReplyDelay()
        let selection = selectedRange()
        guard interactionEnabled, !draggingSelection, onReply != nil, window?.isVisible == true,
              fragment.sourceQuote(for: selection, in: source) != nil else {
            SidekickSelectionReply.shared.dismiss(ifOwnedBy: self)
            return
        }
        SidekickSelectionReply.shared.watch(self)
        selectionReplyDelay = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard let self, self.interactionEnabled, !Task.isCancelled, !self.draggingSelection,
                  self.selectedRange() == selection else { return }
            SidekickSelectionReply.shared.present(for: self)
        }
    }
    /// First visible selected line, in view coordinates. Glyph layout (not character counts)
    /// handles ligatures, Unicode, wrapped paragraphs and horizontal code/table scrolling.
    func selectedGlyphRect() -> NSRect? {
        let selection = selectedRange()
        guard selection.length > 0, selection.location != NSNotFound,
              NSMaxRange(selection) <= string.utf16.count,
              let layout = layoutManager, let container = textContainer else { return nil }
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        var anchor: NSRect?
        layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container) { rect, stop in
            let visible = rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y).intersection(self.visibleRect)
            if !visible.isEmpty { anchor = visible; stop.pointee = true }
        }
        return anchor
    }
    func reportSelection(_ selected: Bool) {
        guard selected != reportedSelection else { return }
        reportedSelection = selected
        let callback = onSelectionChange
        // Attribute/size updates may happen during SwiftUI reconciliation. Defer only the
        // content-free observation; quoting always reads the current synchronous selection.
        Task { @MainActor in callback?(selected) }
    }
    static func permitted(_ url: URL) -> Bool { ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL, Self.permitted(url) { NSWorkspace.shared.open(url) }
        return true
    }
}

/// Pure placement is shared by the real popup and tests, including negative monitor origins.
nonisolated enum SidekickSelectionReplyPlacement {
    static func frame(anchor: NSRect, owner: NSRect, screen: NSRect, size: NSSize = NSSize(width: 96, height: 32)) -> NSRect? {
        let bounds = owner.intersection(screen).insetBy(dx: 6, dy: 6)
        guard !anchor.isEmpty, anchor.intersects(owner.intersection(screen)),
              bounds.width >= size.width, bounds.height >= size.height else { return nil }
        let x = max(bounds.minX, min(anchor.midX - size.width / 2, bounds.maxX - size.width))
        let y = max(bounds.minY, min(anchor.maxY + 7, bounds.maxY - size.height))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

/// A single app-owned panel; neither its content nor callbacks retain a message view/window.
/// It cannot become key, so automatic presentation never pulls focus out of native selection.
@MainActor private final class SidekickSelectionReply {
    static let shared = SidekickSelectionReply()
    private weak var selectedView: SidekickMarkdownTextView?
    private weak var owner: NSWindow?
    private var panel: SelectionPanel?
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private var observations: [NSObjectProtocol] = []
    var visibleWindow: NSWindow? { panel?.isVisible == true && selectedView != nil ? panel : nil }

    func watch(_ view: SidekickMarkdownTextView) {
        if selectedView !== view || owner !== view.window {
            dismiss()
            selectedView = view; owner = view.window
            installDismissalObservers(view)
        } else { panel?.orderOut(nil) }
    }
    func present(for view: SidekickMarkdownTextView) {
        guard selectedView === view, let owner, view.window === owner, owner.isVisible,
              !view.isHiddenOrHasHiddenAncestor, view.onReply != nil,
              view.fragment.sourceQuote(for: view.selectedRange(), in: view.source) != nil,
              let glyph = view.selectedGlyphRect() else { dismiss(); return }
        let anchor = owner.convertToScreen(view.convert(glyph, to: nil))
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? owner.screen
        guard let screen, let frame = SidekickSelectionReplyPlacement.frame(anchor: anchor, owner: owner.frame, screen: screen.visibleFrame) else { dismiss(); return }
        let panel: SelectionPanel
        if let existing = self.panel { panel = existing }
        else {
            panel = SelectionPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.hidesOnDeactivate = false // the nonactivating notch can be used while another app is active
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
            panel.title = "Reply to selection"
            // A popover-material capsule, like the Writing Tools affordance. The mask image shapes
            // the behind-window blur and the window shadow; the layer only draws the hairline.
            // Reduce Transparency makes the popover material opaque on its own.
            let effect = ReplyEffectView()
            effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
            effect.maskImage = Self.capsuleMask
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 16; effect.layer?.borderWidth = 0.5
            effect.refreshHairline()
            let host = ReplyHostingView(rootView: ReplyCapsule { [weak self] in
                self?.selectedView?.replyToSelection()
            })
            host.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                host.topAnchor.constraint(equalTo: effect.topAnchor),
                host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
            panel.contentView = effect
            self.panel = panel
        }
        // Follow the message's own appearance: light in a light window, dark over the notch
        // (whose text view is bridged to darkAqua from its SwiftUI colour scheme).
        panel.appearance = view.effectiveAppearance
        panel.level = owner.level
        panel.setFrame(frame, display: true)
        if panel.parent !== owner { panel.parent?.removeChildWindow(panel); owner.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil) // Deliberately never makeKey / activate / change firstResponder.
    }
    func dismiss(ifOwnedBy view: SidekickMarkdownTextView) {
        guard selectedView === view else { return }
        dismiss()
    }
    private func dismiss() {
        selectedView?.cancelSelectionReplyDelay()
        panel?.orderOut(nil)
        if let panel { panel.parent?.removeChildWindow(panel) }
        selectedView = nil; owner = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        observations.forEach(NotificationCenter.default.removeObserver); observations.removeAll()
    }
    private func installDismissalObservers(_ view: SidekickMarkdownTextView) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .scrollWheel { self.dismiss() }
                else if event.type == .keyDown {
                    if event.keyCode == 53 { self.dismiss() }
                } else if event.window !== self.panel { self.dismiss() }
            }
            return event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismiss() }
        }
        func observe(_ name: Notification.Name, object: AnyObject?) {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResignMainNotification,
                     NSWindow.willCloseNotification, NSWindow.willMoveNotification, NSWindow.didResizeNotification] {
            observe(name, object: owner)
        }
        observe(NSApplication.didResignActiveNotification, object: NSApp)
        var ancestor = view.superview
        while let current = ancestor {
            if let clip = current as? NSClipView {
                clip.postsBoundsChangedNotifications = true
                observe(NSView.boundsDidChangeNotification, object: clip)
            }
            if let scroll = current as? NSScrollView { observe(NSScrollView.willStartLiveScrollNotification, object: scroll) }
            ancestor = current.superview
        }
    }

    private final class SelectionPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    /// A 32 pt capsule that stretches horizontally to the panel's width.
    private static let capsuleMask: NSImage = {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        image.resizingMode = .stretch
        return image
    }()

    private final class ReplyEffectView: NSVisualEffectView {
        func refreshHairline() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                self.layer?.borderColor = NSColor.separatorColor.cgColor
            }
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            refreshHairline()
        }
    }
    private final class ReplyHostingView: NSHostingView<ReplyCapsule> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    private struct ReplyCapsule: View {
        let reply: () -> Void
        var body: some View {
            Button(action: reply) {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 96, height: 32).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reply to selected text")
            .accessibilityIdentifier("sidekick.selection.reply")
        }
    }
}
