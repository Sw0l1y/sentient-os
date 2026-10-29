//
//  LetterBody.swift
//  Sentient OS macOS  ·  Views/
//
//  The letter renderer: the editorial Markdown subset our letters use (the gift letter, research
//  briefings), set as system document text, line by line: `##`/`###` section headings, bullets
//  (`✦ `/`- `/`* `/`• `), numbered items, `---` rules, a closing sign-off line, and plain
//  paragraphs with `**bold**` and links inline. A blank line is a paragraph break. `neutral`
//  (research notes) draws the bullet glyphs in secondary ink instead of the accent.
//  (`# H1` is promoted to the card title upstream, but a stray one still renders defensively.)
//  Shared by the letter sheet (HomeLetterSheet) and the saved share image (GiftShareImage), so what
//  you read is exactly what you save. It names no fixed color: the poster renders it in its own
//  light context, the sheet in the system appearance. SPEC-D1 S12.
//

import SwiftUI
import AppKit

struct LetterBody: View {
    let text: String
    let accent: Color
    var neutral = false   // research notes: secondary bullet glyphs instead of the accent

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, raw in
                letterBlock(raw.trimmingCharacters(in: .whitespaces))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .tint(Color(nsColor: .linkColor))       // inline Markdown links read as links, not accent
    }

    @ViewBuilder
    private func letterBlock(_ line: String) -> some View {
        if line.isEmpty {
            Color.clear.frame(height: 2)                              // a paragraph break
        } else if line.hasPrefix("### ") {
            Text(Self.inline(String(line.dropFirst(4))))
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.top, Space.xs)
                .accessibilityAddTraits(.isHeader)
        } else if line.hasPrefix("## ") {
            Text(Self.inline(String(line.dropFirst(3))))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.top, Space.s)
                .accessibilityAddTraits(.isHeader)
        } else if line.hasPrefix("# ") {
            Text(Self.inline(String(line.dropFirst(2))))             // a stray title, defensive
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.top, Space.xs)
                .accessibilityAddTraits(.isHeader)
        } else if Self.isRule(line) {
            Divider()                                                 // a `---` rule
                .padding(.vertical, Space.xs)
        } else if let bullet = Self.bulletText(line) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("•")
                    .font(.body)
                    .foregroundStyle(neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
                    .accessibilityHidden(true)
                Text(Self.inline(bullet))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let (number, item) = Self.numberedText(line) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("\(number).")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(Self.inline(item))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if Self.isSignoff(line) {
            Text(Self.inline(line))                                  // "-- Your Sentient"
                .font(.body.italic())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, Space.s)
        } else {
            Text(Self.inline(line))
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "✦ …" (tolerating a stray word-joiner / nbsp the model sometimes slips in) → the bullet's text;
    /// nil if the line isn't a bullet. Standard-Markdown bullets ("- " / "* " / "• ") are accepted
    /// too — models slip into vanilla Markdown no matter what the prompt says — and every flavour
    /// renders as the same bullet. "- " needs its space so a "-- your Sentient" sign-off
    /// (and "**bold**"-opening lines for "* ") can never be mistaken for a bullet.
    private static func bulletText(_ line: String) -> String? {
        let rest: Substring
        if line.first == "✦" || line.first == "•" {
            rest = line.dropFirst()
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            rest = line.dropFirst(2)
        } else { return nil }
        let text = rest.drop { $0 == " " || $0 == "\t" || $0 == "\u{2060}" || $0 == "\u{00A0}" }
        return text.isEmpty ? nil : String(text)
    }

    /// "1. …" → the item's number + text; nil if the line isn't a numbered item.
    private static func numberedText(_ line: String) -> (String, String)? {
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex,
              line[line.startIndex..<dot].allSatisfy(\.isNumber) else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.first == " " else { return nil }
        let text = rest.drop { $0 == " " }
        return text.isEmpty ? nil : (String(line[..<dot]), String(text))
    }

    /// A `---` horizontal rule (3+ dashes and nothing else). Checked BEFORE the sign-off, which
    /// would otherwise claim it via its "--" prefix.
    private static func isRule(_ line: String) -> Bool {
        line.count >= 3 && line.allSatisfy { $0 == "-" }
    }

    /// A closing line like "-- Your Sentient" / "— your Sentient" (line-start only, so inline em-dashes
    /// mid-paragraph aren't mistaken for a sign-off).
    private static func isSignoff(_ line: String) -> Bool {
        line.hasPrefix("--") || line.hasPrefix("—") || line.hasPrefix("– ")
    }

    /// Inline-markdown parse (**bold**, links) so letters can carry a skimmable bold rail.
    private static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

#Preview("Letter body") {
    let sample = """
    ## Who she is
    **Priya Iyer, Partner at Northbeam Capital**; leads early-stage consumer AI.

    ## Lead with
    - Traction: **2,500 waitlist signups in 24 hours** from one post.
    - Moat: the full on-device pipeline runs on real data today.

    ### Likely questions
    1. Why won't Apple do this? Apple Intelligence can't read WhatsApp.
    2. Business model? Free consumer wedge.

    ---
    -- Your Sentient
    """
    return HStack(spacing: 0) {
        LetterBody(text: sample, accent: .accentColor)
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .environment(\.colorScheme, .light)
        LetterBody(text: sample, accent: .accentColor, neutral: true)
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .environment(\.colorScheme, .dark)
    }
    .frame(width: 900)
}
