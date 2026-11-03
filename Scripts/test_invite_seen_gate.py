#!/usr/bin/env python3
"""Check that the once-only invite offer waits until its notice slot is in the reader's view.

Presenting the invite spends it for good: InviteBanner sets the code and calls
`program.markBannerShown()`, which persists `invites.bannerShown`, and the offer retires 20 s later.
Home's notice slot used to dock above the page, so "the Home window is key" meant "the offer is on
screen". On Today the slot is now the last item of the turn inside the scrolling column
(FIX3-NOTES, "Notice in Today"), so a reader scrolled up would have the offer spent below the fold.
No lab can drive the invite (InviteProgram.refresh goes to the network), so this reads the wiring:

  InviteBanner.swift  reads `noticeSlotInView` as `inView`, restarts its presentation task when it
                      changes, returns at the top of that task while it is false, stops after the
                      refresh if the task was cancelled meanwhile (the reader scrolled away), and
                      retires the offer in its own task keyed to the code, never in the presentation
                      task (restarting that must not strand an offer).
  HomeToday.swift     sets `noticeSlotInView` on the notices from `atEnd`, which follows
                      `viewport.atEnd`.

Comments are stripped first, so a commented-out line does not count. The checker is first run on a
planted copy of the code before the gate, which it must reject on every rule, and on single
mutations of the live files, each of which it must reject on exactly its own rule. No UI, providers
or user data.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "Sentient OS macOS"
BANNER = APP / "Invitations" / "InviteBanner.swift"
TODAY = APP / "Views" / "HomeToday.swift"

RULES = {"banner-reads-slot", "task-restarts", "gate-before-spend", "cancel-after-refresh",
         "retire-apart", "retire-exists", "today-sets-slot", "today-tracks-end"}


def function_body(source: str, signature: str) -> str:
    """The text of a 4-space-indented member function, from its signature to its closing brace."""
    start = source.index(signature)
    end = source.index("\n    }\n", start)
    return source[start:end]


def problems(banner: str, today: str) -> list[str]:
    banner = re.sub(r"//[^\n]*", "", banner)
    today = re.sub(r"//[^\n]*", "", today)
    found = []
    if not re.search(r"@Environment\(\\\.noticeSlotInView\) private var inView\b", banner):
        found.append("banner-reads-slot: InviteBanner does not read noticeSlotInView as inView")
    task = re.search(r"\.task\(id: ([^)]*)\) \{ await presentWhenReady\(\) \}", banner)
    if not task or not re.search(r"\binView\b", task.group(1)) or not re.search(r"\bcanPresent\b", task.group(1)):
        found.append("task-restarts: the presentation task does not restart when inView changes")
    try:
        present = function_body(banner, "private func presentWhenReady() async {")
    except ValueError:
        present = ""
    # The guard at the function's top level, before the loop: not in a branch, not after a spend.
    gate = re.search(r"\n        guard inView else \{ return \}\n", present)
    loop = present.find("\n        while ")
    spend = present.find("program.markBannerShown()")
    if not gate or loop < 0 or spend < 0 or gate.start() > loop:
        found.append("gate-before-spend: presentWhenReady can mark the offer shown while its slot is out of view")
    refresh = present.rfind("await program.refresh(", 0, spend if spend >= 0 else len(present))
    if refresh < 0 or spend < 0 or not re.search(r"guard !Task\.isCancelled else \{ return \}", present[refresh:spend]):
        found.append("cancel-after-refresh: a task cancelled during the refresh can still spend the offer")
    rest = present.split("guard canPresent else { code = nil; return }", 1)[-1]
    if re.search(r"\bcode = nil\b", rest):
        found.append("retire-apart: the presentation task, which restarts, clears the offer itself")
    retire = re.search(r"\.task\(id: code\) \{(.*?)\n        \}", banner, re.S)
    if not retire or "Task.sleep(" not in retire.group(1) or not re.search(r"\bcode = nil\b", retire.group(1)):
        found.append("retire-exists: no task keyed to the code clears the offer after a sleep")
    if not re.search(r"\bnotices\s*\n\s*\.environment\(\\\.noticeSlotInView, atEnd\)", today):
        found.append("today-sets-slot: HomeToday does not set noticeSlotInView on its notices from atEnd")
    if not re.search(r"atEnd = viewport\.atEnd\b", today):
        found.append("today-tracks-end: HomeToday's atEnd does not follow viewport.atEnd")
    return found


PLANTED_BANNER = """struct InviteBanner: View {
    @Environment(\\.controlActiveState) private var controlActiveState
    var body: some View {
        ZStack { }
        .task(id: canPresent) { await presentWhenReady() }
        .onDisappear { code = nil }
    }

    private func presentWhenReady() async {
        guard canPresent else { code = nil; return }
        while !Task.isCancelled && !program.bannerShown {
            code = verifiedCode
            program.markBannerShown()
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            code = nil
        }
    }
}
"""

PLANTED_TODAY = """    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            notices
            if !kbOnly {
"""

RETIREMENT = """        .task(id: code) {
            guard code != nil else { return }
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            code = nil
        }
"""

# Single edits of the live files: (what, file, old text, new text, the one rule that must catch it).
MUTATIONS = [
    ("gate commented out", "banner", "        guard inView else { return }\n",
     "        // guard inView else { return }\n", "gate-before-spend"),
    ("gate in a side branch", "banner", "        guard inView else { return }\n",
     "        if program.snapshot == nil {\n            guard inView else { return }\n        }\n", "gate-before-spend"),
    ("no stop after the refresh", "banner", "            guard !Task.isCancelled else { return }\n", "",
     "cancel-after-refresh"),
    ("retirement back in the presentation task", "banner", "            program.markBannerShown()\n",
     "            program.markBannerShown()\n"
     "            do { try await Task.sleep(for: Self.lifetime) } catch { return }\n            code = nil\n",
     "retire-apart"),
    ("retirement deleted", "banner", RETIREMENT, "", "retire-exists"),
    ("task restarts on canPresent only", "banner", ".task(id: [canPresent, inView])", ".task(id: canPresent)",
     "task-restarts"),
    ("slot not read", "banner", r"@Environment(\.noticeSlotInView) private var inView",
     r"@Environment(\.isEnabled) private var inView", "banner-reads-slot"),
    ("tracking commented out", "today", "if atEnd != viewport.atEnd { atEnd = viewport.atEnd }",
     "// if atEnd != viewport.atEnd { atEnd = viewport.atEnd }", "today-tracks-end"),
    ("slot set to a constant", "today", r".environment(\.noticeSlotInView, atEnd)",
     r".environment(\.noticeSlotInView, true)", "today-sets-slot"),
]


def rules(found: list[str]) -> set[str]:
    return {problem.split(":", 1)[0] for problem in found}


def main() -> int:
    caught = rules(problems(PLANTED_BANNER, PLANTED_TODAY))
    if caught != RULES:
        print("FAIL: the checker did not reject the planted pre-gate code on every rule:", sorted(caught))
        return 1
    live = {"banner": BANNER.read_text(), "today": TODAY.read_text()}
    for what, file, old, new, rule in MUTATIONS:
        if live[file].count(old) != 1:
            print(f"FAIL: mutation '{what}' no longer applies to the live {file} file; update it")
            return 1
        mutated = dict(live, **{file: live[file].replace(old, new)})
        caught = rules(problems(mutated["banner"], mutated["today"]))
        if caught != {rule}:
            print(f"FAIL: mutation '{what}' was caught by {sorted(caught)}, not exactly {rule}")
            return 1
    found = problems(live["banner"], live["today"])
    if found:
        print("FAIL: the invite can be spent while its slot is out of view:")
        for problem in found:
            print("  " + problem)
        return 1
    print(f"PASS: the invite waits for its slot to be in view (planted pre-gate code rejected on "
          f"{len(RULES)} rules, {len(MUTATIONS)} live mutations each caught by exactly their rule)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
