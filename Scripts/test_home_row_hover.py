#!/usr/bin/env python3
"""Check that hovering a Today suggestion row changes how it looks, never how it is laid out.

HomeSuggestionRow used to insert its ✕ only while hovered. Inserting it reflowed the row, and a
row that changed size under a resting pointer handed the hover to its neighbour and back on every
update: SwiftUI's hover pass and layout fed each other inside one run-loop callback, so Home froze
(FIX3-NOTES, "Hover loop"). The polish lab found it only because a pointer happened to rest in the
5 pt band where it happens. Forcing hover through `sidekickHoveredCardID` measures the settled
layout and cannot see it.

So this reads Views/HomeSuggestionRow.swift: inside HomeSuggestionRow, every use of `hovered` or
`isHovered` must sit inside a modifier that cannot move anything (opacity, hit testing, enabled,
accessibility visibility, background), apart from their declarations and the onHover setter. An
`if isHovered { … }`, or hover inside a frame or padding, fails. The checker is first run on a
planted copy of the old code, which it must reject. No UI, providers or user data.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ROW = ROOT / "Sentient OS macOS" / "Views" / "HomeSuggestionRow.swift"

# Modifiers that change appearance or input only, never size or position.
LAYOUT_NEUTRAL = {"opacity", "allowsHitTesting", "disabled", "accessibilityHidden", "background"}
HOVER = re.compile(r"\b(isHovered|hovered)\b")
ALLOWED_LINES = [
    re.compile(r"@State private var hovered\b"),
    re.compile(r"private var isHovered: Bool \{"),
    re.compile(r"\.onHover \{ hovered = \$0 \}"),
]


def enclosing_modifier(line: str, position: int) -> str | None:
    """The modifier whose parentheses directly hold `position` on this line, if any."""
    depth = 0
    for index in range(position - 1, -1, -1):
        if line[index] == ")":
            depth += 1
        elif line[index] == "(":
            if depth == 0:
                match = re.search(r"\.(\w+)\s*$", line[:index])
                return match.group(1) if match else None
            depth -= 1
    return None


def layout_uses(source: str) -> list[str]:
    """Lines of HomeSuggestionRow where hover can change layout."""
    start = source.index("struct HomeSuggestionRow: View {")
    end = source.index("// MARK: - The leading tile", start)
    found = []
    for number, line in enumerate(source[start:end].splitlines(), source[:start].count("\n") + 1):
        code = line.split("//", 1)[0]
        if not HOVER.search(code) or any(pattern.search(code) for pattern in ALLOWED_LINES):
            continue
        if any(enclosing_modifier(code, match.start()) not in LAYOUT_NEUTRAL for match in HOVER.finditer(code)):
            found.append(f"HomeSuggestionRow.swift:{number}: {line.strip()}")
    return found


def main() -> int:
    planted = """struct HomeSuggestionRow: View {
    @State private var hovered = false
    private var isHovered: Bool { hovered }
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { hovered = $0 }
    @ViewBuilder private var dismissButton: some View {
        if isHovered { dismissControl }
    }
            .padding(.top, isHovered ? 8 : 0)
            .opacity(isHovered ? 1 : 0)
            .disabled(!isHovered)
// MARK: - The leading tile
"""
    caught = layout_uses(planted)
    if len(caught) != 2 or "if isHovered" not in caught[0] or ".padding" not in caught[1]:
        print("FAIL: the checker did not reject exactly the planted `if isHovered` and hover padding:", caught)
        return 1
    problems = layout_uses(ROW.read_text())
    if problems:
        print("FAIL: hovering a Today row can change its layout:")
        for problem in problems:
            print("  " + problem)
        return 1
    print("PASS: hover changes no layout in HomeSuggestionRow (planted old code rejected)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
