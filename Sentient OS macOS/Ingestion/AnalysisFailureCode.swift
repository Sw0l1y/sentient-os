// AnalysisFailureCode.swift
// A short technical code for an error: its type and nested enum case path, such as
// "LiteRTLMError.conversation.invalidResponse.nativeNull" or "ReplyFailure.invalidJSON".
// Payload strings are never copied (they can hold model output, paths or message text). The fixed
// LiteRT-LM library sentences map to short tags, and small integers (a status) are kept.
// Foundation only, so a standalone test can compile it. Used by the saved analysis report.

import Foundation

nonisolated enum AnalysisFailureCode {
    /// Constant sentences from the vendored LiteRT-LM Swift API (Vendor/LiteRTLM/swift/Conversation.swift).
    /// They are library text, never model output, so they may be named.
    private static let libraryMessages: [String: String] = [
        "Native sendMessage returned null.": "nativeNull",
        "Native get string for response returned null.": "nativeStringNull",
        "Failed to parse native response JSON.": "nativeJSON",
        "Failed to render message into string.": "renderFailed",
    ]

    static func code(for error: Error) -> String {
        var parts = [clean(String(describing: type(of: error)))]
        if Mirror(reflecting: error).displayStyle == .enum {
            describe(error, into: &parts, depth: 0)
        } else {
            let ns = error as NSError
            parts.append("code\(ns.code)")
        }
        return String(parts.filter { !$0.isEmpty }.joined(separator: ".").prefix(160))
    }

    /// An enum case: its label, then its payload; a payload-free case prints as its own name.
    private static func describe(_ value: Any, into parts: inout [String], depth: Int) {
        guard depth < 4 else { return }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .enum else { return }
        if let child = mirror.children.first {
            if let label = child.label { parts.append(clean(label)) }
            payload(child.value, into: &parts, depth: depth + 1)
        } else {
            parts.append(clean(String(describing: value)))
        }
    }

    private static func payload(_ value: Any, into parts: inout [String], depth: Int, label: String? = nil) {
        guard depth < 5 else { return }
        if let text = value as? String {
            if let tag = libraryMessages[text] { parts.append(tag) }
            return
        }
        if let number = value as? Int {
            let name = label.flatMap { $0.hasPrefix(".") ? nil : clean($0) + "=" } ?? ""
            if abs(number) < 1_000_000 { parts.append(name + String(number)) }
            return
        }
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .enum:
            describe(value, into: &parts, depth: depth)
        case .tuple:
            for child in mirror.children { payload(child.value, into: &parts, depth: depth + 1, label: child.label) }
        default:
            break   // structs, classes and collections can carry content: never described
        }
    }

    private static func clean(_ text: String) -> String {
        String(text.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }.prefix(64))
    }
}
