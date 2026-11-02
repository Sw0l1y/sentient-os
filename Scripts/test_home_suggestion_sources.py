#!/usr/bin/env python3
"""Check which source a Today suggestion row's kicker names, using the production parser.

Compiles HomeSuggestionTile's `NamedSource`, `namedSource(in:)`, its name table and `key(_:)`
(Views/HomeSuggestionRow.swift) against a stub PreparedAction.Method, then checks the kicker
spellings Briefing.kickerLine and the demo decks write. Every demo-deck kicker in
Views/Briefing.swift (except the welcome letter's) must name a source, so no demo row falls back
to the sparkles glyph. No UI, providers or user data.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "Sentient OS macOS"

FIXTURE = r'''
import Foundation

struct PreparedAction {
    enum Method: Hashable { case computer, gmail, calendar, mcp, research }
}

struct Tile {
    // PRODUCTION_CODE
}

@main struct HomeSuggestionSourceChecks {
    static var failures: [String] = []
    static func check(_ kicker: String, _ expected: Tile.NamedSource?) {
        let found = Tile.namedSource(in: kicker)
        if found != expected { failures.append("\(kicker): expected \(String(describing: expected)), got \(String(describing: found))") }
    }

    static func main() {
        check("Overdue · 2 days · Gmail", .logo("GmailMark"))
        check("Press · Early next week · WhatsApp", .logo("WhatsAppMark"))
        check("Renew · Friday · Computer use", .method(.computer))
        check("Prep · 4 PM today · Researched", .method(.research))
        check("Calendar", .logo("GoogleCalendarMark"))
        // Provenance comes last: the last part that names a source wins.
        check("Group plan · Researched · WhatsApp", .logo("WhatsAppMark"))
        check("Computer use · WhatsApp", .logo("WhatsAppMark"))
        // In a joined part the first name wins.
        check("Meeting · iMessage + Calendar", .logo("IMessageMark"))
        // Nothing named: the row keeps the sparkles glyph.
        check("Renews tomorrow · $149", nil)
        check("Follow-up · Draft ready", nil)
        check("", nil)
        // DEMO_KICKERS
        for failure in failures { print("FAIL: " + failure) }
        print("home suggestion sources: \(failures.isEmpty ? "all" : "\(failures.count)") checks \(failures.isEmpty ? "passed" : "failed")")
        if !failures.isEmpty { exit(1) }
    }
}
'''


def declaration(source, signature):
    """The declaration starting at `signature`, through the brace (or a literal's bracket) closing it."""
    start = source.index(signature)
    opening = source.index("[", start + len(signature)) if signature.endswith("=") else source.index("{", start)
    close = "]" if source[opening] == "[" else "}"
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == source[opening]) - (source[end] == close)
        end += 1
    return source[start:end]


def main():
    row = (APP / "Views/HomeSuggestionRow.swift").read_text()
    code = "\n".join(declaration(row, signature).replace("private static", "static") for signature in [
        "    enum NamedSource: Equatable", "    static func namedSource(in kicker: String)",
        "    private static let namedSources: [String: NamedSource] =",
        "    private static func key(_ s: String)"])
    briefing = (APP / "Views/Briefing.swift").read_text()
    kickers = [k for k in re.findall(r'kicker: "([^"]*)"', briefing) if not k.startswith("Welcome")]
    if len(kickers) < 10:
        raise SystemExit(f"FAIL: found only {len(kickers)} demo kickers in Briefing.swift; the pattern no longer reads them")
    demo = "\n".join(
        f'        if Tile.namedSource(in: "{k}") == nil {{ failures.append("demo kicker names no source: {k}") }}'
        for k in kickers)
    fixture = FIXTURE.replace("    // PRODUCTION_CODE", code).replace("        // DEMO_KICKERS", demo)
    with tempfile.TemporaryDirectory(prefix="sentient-suggestion-sources-") as temporary:
        root = Path(temporary)
        path = root / "SuggestionSources.swift"
        path.write_text(fixture)
        executable = root / "suggestion-sources"
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                        "-parse-as-library", str(path), "-o", str(executable)], check=True, timeout=60)
        subprocess.run([str(executable)], check=True, timeout=15)
    print(f"checked {len(kickers)} demo-deck kickers from Briefing.swift")


if __name__ == "__main__":
    main()
