#!/usr/bin/env python3
"""Measure production notch message layout against its real native Markdown renderer.

No app/window/provider launch. TextKit measurement and the bounded layout/cache are real.
The recovery card's layout (question, question with an error, error alone) is checked against
the real SidekickRecoveryView laid out in a window that is never ordered in.
"""
from pathlib import Path
import subprocess
from swift_fixture import platform_plugin_flags
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "Sentient OS macOS"

FIXTURE = r'''
import AppKit

@main enum NotchLayoutTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        guard value() else { fatalError("FAIL: " + label) }
        checks += 1
    }
    static func size(_ text: String, width: CGFloat = 520, height: CGFloat = 286) -> CGSize {
        SidekickNotchMessageLayout(markdown: text, maximumSize: CGSize(width: width, height: height),
            cameraHeight: 37, outerTopPad: 0, outerBottomPad: 4, horizontalPad: 18).size
    }
    static func nativeParagraph(_ text: String, width: CGFloat, heading: Int? = nil) -> CGFloat {
        let document = SidekickMarkdownDocument(markdown: text)
        guard case .text(let fragment, _) = document.blocks[0] else { fatalError("expected text fixture") }
        let style = SidekickSelectableMarkdown.Style(compact: true, heading: heading,
            code: false, bold: false, alignment: .left)
        let view = SidekickMarkdownTextView()
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textStorage?.setAttributedString(SidekickSelectableMarkdown.styled(fragment.attributed, style: style))
        return SidekickSelectableMarkdown.measuredSize(view, proposedWidth: width, style: style, wrapping: true)!.height
    }
    static func main() {
        let fixture = "You're free **2:30–4:00 PM tomorrow**. That gives you a quiet 90-minute block after your design review.\n\nI can help protect that time when you're ready."
        let short = size(fixture)
        check(short.width == 520 && short.height >= 190 && short.height < 250,
              "actual two-paragraph preview sheds oversized empty reading space")
        check((190...200).contains(size("Done.").height), "single native line reserves compact chrome without growing to maximum")
        check(size("").height == 190, "empty response retains minimum stable controls")
        check(size(fixture) == short, "cached repeated hit testing returns identical geometry")
        check(size(fixture, width: 360).height >= short.height, "narrower display never undermeasures wrapping")
        check(size(fixture).height == short.height, "width-specific cache does not corrupt original measurement")

        let plain = "A compact response with **important details**, café, and a link to [the source](https://example.com)."
        let native = nativeParagraph(plain, width: 484)
        // Actual camera/header/footer/spacing/padding together occupy177 points. The native
        // renderer's independent NSTextView measurement must fit the layout's text allowance.
        check(size(plain).height >= 177 + native, "native formatted paragraph fits without clipping")
        check(size(plain).height <= 179 + native, "paragraph measurement does not introduce excess dead space")
        let heading = "# A small heading"
        check(size(heading).height >= 177 + 4 + nativeParagraph(heading, width: 484, heading: 1),
              "heading uses shared compact font and heading inset")
        let list = "- A sufficiently long list item with its own marker that wraps around a narrow message preview without clipping the text beside it."
        check(size(list, width: 360).height >= size(list).height, "list indentation participates in wrapping")
        let quote = "> > Nested quotation that keeps its visible left inset when calculating the available message width."
        check(size(quote, width: 360).height > 190, "nested quote is measured within its decoration inset")

        check(size(String(repeating: "x", count: 1_001)).height == 286, "long source bypasses parser and keeps bounded maximum")
        check(size(String(repeating: "😀", count: 501)).height == 286, "Unicode parse bound is conservative")
        check(size("a" + String(repeating: "\u{301}", count: 5_000)).height == 286,
              "pathological combining grapheme cannot bypass parse budget")
        check(size("```swift\nprint(1)\n```").height == 286, "code scroll/header chrome retains maximum")
        check(size("| A | B |\n|---|---|\n| one | two |").height == 286, "table grid keeps bounded reading surface")
        check(size(String(repeating: "A paragraph.\n\n", count: 50)).height == 286,
              "many short blocks cannot exceed the maximum")
        check(size(fixture, height: 160).height == 160, "available screen height caps measured preview")
        check(size("Done.", height: 120).height == 120, "small displays take precedence over preferred minimum")
        check(size("Changed.").height < size(fixture).height, "message content changes invalidate cached height")
        print("PASS: \(checks) Sidekick notch layout checks; fixture height \(short.height)pt")
    }
}
'''


