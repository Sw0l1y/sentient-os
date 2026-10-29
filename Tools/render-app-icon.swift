//
//  render-app-icon.swift
//  Sentient OS tools (SPEC-00 7.1 and 7.2, WP0b)
//
//  Renders the app icon (a white BrandMark on an indigo superellipse) and SentientLogo.png.
//  A standalone tool, not part of the app target. From the repo root:
//
//    swiftc -parse-as-library Tools/render-app-icon.swift \
//        "Sentient OS macOS/Views/Design/BrandMark.swift" -o .remake/build/render-app-icon \
//      && .remake/build/render-app-icon
//
//  Order: BrandMark's path self-checks (3.6) first; then each icon size is drawn directly at its
//  pixel size (never downscaled from 1024) with a glyph-only mask beside it, and the acceptance
//  alphas are measured on that mask and printed. Any failure exits non-zero.
//  The glyph is always `BrandMark(variant:).path(in:)`; this file never re-implements its geometry.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct RenderAppIcon {
    // MARK: Canvas constants (1024-unit canvas, y-down after the single flip)

    static let canvas: CGFloat = 1024
    static let center = CGPoint(x: 512, y: 512)
    static let bodyRadius: CGFloat = 412          // 824 × 824 body, 100-unit margin
    static let bodyExponent: CGFloat = 5
    static let bodySamples = 720
    static let glyphSide: CGFloat = 636
    static var glyphRect: CGRect {
        CGRect(x: center.x - glyphSide / 2, y: center.y - glyphSide / 2, width: glyphSide, height: glyphSide)
    }

    static let iconSizes = [16, 32, 64, 128, 256, 512, 1024]
    static let logoSize = 512

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func main() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let iconDir = root.appendingPathComponent("Sentient OS macOS/Assets.xcassets/AppIcon.appiconset")
        let logoDir = root.appendingPathComponent("Sentient OS macOS/Assets.xcassets/SentientLogo.imageset")
        guard FileManager.default.fileExists(atPath: iconDir.path),
              FileManager.default.fileExists(atPath: logoDir.path) else {
            fail("run from the repo root: \(iconDir.path) or \(logoDir.path) is missing")
        }

        // 1. BrandMark self-checks (SPEC-00 3.6), before anything is drawn.
        let selfCheck = BrandMark.selfCheckFailures()
        if !selfCheck.isEmpty {
            for line in selfCheck { print("BrandMark self-check FAILED: \(line)") }
            fail("\(selfCheck.count) BrandMark self-check(s) failed")
        }
        print("BrandMark self-checks: 16 passed (regular and compact, sides 100 and 16)")

        // 2. Icon sizes, each drawn at its own pixel size, each measured on its glyph-only mask.
        var failures: [String] = []
        for px in iconSizes {
            let variant: BrandMark.Variant = px <= 32 ? .compact : .regular
            let composite = makeContext(px)
            drawIcon(in: composite, px: px, variant: variant)
            let mask = makeContext(px)
            drawGlyphMask(in: mask, px: px, variant: variant)

            let probes = probePoints(variant: variant)
            let scale = CGFloat(px) / canvas
            let gapLead = alpha(mask, px: px, at: probes.gapLeading, scale: scale)
            let gapTrail = alpha(mask, px: px, at: probes.gapTrailing, scale: scale)
            let dot = alpha(mask, px: px, at: probes.dot, scale: scale)
            let ring = alpha(mask, px: px, at: probes.opposite, scale: scale)
            let gap = max(gapLead, gapTrail)
            print(String(format: "icon_%d.png (%@): gap %.3f (leading %.3f, trailing %.3f)  dot %.3f  ring opposite gap %.3f",
                         px, "\(variant)", gap, gapLead, gapTrail, dot, ring))

            // Positive controls first: a failing control means the measurement is wrong, not the icon.
            if dot <= 0.5 { failures.append("icon_\(px): control failed, dot center alpha \(dot) is not above 0.5") }
            if ring <= 0.5 { failures.append("icon_\(px): control failed, ring opposite the gap alpha \(ring) is not above 0.5") }
            if gap >= 0.5 { failures.append("icon_\(px): gap between dot and cap alpha \(gap) is not below 0.5") }

            if px == 1024 {
                let outside = alpha(composite, px: px, pixelX: 8, pixelY: 8)
                let inside = alpha(composite, px: px, pixelX: 512, pixelY: 150)
                print(String(format: "icon_1024.png composite: alpha %.3f at (8, 8) outside the body, %.3f at (512, 150) inside", outside, inside))
                if outside != 0 { failures.append("icon_1024: alpha at (8, 8) is \(outside), expected 0") }
                if inside != 1 { failures.append("icon_1024: alpha at (512, 150) is \(inside), expected 1") }
            }

            writePNG(composite, to: iconDir.appendingPathComponent("icon_\(px).png"))
        }

        // 3. SentientLogo.png (SPEC-00 7.2): regular glyph in #5856D6 on transparent, 636/1024 proportion.
        let logo = makeContext(logoSize)
        prepare(logo, px: logoSize)
        logo.addPath(BrandMark(variant: .regular).path(in: glyphRect).cgPath)
        logo.setFillColor(color(0x5856D6))
        logo.fillPath()
        let logoProbes = probePoints(variant: .regular)
        let logoScale = CGFloat(logoSize) / canvas
        let logoDot = alpha(logo, px: logoSize, at: logoProbes.dot, scale: logoScale)
        let logoRing = alpha(logo, px: logoSize, at: logoProbes.opposite, scale: logoScale)
        let logoGap = max(alpha(logo, px: logoSize, at: logoProbes.gapLeading, scale: logoScale),
                          alpha(logo, px: logoSize, at: logoProbes.gapTrailing, scale: logoScale))
        let logoCorner = alpha(logo, px: logoSize, pixelX: 8, pixelY: 8)
        print(String(format: "SentientLogo.png (512, regular, #5856D6): gap %.3f  dot %.3f  ring opposite gap %.3f  corner %.3f",
                     logoGap, logoDot, logoRing, logoCorner))
        if logoDot <= 0.5 || logoRing <= 0.5 { failures.append("SentientLogo: control failed (dot \(logoDot), ring \(logoRing))") }
        if logoGap >= 0.5 { failures.append("SentientLogo: gap alpha \(logoGap) is not below 0.5") }
        if logoCorner != 0 { failures.append("SentientLogo: corner alpha \(logoCorner) is not 0 (background must be transparent)") }
        writePNG(logo, to: logoDir.appendingPathComponent("SentientLogo.png"))

        // 4. Every filename the asset catalogs reference exists.
        failures += missingCatalogFiles(in: iconDir) + missingCatalogFiles(in: logoDir)

        if !failures.isEmpty {
            for line in failures { print("FAILED: \(line)") }
            fail("\(failures.count) acceptance check(s) failed")
        }
        print("OK: 7 icon sizes and SentientLogo.png written; every acceptance check passed")
        exit(0)
    }

    // MARK: Drawing

    static func makeContext(_ px: Int) -> CGContext {
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fail("could not create a \(px) px sRGB context")
        }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        return ctx
    }

    /// Scales the 1024-unit canvas to `px` and flips it once, so y grows downward like BrandMark's path.
    static func prepare(_ ctx: CGContext, px: Int) {
        let s = CGFloat(px) / canvas
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: 0, y: canvas)
        ctx.scaleBy(x: 1, y: -1)
    }

    static func drawIcon(in ctx: CGContext, px: Int, variant: BrandMark.Variant) {
        prepare(ctx, px: px)
        let s = CGFloat(px) / canvas
        let body = superellipse()

        // Body: shadow, then the gradient fill. Shadow offsets live in the context's base space
        // (y-up, device pixels), so "downward" is a negative y there, scaled by hand.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: color(0x000000, alpha: 0.30))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(body)
        ctx.clip()
        let fill = CGGradient(colorsSpace: sRGB,
                              colors: [color(0x7A78F0), color(0x5856D6), color(0x3634A3)] as CFArray,
                              locations: [0.0, 0.55, 1.0])!
        ctx.drawLinearGradient(fill, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        // Rim: a 3-unit stroke of the body, clipped to the body, white 28% at the top to 0% at y = 512.
        if px >= 64 {
            ctx.saveGState()
            ctx.addPath(body)
            ctx.clip()
            ctx.addPath(body)
            ctx.setLineWidth(3)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            let rim = CGGradient(colorsSpace: sRGB,
                                 colors: [color(0xFFFFFF, alpha: 0.28), color(0xFFFFFF, alpha: 0)] as CFArray,
                                 locations: [0, 1])!
            ctx.drawLinearGradient(rim, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 512), options: [])
            ctx.restoreGState()
        }

        // Glyph: the BrandMark path, white; a soft indigo shadow at 64 px and up.
        ctx.saveGState()
        if variant == .regular {
            ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 12 * s, color: color(0x1C1A6B, alpha: 0.35))
        }
        ctx.addPath(BrandMark(variant: variant).path(in: glyphRect).cgPath)
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// The glyph alone: same transform, white glyph on a transparent canvas, no body, no shadow.
    static func drawGlyphMask(in ctx: CGContext, px: Int, variant: BrandMark.Variant) {
        prepare(ctx, px: px)
        ctx.addPath(BrandMark(variant: variant).path(in: glyphRect).cgPath)
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
    }

    /// `|x−512|^5 + |y−512|^5 = 412^5`, sampled at 720 points and closed.
    static func superellipse() -> CGPath {
        let path = CGMutablePath()
        let e = 2 / bodyExponent
        for i in 0..<bodySamples {
            let t = Double(i) / Double(bodySamples) * 2 * .pi
            let c = cos(t), sn = sin(t)
            let x = center.x + bodyRadius * CGFloat(copysign(pow(abs(c), Double(e)), c))
            let y = center.y + bodyRadius * CGFloat(copysign(pow(abs(sn), Double(e)), sn))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Measurement

    struct Probes { let dot, gapLeading, gapTrailing, opposite: CGPoint }

    /// Probe points in canvas units, from BrandMark's own geometry for the 636-unit glyph square.
    static func probePoints(variant: BrandMark.Variant) -> Probes {
        let g = BrandMark.geometry(side: glyphSide, variant: variant)
        func on(_ degrees: Double) -> CGPoint {
            let r = degrees * .pi / 180
            return CGPoint(x: center.x + g.radius * CGFloat(cos(r)), y: center.y + g.radius * CGFloat(sin(r)))
        }
        let dot = on(g.gapCenterDegrees)
        func gapMidpoint(_ sign: Double) -> CGPoint {
            let cap = on(g.gapCenterDegrees + sign * g.gapDegrees / 2)
            let dx = cap.x - dot.x, dy = cap.y - dot.y
            let length = (dx * dx + dy * dy).squareRoot()
            let along = (g.dotDiameter / 2 + (length - g.stroke / 2)) / 2
            return CGPoint(x: dot.x + dx / length * along, y: dot.y + dy / length * along)
        }
        return Probes(dot: dot, gapLeading: gapMidpoint(-1), gapTrailing: gapMidpoint(1),
                      opposite: on(g.gapCenterDegrees + 180))
    }

    /// Alpha (0...1) of the pixel that contains canvas point `p` (y-down units).
    static func alpha(_ ctx: CGContext, px: Int, at p: CGPoint, scale: CGFloat) -> Double {
        alpha(ctx, px: px, pixelX: Int((p.x * scale).rounded(.down)), pixelY: Int((p.y * scale).rounded(.down)))
    }

    /// Alpha of pixel (x, y) counted from the top-left; bitmap memory row 0 is the top row.
    static func alpha(_ ctx: CGContext, px: Int, pixelX: Int, pixelY: Int) -> Double {
        let x = min(max(pixelX, 0), px - 1), y = min(max(pixelY, 0), px - 1)
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return Double(bytes[y * ctx.bytesPerRow + x * 4 + 3]) / 255
    }

    // MARK: Output

    static func writePNG(_ ctx: CGContext, to url: URL) {
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fail("could not encode \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fail("could not write \(url.path)") }
    }

    /// Filenames referenced by the catalog's Contents.json that do not exist, plus slots with no file.
    static func missingCatalogFiles(in dir: URL) -> [String] {
        let contents = dir.appendingPathComponent("Contents.json")
        guard let data = try? Data(contentsOf: contents),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [[String: Any]] else {
            return ["\(contents.path) is missing or unreadable"]
        }
        var problems: [String] = []
        for image in images {
            let slot = "\(image["size"] ?? "any") @\(image["scale"] ?? "1x")"
            guard let name = image["filename"] as? String else {
                problems.append("\(dir.lastPathComponent): slot \(slot) has no file")
                continue
            }
            if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
                problems.append("\(dir.lastPathComponent): \(name) (slot \(slot)) does not exist")
            }
        }
        print("\(dir.lastPathComponent)/Contents.json: \(images.count) slot(s), \(images.count - problems.count) with an existing file")
        return problems
    }

    // MARK: Helpers

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: sRGB, components: [CGFloat((hex >> 16) & 0xFF) / 255,
                                               CGFloat((hex >> 8) & 0xFF) / 255,
                                               CGFloat(hex & 0xFF) / 255, alpha])!
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("render-app-icon: \(message)\n".utf8))
        exit(1)
    }
}
