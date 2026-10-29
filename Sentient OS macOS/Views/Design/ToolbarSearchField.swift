//
//  ToolbarSearchField.swift
//  Sentient OS macOS
//
//  The only search UI on retained pages (Home, Knowledge), never `.searchable` there (SPEC-00 3.9).
//  An NSSearchField: every keystroke writes `text`, Return calls `onSubmit`, Esc clears the text and
//  calls `onCancel`, and a change of `focusRequest` makes the field first responder. Use it inside
//  the page's gated toolbar:
//
//      if isPresented && searching {
//          ToolbarItem(placement: .primaryAction) {
//              ToolbarSearchField(text: $query, prompt: "Search Conversation",
//                                 identifier: "sidekick.history.search", focusRequest: focusTick)
//          }
//      }
//

import SwiftUI
import AppKit

struct ToolbarSearchField: NSViewRepresentable {
    @Binding private var text: String
    private let prompt: String
    private let identifier: String
    private let width: CGFloat
    private let focusRequest: Int
    private let onSubmit: () -> Void
    private let onCancel: () -> Void

    init(text: Binding<String>, prompt: String, identifier: String, width: CGFloat = 220,
         focusRequest: Int = 0, onSubmit: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {}) {
        self._text = text
        self.prompt = prompt
        self.identifier = identifier
        self.width = width
        self.focusRequest = focusRequest
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.sendsSearchStringImmediately = true
        field.placeholderString = prompt
        field.setAccessibilityIdentifier(identifier)
        field.stringValue = text
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != prompt { field.placeholderString = prompt }
        field.setAccessibilityIdentifier(identifier)
        // A field created with a non-zero request (the toolbar item just appeared because search was
        // asked for) takes focus too: the coordinator starts from 0.
        if focusRequest != context.coordinator.focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.requestFocus()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Field, context: Context) -> CGSize? {
        CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    /// The search field; it takes a pending focus request once it is in a window.
    final class Field: NSSearchField {
        private var wantsFocus = false

        func requestFocus() {
            wantsFocus = true
            DispatchQueue.main.async { [weak self] in self?.applyFocus() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyFocus()
        }

        private func applyFocus() {
            guard wantsFocus, let window else { return }
            wantsFocus = false
            window.makeFirstResponder(self)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ToolbarSearchField
        var focusRequest = 0

        init(_ parent: ToolbarSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            write(field.stringValue)
        }

        /// The field's action: sent per keystroke (sendsSearchStringImmediately) and when its ✕ clears it.
        @objc func searchChanged(_ sender: NSSearchField) {
            write(sender.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                write(control.stringValue)
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                control.stringValue = ""
                write("")
                parent.onCancel()
                return true
            }
            return false
        }

        private func write(_ value: String) {
            if parent.text != value { parent.text = value }
        }
    }
}

#Preview("Toolbar search field") {
    @Previewable @State var query = ""
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(alignment: .leading, spacing: Space.s) {
                ToolbarSearchField(text: $query, prompt: "Search Notes", identifier: "preview.search")
                Text(query.isEmpty ? "Type to search" : "Searching for “\(query)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 560)
}