RECOVERY_FIXTURE = r'''
import AppKit
import SwiftUI
extension EnvironmentValues { @Entry var sidekickReduceMotionOverride: Bool? = nil }
enum Motion { static func gated(_ animation: Animation, reduceMotion: Bool) -> Animation? { reduceMotion ? nil : animation } }
enum CodexAuth { static let upgradeURL = URL(string: "https://example.invalid")! }
enum SettingsPane { case frontierModel }
enum HomeWindowOpening { enum Page { case settings }; static func open(_ page: Page, settingsPane: SettingsPane) {} }
enum NotchPhase { case recovery }
// The production values the recovery layout reads (NotchView.swift: hPad 18, topPad 0, bottomPad 4,
// a 32 pt camera band, and the 520 x 240 recovery maximum on a 1440 x 900 display).
struct NotchMetrics {
    var hPad: CGFloat { 18 }
    var topRowHeight: CGFloat { 32 }
    var topPad: CGFloat { 0 }
    var bottomPad: CGFloat { 4 }
    func size(for phase: NotchPhase) -> CGSize { CGSize(width: 520, height: 240) }
}

@main @MainActor enum RecoveryLayoutTests {
    static func scrollViews(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }
    /// The layout's scroll and view heights against the drawn view's: the label row, the error and
    /// the question must all be in both, or the card clips or leaves a gap.
    static func check(_ name: String, _ content: SidekickRecoveryContent) {
        let metrics = NotchMetrics()
        let recovery = SidekickRecovery()
        recovery.present(content) { _ in }
        let layout = SidekickRecoveryLayout(content: content, metrics: metrics)
        let width = layout.size.width - 2 * metrics.hPad
        let host = NSHostingView(rootView: SidekickRecoveryView(recovery: recovery, content: content, layout: layout)
            .frame(width: width).background(.black))
        // Never ordered in: an offscreen window only gives the hosting view a layout pass.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: host.fittingSize.height)
        host.layoutSubtreeIfNeeded()
        guard let outer = scrollViews(host).max(by: { $0.frame.height < $1.frame.height }), let document = outer.documentView else {
            fatalError("FAIL: \(name): the recovery view drew no scroll view")
        }
        let view = host.fittingSize.height
        let expected = layout.size.height - metrics.topRowHeight - metrics.topPad - metrics.bottomPad
        guard abs(document.frame.height - layout.scrollHeight) <= 1, abs(view - expected) <= 1 else {
            fatalError("FAIL: \(name): layout scroll \(layout.scrollHeight) / view \(expected), drawn \(document.frame.height) / \(view)")
        }
        recovery.cancel()
        window.contentView = nil
    }
    static func main() throws {
        check("question", .clarification(try SidekickQuestion(error: nil,
            question: "Would you like me to protect the longer afternoon block or keep your calendar open?",
            answers: ["Protect the afternoon", "Keep it open"])))
        check("question+error", .clarification(try SidekickQuestion(error: "The calendar refused the first write.",
            question: "Should I try the other calendar?", answers: ["Yes", "No"])))
        check("error", .failure(id: UUID(), error: "I couldn’t finish this step. Add a detail to help me continue."))
        print("PASS: 3 notch recovery layout checks")
    }
}
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="sentient-notch-layout-test-") as temporary:
        directory = Path(temporary)
        fixture = directory / "NotchLayoutTests.swift"
        fixture.write_text(FIXTURE)
        executable = directory / "notch-layout-tests"
        subprocess.run([
            "swiftc", *platform_plugin_flags(), "-swift-version", "5", "-default-isolation", "MainActor",
            "-enable-upcoming-feature", "NonisolatedNonsendingByDefault", "-warnings-as-errors", "-parse-as-library",
            str(APP / "Views/Sidekick/SidekickMarkdownDocument.swift"),
            str(APP / "Views/Sidekick/SidekickMarkdown.swift"),
            str(APP / "Notch Magic/SidekickNotchMessageLayout.swift"), str(fixture),
            "-o", str(executable),
        ], check=True, timeout=60)
        subprocess.run([str(executable)], check=True, timeout=20)

        recovery_fixture = directory / "RecoveryLayoutTests.swift"
        recovery_fixture.write_text(RECOVERY_FIXTURE)
        recovery = directory / "recovery-layout-tests"
        subprocess.run([
            "swiftc", *platform_plugin_flags(), "-swift-version", "5", "-default-isolation", "MainActor",
            "-enable-upcoming-feature", "NonisolatedNonsendingByDefault", "-parse-as-library",
            str(APP / "Notch Magic/SidekickConversationStore.swift"),
            str(APP / "Views/Sidekick/SidekickMarkdownDocument.swift"),
            str(APP / "Views/Sidekick/SidekickMarkdown.swift"),
            str(APP / "Notch Magic/SidekickNotchMessageLayout.swift"),
            str(APP / "Notch Magic/SidekickNotchMessageView.swift"),
            str(APP / "Notch Magic/SidekickRecovery.swift"),
            str(APP / "Notch Magic/SidekickRecoveryView.swift"), str(recovery_fixture),
            "-o", str(recovery),
        ], check=True, timeout=120)
        subprocess.run([str(recovery)], check=True, timeout=20)


if __name__ == "__main__":
    main()
