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

/// Parsed documents by source, shared by the transcript's messages and its search snippets.
@MainActor final class SidekickMarkdownCache {
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
        view.wrapsToFrame = wrapping
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
        // Resizing the container makes AppKit re-apply the frame, which must not snap the
        // container back to the placed width in the middle of this measurement.
        view.measuring = true
        if container.containerSize != size { container.containerSize = size }
        layout.ensureLayout(for: container)
        let height = max(ceil(style.pointSize * 1.25), ceil(layout.usedRect(for: container).height) + 1)
        view.measuring = false
        // SwiftUI also asks for probe sizes (an unspecified or infinite width measures at
        // 320 pt above) after it has placed the view. Measuring must not leave the drawn
        // text wrapped at the probe's width, so wrap back to the placed frame.
        view.wrapContainerToFrame()
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
    /// Wrapping text always lays out at the width SwiftUI placed it at; the measurement in
    /// sizeThatFits only borrows the container. Horizontal (code) text keeps its natural width.
    var wrapsToFrame = false
    fileprivate var measuring = false
    private var reportedSelection = false
    private var selectionReplyDelay: Task<Void, Never>?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        wrapContainerToFrame()
    }
    func wrapContainerToFrame() {
        guard wrapsToFrame, !measuring, frame.width >= 1, let container = textContainer,
              container.containerSize.width != frame.width else { return }
        container.containerSize = NSSize(width: frame.width, height: .greatestFiniteMagnitude)
    }
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
    /// First visible selected line, in view coordinates.
    func selectedGlyphRect() -> NSRect? { selectedLineRects()?.first }
    /// First and last visible selected lines, in view coordinates. Glyph layout (not character
    /// counts) handles ligatures, Unicode, wrapped paragraphs and horizontal code/table scrolling.
    func selectedLineRects() -> (first: NSRect, last: NSRect)? {
        let selection = selectedRange()
        guard selection.length > 0, selection.location != NSNotFound,
              NSMaxRange(selection) <= string.utf16.count,
              let layout = layoutManager, let container = textContainer else { return nil }
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        var lines: (first: NSRect, last: NSRect)?
        layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container) { rect, _ in
            let visible = rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y).intersection(self.visibleRect)
            if !visible.isEmpty { lines = (lines?.first ?? visible, visible) }
        }
        return lines
    }
    /// Every visible line's used rect (the extent of its text, not the container's), in view coordinates.
    func visibleLineRects() -> [NSRect] {
        guard let layout = layoutManager, let container = textContainer else { return [] }
        layout.ensureLayout(for: container)
        let origin = textContainerOrigin, visible = visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        var lines: [NSRect] = []
        layout.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
            let line = used.offsetBy(dx: origin.x, dy: origin.y).intersection(visible)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
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
/// Screen coordinates. The chip sits beside the selection's last visible line (`end`), where it
/// covers no text: in the trailing margin past `column`, `gap` away or as near as `owner` (the
/// visible area) allows. Without that room it takes the trailing edge of the text's own room
/// (`text`: the text view, a code block's box, a bubble's fill), clear of `lines` (the text view's
/// visible lines) and past the last line's text, within `gap` of `text` above and below (the room
/// every block, table cell and bubble keeps around its text). A text view that stops short of the
/// column's edge (a table cell) keeps it inside. Only without either does the chip go under the last
/// line, or above the first (`anchor`) when there is no room below or no last line is given; a
/// 32 pt chip cannot fit the gap between two paragraphs. It always stays inside `owner` and `screen`.
/// The popup asks `clearFrame` first at `compactSize` too, so a narrow column shows the icon alone
/// beside the text before the labelled chip covers any.
nonisolated enum SidekickSelectionReplyPlacement {
    /// The chip's distance from the column and from the text beside it.
    static let gap: CGFloat = 8
    /// The chip without its label: the reply arrow alone, in a 32 pt circle.
    static let compactSize = NSSize(width: 32, height: 32)

    static func frame(anchor: NSRect, end: NSRect? = nil, column: NSRect? = nil, text: NSRect? = nil,
                      lines: [NSRect] = [], owner: NSRect, screen: NSRect,
                      size: NSSize = NSSize(width: 96, height: 32)) -> NSRect? {
        guard let bounds = bounds(anchor: anchor, owner: owner, screen: screen, size: size) else { return nil }
        if let clear = clearFrame(anchor: anchor, end: end, column: column, text: text, lines: lines,
                                  owner: owner, screen: screen, size: size) {
            return clear
        }
        if let end, !end.isEmpty, end.minY - 7 - size.height >= bounds.minY {
            return clamped(x: end.midX - size.width / 2, y: end.minY - 7 - size.height, in: bounds, size: size)
        }
        return clamped(x: anchor.midX - size.width / 2, y: anchor.maxY + 7, in: bounds, size: size)
    }

    /// `frame`'s first two choices alone, the margin and beside the last line's text: a spot that
    /// covers no text, or nil.
    static func clearFrame(anchor: NSRect, end: NSRect?, column: NSRect?, text: NSRect?, lines: [NSRect],
                           owner: NSRect, screen: NSRect, size: NSSize = NSSize(width: 96, height: 32)) -> NSRect? {
        guard let bounds = bounds(anchor: anchor, owner: owner, screen: screen, size: size),
              let end, !end.isEmpty, let column else { return nil }
        let y = end.midY - size.height / 2
        // Nothing of the column lies beside the margin, at any height.
        let margin = min(column.maxX + gap, bounds.maxX - size.width)
        if margin >= column.maxX { return clamped(x: margin, y: y, in: bounds, size: size) }
        guard let text, let line = lines.first(where: { $0.minY <= end.midY && end.midY <= $0.maxY }) else { return nil }
        let edge = text.maxX >= column.maxX - 1 ? bounds.maxX : min(text.maxX, bounds.maxX)
        let beside = NSRect(x: edge - size.width, y: y, width: size.width, height: size.height)
        guard beside.minX >= max(line.maxX + gap, bounds.minX), beside.minY >= bounds.minY, beside.maxY <= bounds.maxY,
              beside.minY >= text.minY - gap, beside.maxY <= text.maxY + gap,
              !lines.contains(where: { $0.intersects(beside) }) else { return nil }
        return beside
    }

    /// The area the chip may use, or nil when the anchor is off it or the chip cannot fit.
    private static func bounds(anchor: NSRect, owner: NSRect, screen: NSRect, size: NSSize) -> NSRect? {
        let bounds = owner.intersection(screen).insetBy(dx: 6, dy: 6)
        guard !anchor.isEmpty, anchor.intersects(owner.intersection(screen)),
              bounds.width >= size.width, bounds.height >= size.height else { return nil }
        return bounds
    }
    private static func clamped(x: CGFloat, y: CGFloat, in bounds: NSRect, size: NSSize) -> NSRect {
        NSRect(x: max(bounds.minX, min(x, bounds.maxX - size.width)),
               y: max(bounds.minY, min(y, bounds.maxY - size.height)), width: size.width, height: size.height)
    }
}

/// A single app-owned panel; neither its content nor callbacks retain a message view/window.
/// It cannot become key, so automatic presentation never pulls focus out of native selection.
@MainActor private final class SidekickSelectionReply {
    static let shared = SidekickSelectionReply()
    private weak var selectedView: SidekickMarkdownTextView?
    private weak var owner: NSWindow?
    private var panel: SelectionPanel?
    private var host: ReplyHostingView?
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
              let selected = view.selectedLineRects() else { dismiss(); return }
        func onScreen(_ rect: NSRect) -> NSRect { owner.convertToScreen(view.convert(rect, to: nil)) }
        let anchor = onScreen(selected.first)
        let end = onScreen(selected.last)
        let lines = view.visibleLineRects().map(onScreen)
        let room = Self.textRoom(of: view, in: owner)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? owner.screen
        // A scroll area too short for the chip (a compact notch message) falls back to the window.
        let area = Self.visibleArea(of: view, in: owner).map { $0.intersection(owner.frame) } ?? owner.frame
        guard let visible = screen?.visibleFrame else { dismiss(); return }
        func clear(_ size: NSSize) -> NSRect? {
            SidekickSelectionReplyPlacement.clearFrame(anchor: anchor, end: end, column: room.column, text: room.text,
                                                       lines: lines, owner: area, screen: visible, size: size)
        }
        func place(in bounds: NSRect) -> NSRect? {
            SidekickSelectionReplyPlacement.frame(anchor: anchor, end: end, column: room.column, text: room.text,
                                                  lines: lines, owner: bounds, screen: visible)
        }
        // The labelled chip where it covers no text, else the arrow alone where that covers none (a
        // narrow column); only when neither fits does the labelled chip go under or over a line.
        let compact: Bool, frame: NSRect
        if let clear = clear(NSSize(width: 96, height: 32)) { compact = false; frame = clear }
        else if let clear = clear(SidekickSelectionReplyPlacement.compactSize) { compact = true; frame = clear }
        else if let fallback = place(in: area) ?? place(in: owner.frame) { compact = false; frame = fallback }
        else { dismiss(); return }
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
            self.host = host
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
        host?.rootView = ReplyCapsule(compact: compact) { [weak self] in self?.selectedView?.replyToSelection() }
        panel.setFrame(frame, display: true)
        if panel.parent !== owner { panel.parent?.removeChildWindow(panel); owner.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil) // Deliberately never makeKey / activate / change firstResponder.
    }
    func dismiss(ifOwnedBy view: SidekickMarkdownTextView) {
        guard selectedView === view else { return }
        dismiss()
    }
    /// The visible part of the column, in screen coordinates: the outermost scroll view's clip
    /// inside its content insets (under the toolbar, above the Ask bar). Code and table scrollers
    /// nest inside it. Nil outside a scroll view, where the window bounds the chip.
    private static func visibleArea(of view: NSView, in owner: NSWindow) -> NSRect? {
        var outermost: NSScrollView?
        var ancestor = view.superview
        while let current = ancestor {
            if let scroll = current as? NSScrollView { outermost = scroll }
            ancestor = current.superview
        }
        guard let clip = outermost?.contentView else { return nil }
        let insets = clip.contentInsets
        var visible = clip.bounds
        visible.origin.x += insets.left
        visible.origin.y += clip.isFlipped ? insets.top : insets.bottom
        visible.size.width -= insets.left + insets.right
        visible.size.height -= insets.top + insets.bottom
        guard visible.width > 0, visible.height > 0 else { return nil }
        return owner.convertToScreen(clip.convert(visible, to: nil))
    }
    /// The selected text's own room and the column it lines up in, in screen coordinates. Nothing
    /// else lies beside a code block's text inside its box, or a bubble's inside its fill; a table
    /// cell's neighbours do, so its column is the table's own scroller and its room the cell.
    private static func textRoom(of view: SidekickMarkdownTextView, in owner: NSWindow) -> (text: NSRect, column: NSRect) {
        var scrollers: [NSScrollView] = []
        var ancestor = view.superview
        while let current = ancestor {
            if let scroll = current as? NSScrollView { scrollers.append(scroll) }
            ancestor = current.superview
        }
        // The outermost scroller is the conversation's; the nearest one inside it is a code block's or a table's.
        let box = scrollers.count >= 2 ? scrollers.first : nil
        let boxFrame = box.map { $0.convert($0.bounds, to: nil) }
        var text = view.convert(view.visibleRect, to: nil)
        // `12` is the bubble's Space.m padding; this file compiles standalone and cannot name Views/Design.
        if view.chromeIsBubble == true { text = text.insetBy(dx: -12, dy: 0) }
        if view.style?.code == true, let boxFrame { text = text.union(boxFrame) }
        return (owner.convertToScreen(text), owner.convertToScreen(boxFrame ?? text))
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
    /// Reply with its label, or (`compact`) the arrow alone in a 32 pt circle.
    private struct ReplyCapsule: View {
        var compact = false
        let reply: () -> Void
        var body: some View {
            Button(action: reply) {
                Group {
                    if compact { Image(systemName: "arrowshape.turn.up.left") }
                    else { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: compact ? 32 : 96, height: 32).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Reply to selected text")
            .accessibilityLabel("Reply to selected text")
            .accessibilityIdentifier("sidekick.selection.reply")
        }
    }
}
