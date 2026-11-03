#!/usr/bin/env python3
"""Compile actual Markdown parser/view sources; exercise source quotes and native text layout.

No Sentient app launch, windows, providers, credentials, network, or production preferences.
"""
from pathlib import Path
import subprocess
from swift_fixture import platform_plugin_flags
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sentient OS macOS/Views/Sidekick"
FIXTURE = r'''
import AppKit
import Foundation

@main enum MarkdownTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        guard value() else { fatalError("FAIL: " + label) }
        checks += 1
    }
    static func fragments(_ document: SidekickMarkdownDocument) -> [SidekickMarkdownDocument.Fragment] {
        document.blocks.flatMap { block in
            switch block {
            case .text(let text, _), .code(let text, _, _): return [text]
            case .table(let table, _): return table.rows.flatMap { $0.cells.map(\.fragment) }
            case .rule: return []
            }
        }
    }
    static func first(_ source: String) -> SidekickMarkdownDocument.Fragment {
        fragments(SidekickMarkdownDocument(markdown: source))[0]
    }
    static func quote(_ fragment: SidekickMarkdownDocument.Fragment, _ text: String, source: String) -> String? {
        fragment.sourceQuote(for: (fragment.text as NSString).range(of: text), in: source)
    }
    static func main() async {
        let nested = SidekickMarkdownDocument(markdown: """
        # A **heading**

        3. First
           - Child

             Second paragraph in child.
        4. Next

        > A quote
        >
        > > Nested quote

        ---
        """)
        let decorations = nested.blocks.compactMap { block -> SidekickMarkdownDocument.Decoration? in
            if case .text(_, let decoration) = block { decoration } else { nil }
        }
        check(decorations[0].heading == 1, "heading intent")
        check(decorations.contains { $0.marker == "3." }, "ordered start preserved")
        check(decorations.contains { $0.marker == "4." }, "ordered next item preserved")
        check(decorations.contains { $0.listDepth == 2 && $0.marker == "•" }, "nested unordered list")
        check(decorations.contains { $0.listDepth == 2 && $0.marker == nil }, "continuation does not repeat bullet")
        check(decorations.contains { $0.quoteDepth == 2 }, "nested blockquote")
        check(nested.blocks.contains { if case .rule = $0 { true } else { false } }, "thematic break")

        let tableDocument = SidekickMarkdownDocument(markdown: "| Name | Count |\n|:---|---:|\n| A | **2** |\n| pipe \\| inside | 3 |")
        guard case .table(let table, _) = tableDocument.blocks[0] else { fatalError("table missing") }
        check(table.rows.count == 3 && table.rows[0].header, "table header and rows")
        check(table.columns.map(\.alignment) == [.left, .right], "table alignment")
        check(table.rows[1].cells[1].fragment.text == "2", "table inline formatting")
        check(table.rows[2].cells[0].fragment.text == "pipe | inside", "escaped table pipe")
        let plain = SidekickMarkdownDocument(markdown: "Your **afternoon** has [room](https://example.com).\n\n1. Finish the `calendar` research\n\n| A | B |\n|---|---|\n| x | **y** |\n\n---").plainText
        check(plain == "Your afternoon has room.\n1. Finish the calendar research\nA B\nx y", "search plain text keeps Markdown syntax")

        let codeSource = "```swift\nlet greeting = \"hello\"\nprint(greeting)\n```"
        let codeDocument = SidekickMarkdownDocument(markdown: codeSource)
        guard case .code(let code, let language, _) = codeDocument.blocks[0] else { fatalError("code missing") }
        check(language == "swift", "code language")
        check(code.text == "let greeting = \"hello\"\nprint(greeting)\n", "code copy body excludes fences")
        check(quote(code, "greeting", source: codeSource) == "greeting", "code selection maps inside fences")
        check(quote(code, "print(greeting)", source: codeSource) == "print(greeting)", "code later line exact")
        let tilde = SidekickMarkdownDocument(markdown: "~~~python\nprint(1)\n~~~")
        check(tilde.blocks.contains { if case .code(_, let language, _) = $0 { language == "python" } else { false } }, "tilde fence")
        let unfinished = SidekickMarkdownDocument(markdown: "```txt\nunfinished")
        check(fragments(unfinished).first?.text.hasPrefix("unfinished") == true, "unfinished fence visible")

        let formatted = "hello **bold** then [linked text](https://example.com) and `code`"
        let paragraph = first(formatted)
        check(quote(paragraph, "bold", source: formatted) == "bold", "bold maps to exact source text")
        check(quote(paragraph, "hello bold then", source: formatted) == "hello **bold** then", "cross-format selection includes exact syntax")
        check(quote(paragraph, "linked text", source: formatted) == "linked text", "link label selection")
        check(quote(paragraph, "bold then linked text", source: formatted) == "bold** then [linked text", "cross-link source remains exact")
        check(paragraph.sourceQuote(for: NSRange(location: NSNotFound, length: 1), in: formatted) == nil, "invalid range rejected")
        check(paragraph.sourceQuote(for: NSRange(location: 0, length: Int.max), in: formatted) == nil, "overflow range rejected")
        check(paragraph.sourceQuote(for: NSRange(location: 0, length: 0), in: formatted) == nil, "empty selection rejected")

        let entity = "&amp;"
        check(quote(first(entity), "&", source: entity) == entity, "entity selection expands to original spelling")
        let unicodeEntity = "&#x1F600;"
        check(quote(first(unicodeEntity), "😀", source: unicodeEntity) == unicodeEntity, "Unicode entity expands safely")
        let unicode = "Hi 👩🏽‍💻 café e\u{301} **नमस्ते**."
        let unicodeFragment = first(unicode)
        check(quote(unicodeFragment, "👩🏽‍💻", source: unicode) == "👩🏽‍💻", "emoji grapheme mapping")
        check(quote(unicodeFragment, "e\u{301}", source: unicode) == "e\u{301}", "decomposed accent mapping")
        check(quote(unicodeFragment, "नमस्ते", source: unicode) == "नमस्ते", "non-Latin selection")
        let repeatedSource = "same **same** same"
        let repeated = first(repeatedSource)
        check(repeated.mappings[1].source.location == 7, "repeated phrase maps to selected occurrence")
        let lineSource = "first line\nsecond line"
        check(quote(first(lineSource), "line second", source: lineSource) == "line\nsecond", "soft break maps original newline")
        let crlfSource = "before\r\nafter **bold**"
        let crlf = first(crlfSource)
        check(quote(crlf, "bold", source: crlfSource) == "bold", "CRLF source offsets")

        // Every selectable scalar-sized range must return source text, never synthesized
        // rendered Markdown or a string that the durable reply validator would reject.
        for source in [formatted, unicode, "escaped \\* and &amp; with **bold**", "[x](https://example.com) &lt;tag&gt;"] {
            for fragment in fragments(SidekickMarkdownDocument(markdown: source)) {
                for location in 0..<fragment.text.utf16.count {
                    if let selected = fragment.sourceQuote(for: NSRange(location: location, length: 1), in: source) {
                        check(source.contains(selected), "exact raw substring invariant")
                    }
                }
            }
        }
        let large = String(repeating: "🙂 exact text\n", count: 8_000)
        let largeDocument = SidekickMarkdownDocument(markdown: large)
        check(largeDocument.remainder != nil, "large source parse is bounded")
        let tail = largeDocument.remainder!
        check(!tail.text.contains("�"), "large prefix split respects graphemes")
        check(tail.sourceQuote(for: NSRange(location: 0, length: tail.text.utf16.count), in: large) == tail.text, "large remainder is exact and selectable")
        let manyBlocks = String(repeating: "tiny\n\n", count: 500)
        let bounded = SidekickMarkdownDocument(markdown: manyBlocks)
        check(bounded.blocks.count == 1 && fragments(bounded)[0].text == manyBlocks, "complex block count falls back without loss")

        let normal = SidekickSelectableMarkdown.Style(compact: false, heading: nil, code: false, bold: false, alignment: .left)
        let styled = SidekickSelectableMarkdown.styled(paragraph.attributed, style: normal)
        let boldRange = (styled.string as NSString).range(of: "bold")
        let boldFont = styled.attribute(.font, at: boldRange.location, effectiveRange: nil) as! NSFont
        check(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask), "native bold font")
        let linkRange = (styled.string as NSString).range(of: "linked text")
        check(styled.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL == URL(string: "https://example.com"), "native link attribute")
        for url in ["javascript:alert(1)", "file:///tmp/test", "data:text/html,test", "sentient:delete"] {
            check(!SidekickMarkdownTextView.permitted(URL(string: url)!), "non-web URL is not activated")
        }
        check(SidekickMarkdownTextView.permitted(URL(string: "mailto:hello@example.com")!), "email link supported")
        let dangerous = first("[local](file:///tmp/example)")
        check(SidekickSelectableMarkdown.styled(dangerous.attributed, style: normal).attribute(.link, at: 0, effectiveRange: nil) == nil, "unpermitted link remains inert text")

        let textView = SidekickMarkdownTextView()
        textView.drawsBackground = false; textView.isEditable = false; textView.isSelectable = true
        textView.textContainerInset = .zero; textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        let longParagraph = first(String(repeating: "Native text sizing wraps correctly. ", count: 20))
        textView.textStorage?.setAttributedString(SidekickSelectableMarkdown.styled(longParagraph.attributed, style: normal))
        let narrow = SidekickSelectableMarkdown.measuredSize(textView, proposedWidth: 180, style: normal, wrapping: true)!
        let wide = SidekickSelectableMarkdown.measuredSize(textView, proposedWidth: 600, style: normal, wrapping: true)!
        check(narrow.height > wide.height && narrow.width == 180 && wide.width == 600, "native layout responds to transcript width")
        let natural = SidekickSelectableMarkdown.measuredSize(textView, proposedWidth: nil, style: normal, wrapping: false)!
        check(natural.width > 600 && natural.height < wide.height, "horizontal code layout reports natural width")
        let empty = SidekickSelectableMarkdown.measuredSize(textView, proposedWidth: 0, style: normal, wrapping: true)!
        check(empty.width == 1 && empty.height.isFinite, "zero proposal stays finite")
        let wrappedSize = SidekickSelectableMarkdown.measuredSize(textView, proposedWidth: 180, style: normal, wrapping: true)!
        textView.setFrameSize(wrappedSize)
        let wrappedLines = textView.visibleLineRects()
        check(wrappedLines.count > 3 && wrappedLines.allSatisfy { $0.width > 0 && $0.maxX <= 180.5 } && wrappedLines.contains { $0.width < 170 }
              && zip(wrappedLines, wrappedLines.dropFirst()).allSatisfy { $0.maxY <= $1.minY + 0.5 },
              "native layout reports each visible line's own extent, in order")
        textView.setSelectedRange(NSRange(location: 40, length: 30))
        let wrappedEnd = textView.selectedLineRects()!.last
        check(wrappedLines.contains { $0.minY <= wrappedEnd.midY && wrappedEnd.midY <= $0.maxY && $0.maxX >= wrappedEnd.maxX - 0.5 },
              "the selection's last line is one of the visible lines")

        textView.fragment = paragraph; textView.source = formatted
        textView.textStorage?.setAttributedString(styled)
        var actualReply: String?
        textView.onReply = { actualReply = $0 }
        textView.setSelectedRange((paragraph.text as NSString).range(of: "hello bold then"))
        textView.setFrameSize(NSSize(width: 600, height: 100))
        _ = SidekickSelectableMarkdown.measuredSize(textView, proposedWidth: 600, style: normal, wrapping: true)
        let glyphAnchor = textView.selectedGlyphRect()
        check(glyphAnchor != nil && glyphAnchor!.width > 0 && glyphAnchor!.height > 0,
              "floating reply anchors to native selected glyphs")
        textView.perform(NSSelectorFromString("replyToSelection"))
        check(actualReply == "hello **bold** then", "actual AppKit reply target delivers raw source")
        check(textView.selectedRange().length == 0, "reply clears native selection")
        check(textView.selectedGlyphRect() == nil, "empty selection has no floating reply anchor")
        let owner = NSRect(x: 100, y: 100, width: 800, height: 600)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let middle = NSRect(x: 300, y: 300, width: 120, height: 20)
        let popup = SidekickSelectionReplyPlacement.frame(anchor: middle, owner: owner, screen: screen)!
        check(popup.minY > middle.maxY && popup.midX == middle.midX, "floating reply appears above selection")
        for anchor in [NSRect(x: 101, y: 110, width: 10, height: 15),
                       NSRect(x: 880, y: 680, width: 10, height: 15)] {
            let placed = SidekickSelectionReplyPlacement.frame(anchor: anchor, owner: owner, screen: screen)!
            check(owner.insetBy(dx: 6, dy: 6).contains(placed), "reply clamps at owner-window edges")
        }
        let leftDisplay = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let leftOwner = NSRect(x: -1750, y: 200, width: 800, height: 600)
        let leftAnchor = NSRect(x: -1600, y: 450, width: 80, height: 16)
        let leftPopup = SidekickSelectionReplyPlacement.frame(anchor: leftAnchor, owner: leftOwner, screen: leftDisplay)!
        check(leftPopup.minY > leftAnchor.maxY && leftOwner.contains(leftPopup), "negative-origin monitor placement")
        // Given the selection's last line, the chip goes under it, so it never covers the line above
        // the selection (a "Worked for" status, the previous message); above only without room below.
        let lastLine = NSRect(x: 300, y: 260, width: 60, height: 20)
        let under = SidekickSelectionReplyPlacement.frame(anchor: middle, end: lastLine, owner: owner, screen: screen)!
        check(under.maxY < lastLine.minY && under.midX == lastLine.midX, "floating reply sits under the selection's last line")
        let nearBottom = NSRect(x: 300, y: 118, width: 60, height: 20)
        let flipped = SidekickSelectionReplyPlacement.frame(anchor: nearBottom, end: nearBottom, owner: owner, screen: screen)!
        check(flipped.minY > nearBottom.maxY && owner.contains(flipped), "no room below moves the reply above, inside the visible area")
        // Told the column and the text view's lines, the chip covers no text. Lines are 29 pt apart
        // across a paragraph break (the UI lab's 04a), too close for a 32 pt chip between them.
        let gap = SidekickSelectionReplyPlacement.gap
        let window = NSRect(x: 0, y: 100, width: 1100, height: 680)
        let prose = NSRect(x: 234, y: 500, width: 632, height: 20)
        let proseLine = NSRect(x: 234, y: 501, width: 590, height: 18)
        let proseEnd = NSRect(x: 296, y: 501, width: 150, height: 18)
        let lineAbove = NSRect(x: 234, y: 530, width: 620, height: 18), lineBelow = NSRect(x: 234, y: 472, width: 260, height: 18)
        let margin = SidekickSelectionReplyPlacement.frame(anchor: proseEnd, end: proseEnd, column: prose, text: prose,
            lines: [proseLine], owner: window, screen: screen)!
        check(margin.minX >= prose.maxX + gap && margin.midY == proseEnd.midY && window.insetBy(dx: 6, dy: 6).contains(margin),
              "floating reply sits in the trailing margin beside the selection's last line")
        check(![lineAbove, proseLine, lineBelow].contains { $0.intersects(margin) }, "floating reply in the margin covers no line")
        let window840 = NSRect(x: 0, y: 100, width: 840, height: 680), narrowColumn = NSRect(x: 104, y: 500, width: 632, height: 20)
        let near = SidekickSelectionReplyPlacement.frame(anchor: proseEnd, end: NSRect(x: 166, y: 501, width: 150, height: 18),
            column: narrowColumn, text: narrowColumn, lines: [NSRect(x: 104, y: 501, width: 630, height: 18)], owner: window840, screen: screen)!
        check(near.minX >= narrowColumn.maxX && near.maxX <= window840.maxX - 6, "a margin narrower than the gap still holds the reply clear of the column")
        // A column with no margin to spare: after the last line's own text, when it stops short.
        let tight = NSRect(x: 0, y: 100, width: 660, height: 680), tightColumn = NSRect(x: 14, y: 500, width: 632, height: 20)
        let shortLine = NSRect(x: 14, y: 501, width: 380, height: 18), shortEnd = NSRect(x: 60, y: 501, width: 120, height: 18)
        let after = SidekickSelectionReplyPlacement.frame(anchor: shortEnd, end: shortEnd, column: tightColumn, text: tightColumn,
            lines: [shortLine], owner: tight, screen: screen)!
        check(after.minX >= shortLine.maxX + gap && after.maxX <= tight.maxX - 6 && after.midY == shortEnd.midY
              && after.minY >= tightColumn.minY - gap && after.maxY <= tightColumn.maxY + gap,
              "without a margin the reply sits after the last line's own text, within its paragraph")
        check(!after.intersects(NSRect(x: 14, y: 472, width: 632, height: 18)), "after the last line the reply clears the next paragraph")
        let fullAbove = NSRect(x: 14, y: 519, width: 630, height: 18)
        let crowded = SidekickSelectionReplyPlacement.frame(anchor: shortEnd, end: shortEnd, column: tightColumn,
            text: NSRect(x: 14, y: 500, width: 632, height: 38), lines: [fullAbove, shortLine], owner: tight, screen: screen)!
        check(!crowded.intersects(fullAbove) && crowded.maxY < shortEnd.minY && crowded.midX == shortEnd.midX,
              "a longer line above keeps the reply out of its text, falling back under the selection")
        let fullEnd = NSRect(x: 60, y: 501, width: 120, height: 18)
        let full = SidekickSelectionReplyPlacement.frame(anchor: fullEnd, end: fullEnd, column: tightColumn, text: tightColumn,
            lines: [NSRect(x: 14, y: 501, width: 630, height: 18)], owner: tight, screen: screen)!
        check(full.maxY < fullEnd.minY && full.midX == fullEnd.midX, "a full last line without a margin falls back under the selection")
        // A table cell's neighbours lie beside it: the chip stays inside the cell, or past the table.
        let tableBox = NSRect(x: 14, y: 400, width: 632, height: 200), cell = NSRect(x: 26, y: 500, width: 300, height: 20)
        let cellLine = NSRect(x: 26, y: 501, width: 60, height: 18), cellEnd = NSRect(x: 26, y: 501, width: 40, height: 18)
        let inCell = SidekickSelectionReplyPlacement.frame(anchor: cellEnd, end: cellEnd, column: tableBox, text: cell,
            lines: [cellLine], owner: tight, screen: screen)!
        check(inCell.maxX <= cell.maxX && inCell.minX >= cellLine.maxX + gap, "a table cell keeps the reply inside it")
        let wideTable = NSRect(x: 234, y: 400, width: 632, height: 200), wideCell = NSRect(x: 246, y: 500, width: 110, height: 20)
        let pastTable = SidekickSelectionReplyPlacement.frame(anchor: cellEnd, end: NSRect(x: 246, y: 501, width: 40, height: 18),
            column: wideTable, text: wideCell, lines: [NSRect(x: 246, y: 501, width: 100, height: 18)], owner: window, screen: screen)!
        check(pastTable.minX >= wideTable.maxX + gap, "with room, a table cell's reply goes past the table")
        // A margin narrower than the labelled chip but wider than its 32 pt circle: the popup's first
        // ask (the labelled chip, clear of text) finds nothing, and the arrow alone fits the margin.
        let window720 = NSRect(x: 0, y: 100, width: 720, height: 680), column720 = NSRect(x: 44, y: 500, width: 632, height: 20)
        let fullLine720 = NSRect(x: 44, y: 501, width: 630, height: 18), end720 = NSRect(x: 90, y: 501, width: 120, height: 18)
        let compactSize = SidekickSelectionReplyPlacement.compactSize
        check(SidekickSelectionReplyPlacement.clearFrame(anchor: end720, end: end720, column: column720, text: column720,
              lines: [fullLine720], owner: window720, screen: screen) == nil,
              "the labelled reply claimed a clear spot beside a full line in a narrow margin")
        let arrow = SidekickSelectionReplyPlacement.clearFrame(anchor: end720, end: end720, column: column720, text: column720,
            lines: [fullLine720], owner: window720, screen: screen, size: compactSize)
        check(arrow.map { $0.size == compactSize && $0.minX >= column720.maxX && $0.maxX <= window720.maxX - 6
                          && $0.midY == end720.midY && !$0.intersects(fullLine720) } == true,
              "a narrow margin did not take the reply arrow alone, beside the selection's last line")
        check(SidekickSelectionReplyPlacement.clearFrame(anchor: fullEnd, end: fullEnd, column: tightColumn, text: tightColumn,
              lines: [NSRect(x: 14, y: 501, width: 630, height: 18)], owner: tight, screen: screen, size: compactSize) == nil,
              "the reply arrow claimed a margin narrower than itself")
        check(SidekickSelectionReplyPlacement.frame(anchor: .zero, owner: owner, screen: screen) == nil,
              "empty anchor cannot open a popup")
        check(SidekickSelectionReplyPlacement.frame(anchor: NSRect(x: 2000, y: 2000, width: 20, height: 20), owner: owner, screen: screen) == nil,
              "offscreen selection cannot create detached popup")
        var observations: [Bool] = []
        textView.onSelectionChange = { observations.append($0) }
        textView.reportSelection(true); textView.reportSelection(true); textView.reportSelection(false)
        for _ in 0..<5 { await Task.yield() }
        check(observations == [true, false], "selection observations are content-free and deduplicated")

        check(SidekickMarkdown(markdown: "x").onReplyToMessage == nil, "Markdown whole-reply callback defaults to nil")
        check(SidekickPlainText(text: "x").onReplyToMessage == nil, "plain whole-reply callback defaults to nil")
        let messageSource = "# Draft **café**\r\n\r\n- Keep 👩🏽‍💻 and e\u{301} as typed.\n`raw *code*`\n"
        let messageFragment = first(messageSource)
        textView.source = messageSource; textView.fragment = messageFragment
        textView.textStorage?.setAttributedString(SidekickSelectableMarkdown.styled(messageFragment.attributed, style: normal))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        var messageReplies = 0
        textView.onReplyToMessage = { messageReplies += 1 }
        let systemMenu = NSMenu()
        let selectionCopy = NSMenuItem(title: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        selectionCopy.target = textView; systemMenu.addItem(selectionCopy)
        let messageMenu = textView.messageContextMenu(addingTo: systemMenu)
        let wholeCopy = messageMenu.items.first { $0.identifier?.rawValue == "sidekick.copyMessage" }!
        let wholeReply = messageMenu.items.first { $0.identifier?.rawValue == "sidekick.replyMessage" }!
        check(wholeCopy.title == "Copy message" && wholeReply.title == "Reply to message", "whole actions available with zero selection")
        check(!messageMenu.items.contains { $0.title == "Reply to selection" }, "zero selection does not offer selected reply")
        check(messageMenu.items.contains { $0 === selectionCopy } && selectionCopy.action == NSSelectorFromString("copy:"),
              "native Copy selection action remains untouched")
        check(textView.validateUserInterfaceItem(wholeCopy) && textView.validateUserInterfaceItem(wholeReply),
              "whole-message actions validate without a selected range")
        _ = textView.messageContextMenu(addingTo: messageMenu)
        check(messageMenu.items.filter { $0.title == "Copy message" }.count == 1
              && messageMenu.items.filter { $0.title == "Reply to message" }.count == 1,
              "reused native menu does not duplicate message actions")
        textView.perform(wholeReply.action!, with: wholeReply)
        check(messageReplies == 1, "native whole-message Reply target invokes callback")
        let privatePasteboard = NSPasteboard.withUniqueName()
        defer { privatePasteboard.releaseGlobally() }
        check(textView.copyMessage(to: privatePasteboard), "whole-copy handler writes to supplied pasteboard")
        check(privatePasteboard.string(forType: .string)?.utf8.elementsEqual(messageSource.utf8) == true,
              "whole-copy preserves exact Unicode Markdown CRLF and whitespace bytes")

        textView.setSelectedRange((messageFragment.text as NSString).range(of: "café"))
        _ = textView.messageContextMenu(addingTo: messageMenu)
        check(messageMenu.items.contains { $0.title == "Reply to selection" }
              && messageMenu.items.contains { $0 === selectionCopy }, "selection offers both reply modes and native selection Copy")
        check(selectionCopy.target === textView && selectionCopy.action == NSSelectorFromString("copy:")
              && (textView.string as NSString).substring(with: textView.selectedRange()) == "café",
              "native Copy selection keeps its original target and selected rendered range")
        textView.perform(NSSelectorFromString("replyToSelection"))
        check(actualReply == "café" && messageReplies == 1, "selected exact-source Reply remains separate from whole reply")

        textView.source = largeDocument.source; textView.fragment = fragments(largeDocument)[0]
        check(textView.copyMessage(to: privatePasteboard)
              && privatePasteboard.string(forType: .string)?.utf8.elementsEqual(large.utf8) == true,
              "whole-copy includes original content beyond bounded parsed prefix")
        textView.onReplyToMessage = nil
        _ = textView.messageContextMenu(addingTo: messageMenu)
        check(!messageMenu.items.contains { $0.title == "Reply to message" }
              && messageMenu.items.contains { $0.title == "Copy message" }, "optional whole callback controls reply only")
        final class ReplyLifetime { var calls = 0 }
        weak var retainedReplyOwner: ReplyLifetime?
        do {
            let owner = ReplyLifetime(); retainedReplyOwner = owner
            textView.onReplyToMessage = { owner.calls += 1 }
        }
        check(retainedReplyOwner != nil, "whole callback retains its action owner before dismantle")
        SidekickSelectableMarkdown.dismantleNSView(textView, coordinator: ())
        check(textView.onReplyToMessage == nil && textView.onReply == nil && textView.onSelectionChange == nil,
              "dismantle releases all message and selection callbacks")
        check(retainedReplyOwner == nil, "whole-reply action owner released on dismantle")

        // A mounted transcript can be visually hidden behind the overview/Settings. Exercise
        // the real native view and selectors so queued actions cannot bypass that disablement.
        let inertView = SidekickMarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        inertView.isEditable = false; inertView.isSelectable = true; inertView.delegate = inertView
        inertView.source = messageSource; inertView.fragment = messageFragment
        inertView.textStorage?.setAttributedString(SidekickSelectableMarkdown.styled(messageFragment.attributed, style: normal))
        let preservedSelection = (messageFragment.text as NSString).range(of: "café")
        inertView.setSelectedRange(preservedSelection)
        let preservedText = inertView.string
        var inertWholeReplies = 0
        var inertSelectedReplies: [String] = []
        inertView.onReplyToMessage = { inertWholeReplies += 1 }
        inertView.onReply = { inertSelectedReplies.append($0) }
        let queuedMenu = inertView.messageContextMenu(addingTo: NSMenu())
        let queuedWhole = queuedMenu.items.first { $0.title == "Reply to message" }!
        let queuedSelected = queuedMenu.items.first { $0.title == "Reply to selection" }!
        let queuedActions = Task { @MainActor in
            _ = inertView.perform(queuedWhole.action!, with: queuedWhole)
            _ = inertView.perform(queuedSelected.action!)
        }
        inertView.interactionEnabled = false
        check(inertView.hitTest(NSPoint(x: 20, y: 20)) == nil, "disabled native text ignores hit testing")
        check(inertView.isAccessibilityHidden(), "disabled native text is hidden from accessibility")
        check(!inertView.acceptsFirstResponder, "disabled native text refuses first-responder eligibility")
        check(!inertView.becomeFirstResponder(), "disabled native text refuses direct first-responder attempt")
        let inertClick = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        check(inertView.menu(for: inertClick) == nil, "disabled native text does not open context menu")
        await queuedActions.value
        check(inertWholeReplies == 0 && inertSelectedReplies.isEmpty, "queued whole and selected replies cannot run while disabled")
        check(inertView.string == preservedText && inertView.source.utf8.elementsEqual(messageSource.utf8)
              && inertView.selectedRange() == preservedSelection, "disablement preserves rendered text exact source and selection")
        inertView.interactionEnabled = true
        check(!inertView.isAccessibilityHidden(), "reenabled native text returns to accessibility")
        check(inertView.acceptsFirstResponder, "reenabled native text restores responder eligibility")
        check(inertView.hitTest(NSPoint(x: 20, y: 20)) != nil, "reenabled native text restores hit testing")
        check(inertView.string == preservedText && inertView.source.utf8.elementsEqual(messageSource.utf8)
              && inertView.selectedRange() == preservedSelection, "reenabling preserves text source and original selection")
        inertView.perform(queuedSelected.action!)
        check(inertSelectedReplies == ["café"] && inertWholeReplies == 0, "reenabled selected Reply restores exact-source callback")
        check(inertView.selectedRange().length == 0, "restored selected Reply clears the consumed selection")
        inertView.setSelectedRange(preservedSelection)
        inertView.perform(queuedWhole.action!, with: queuedWhole)
        check(inertWholeReplies == 1 && inertSelectedReplies == ["café"], "reenabled whole Reply restores only its own callback")
        check(inertView.selectedRange().length == 0, "restored whole Reply clears the consumed selection")
        SidekickSelectableMarkdown.dismantleNSView(inertView, coordinator: ())
        print("Sidekick Markdown: \(checks) checks passed")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="sentient-markdown-tests-") as temporary:
    directory = Path(temporary)
    fixture = directory / "Fixture.swift"
    fixture.write_text(FIXTURE)
    binary = directory / "markdown-tests"
    subprocess.run([
        "xcrun", "swiftc", *platform_plugin_flags(), "-parse-as-library", "-swift-version", "5",
        "-default-isolation", "MainActor", "-enable-upcoming-feature", "NonisolatedNonsendingByDefault",
        str(SOURCES / "SidekickMarkdownDocument.swift"), str(SOURCES / "SidekickMarkdown.swift"),
        str(fixture), "-o", str(binary),
    ], check=True, cwd=ROOT, timeout=90)
    subprocess.run([str(binary)], check=True, cwd=directory, timeout=30)
