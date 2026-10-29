//
//  GiftShareImage.swift
//  Sentient OS macOS  ·  Views/
//
//  The gift letter as a keepsake: a PNG poster of the welcome letter, saved to the Desktop from the
//  letter's "Save to Desktop" button. The composition is a white card, like a shared Apple Card or
//  Fitness award image: a gift tile header, the kicker and title, the letter, and a brand footer
//  (the mark, the wordmark, sentient-os.ai and the one-line pitch) so a shared image carries its
//  own attribution. The body renders through the SAME LetterBody as the on-screen letter, so what
//  you read is what you save. The poster is always light: it is an exported image (SPEC-00 1.10).
//
//  Key pieces:
//   - GiftShareView                          (the export composition; #Preview'd for design work)
//   - GiftShareImage.save(briefing:) → URL   (ImageRenderer @2x → PNG on the Desktop, never overwrites)
//

import SwiftUI
import AppKit

/// The export composition: a white card with the gift header, the letter, and the brand footer.
/// Takes the built Briefing (not raw markdown): the gift init promotes `# Title` out of the letter
/// text, so the briefing is the only faithful carrier of both.
struct GiftShareView: View {
    let briefing: Briefing

    /// The export's point width; the PNG renders at 2x (1520 px) for retina-crisp sharing.
    static let width: CGFloat = 760

    /// The brand indigo, fixed so the exported image looks the same whatever the viewer's accent.
    private static let brandIndigo = Color(red: 0x58 / 255, green: 0x56 / 255, blue: 0xD6 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.m) {
                IconTile(.giftLetter, size: 40)
                Text("A gift from Sentient")
                    .font(.title2.bold())
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Text(briefing.kicker)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(briefing.accent)
                Text(briefing.title)
                    .font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }

            LetterBody(text: briefing.letter ?? briefing.body, accent: briefing.accent)

            Divider()

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    BrandMarkView(size: 16, tint: Self.brandIndigo)
                    Text("Sentient OS")
                        .font(.headline)
                    Spacer(minLength: Space.l)
                    Text("sentient-os.ai")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Self.brandIndigo)
                }
                Text("On-device intelligence that understands your entire life to proactively help you. Open-source & free.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(40)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

enum GiftShareImage {

    enum ShareError: LocalizedError {
        case renderFailed
        var errorDescription: String? { "Couldn’t render the gift image." }
    }

    /// Render the letter as a @2x PNG and save it to the Desktop as "Gift from Sentient.png"
    /// (counter-suffixed if one already exists — a keepsake is never overwritten). Returns the file.
    @MainActor
    static func save(briefing: Briefing) throws -> URL {
        let renderer = ImageRenderer(content: GiftShareView(briefing: briefing))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: GiftShareView.width, height: nil)
        // Resolve NSColor-backed colors (separator, label) as light even while the app runs dark.
        var cgImage: CGImage?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            cgImage = renderer.cgImage
        }
        guard let cg = cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else { throw ShareError.renderFailed }

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        var url = desktop.appendingPathComponent("Gift from Sentient.png")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = desktop.appendingPathComponent("Gift from Sentient \(n).png"); n += 1
        }
        try png.write(to: url)
        Log("GiftShareImage: saved the gift keepsake → \(url.lastPathComponent) (\(png.count) bytes)")
        return url
    }
}

#Preview("Gift share image") {
    GiftShareView(briefing: Briefing(fromGiftMarkdown: """
    # The System Builder's Map

    I just analyzed your entire digital life to understand you. So much stands out :)
    ### Something you might not know about yourself

    **Your real pattern is not just building AI products; it is turning recurring ambiguity into reusable systems.**
    In IB Math AA HL, you made decision-tree guides for integration, trig, logs, complex numbers, and proofs. Sentient OS is the same reflex at startup scale: take the chaos of screenshots, files, notes, and messages, then compress it into a queryable vault.

    ## Also noticed

    ✦ Your breakout projects keep starting from Apple-shaped constraints: Writing Tools as an open-source Apple Intelligence port, and Sentient's on-device macOS layer.
    ✦ You care about assistants having the right "operating manual" for a person: you maintain prompts across ChatGPT, Claude, Gemini, and Perplexity.
    ✦ Your public technical credibility is unusually concrete: 30,000+ Writing Tools users, WIRED coverage, and a 2025 UMass Tech Challenge win.

    -- Your Sentient
    """))
}
