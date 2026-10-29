//
//  BrandMark.swift
//  Sentient OS macOS
//
//  The brand mark: a ring with a gap at the lower left, and a dot sitting in the gap (SPEC-00 3.6).
//  Imports SwiftUI only and names no app type: Tools/render-app-icon.swift compiles this file with
//  swiftc outside the app and runs `BrandMark.selfCheckFailures()` before it draws. The #Preview
//  sits inside `#if DEBUG`, so a standalone compile without `-D DEBUG` needs no macro plugin.
//

import SwiftUI

nonisolated struct BrandMark: Shape {
    nonisolated enum Variant: Sendable {
        /// 20 pt and up; app icon 64 px and up.
        case regular
        /// Under 20 pt; app icon 16 and 32 px.
        case compact
    }

    nonisolated struct Geometry: Sendable, Equatable {
        let radius: CGFloat          // ring centerline radius
        let stroke: CGFloat          // ring stroke width, round caps
        let dotDiameter: CGFloat
        let gapDegrees: Double       // angular width of the gap
        let gapCenterDegrees: Double // 135: lower-left in SwiftUI's y-down space
    }

    /// nil = `.compact` when the side is under 20 pt, else `.regular`.
    var variant: Variant?

    init(variant: Variant? = nil) {
        self.variant = variant
    }

    /// The mark's proportions for a square of side `side`.
    static func geometry(side: CGFloat, variant: Variant) -> Geometry {
        switch variant {
        case .regular:
            return Geometry(radius: 0.33 * side, stroke: 0.12 * side, dotDiameter: 0.17 * side,
                            gapDegrees: 76, gapCenterDegrees: 135)
        case .compact:
            return Geometry(radius: 0.31 * side, stroke: 0.15 * side, dotDiameter: 0.18 * side,
                            gapDegrees: 116, gapCenterDegrees: 135)
        }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard side > 0 else { return Path() }
        let g = Self.geometry(side: side, variant: variant ?? (side < 20 ? .compact : .regular))
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // The arc as a 97-point polyline: `addArc`'s clockwise flag is inverted in y-down space.
        var arc = Path()
        for i in 0...96 {
            let degrees = g.gapCenterDegrees + g.gapDegrees / 2 + (360 - g.gapDegrees) * Double(i) / 96
            let point = Self.point(at: degrees, radius: g.radius, around: center)
            if i == 0 { arc.move(to: point) } else { arc.addLine(to: point) }
        }
        var path = arc.strokedPath(StrokeStyle(lineWidth: g.stroke, lineCap: .round, lineJoin: .round))

        let dot = Self.point(at: g.gapCenterDegrees, radius: g.radius, around: center)
        path.addEllipse(in: CGRect(x: dot.x - g.dotDiameter / 2, y: dot.y - g.dotDiameter / 2,
                                   width: g.dotDiameter, height: g.dotDiameter))
        return path
    }

    /// A 16–18 pt menu bar template image (isTemplate = true, accessibilityDescription "Sentient").
    @MainActor static func templateImage(pointSize: CGFloat) -> NSImage {
        let inset = pointSize * 0.06
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { @Sendable rect in
            // Template mask: only alpha counts, so black is the conventional ink (SPEC-00 3.0).
            NSColor.black.setFill()
            NSBezierPath(cgPath: BrandMark().path(in: rect.insetBy(dx: inset, dy: inset)).cgPath).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sentient"
        return image
    }

    /// The SPEC-00 3.6 path self-checks for both variants at side 100 and side 16. Returns one line
    /// per failed check; empty means the geometry is sound. Tools/render-app-icon.swift exits
    /// non-zero when this is not empty.
    static func selfCheckFailures() -> [String] {
        var failures: [String] = []
        for variant in [Variant.regular, .compact] {
            for side in [CGFloat(100), CGFloat(16)] {
                let name = "\(variant) at side \(Int(side))"
                let rect = CGRect(x: 0, y: 0, width: side, height: side)
                let path = BrandMark(variant: variant).path(in: rect)
                let g = geometry(side: side, variant: variant)
                let center = CGPoint(x: rect.midX, y: rect.midY)

                // 1. The path lies inside the rect.
                let bounds = path.boundingRect
                if bounds.isEmpty || !rect.contains(bounds) {
                    failures.append("\(name): bounding rect \(bounds) is not inside \(rect)")
                }

                // 2. The dot is filled.
                let dot = point(at: g.gapCenterDegrees, radius: g.radius, around: center)
                if !path.contains(dot) {
                    failures.append("\(name): the dot center is not filled")
                }

                // 3. Clear space between the dot and each cap: the point midway between the dot's
                //    edge and the cap's edge, on the segment joining their centers, is empty.
                for sign in [-1.0, 1.0] {
                    let cap = point(at: g.gapCenterDegrees + sign * g.gapDegrees / 2, radius: g.radius, around: center)
                    let dx = cap.x - dot.x, dy = cap.y - dot.y
                    let length = (dx * dx + dy * dy).squareRoot()
                    let dotEdge = g.dotDiameter / 2
                    let capEdge = length - g.stroke / 2
                    if capEdge <= dotEdge {
                        failures.append("\(name): the dot touches the \(sign < 0 ? "leading" : "trailing") cap")
                        continue
                    }
                    let along = (dotEdge + capEdge) / 2
                    let probe = CGPoint(x: dot.x + dx / length * along, y: dot.y + dy / length * along)
                    if path.contains(probe) {
                        failures.append("\(name): the gap beside the dot (\(sign < 0 ? "leading" : "trailing")) is filled")
                    }
                }

                // 4. Positive control: the ring opposite the gap is filled (a 76° sliver drawn
                //    instead of a 284° ring fails here).
                let opposite = point(at: g.gapCenterDegrees + 180, radius: g.radius, around: center)
                if !path.contains(opposite) {
                    failures.append("\(name): the ring opposite the gap is not filled")
                }
            }
        }
        return failures
    }

    private static func point(at degrees: Double, radius: CGFloat, around center: CGPoint) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(radians)), y: center.y + radius * CGFloat(sin(radians)))
    }
}

/// The brand mark filled with the accent (or `tint`). Decorative: a caller that needs it read
/// aloud adds `.accessibilityLabel("Sentient")` itself.
struct BrandMarkView: View {
    private let size: CGFloat
    private let tint: Color?
    private let variant: BrandMark.Variant?

    init(size: CGFloat, tint: Color? = nil, variant: BrandMark.Variant? = nil) {
        self.size = size
        self.tint = tint
        self.variant = variant
    }

    var body: some View {
        BrandMark(variant: variant)
            .fill(tint ?? .accentColor)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Brand mark") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            HStack(alignment: .center, spacing: 16) {
                BrandMarkView(size: 16)
                BrandMarkView(size: 20)
                BrandMarkView(size: 40)
                BrandMarkView(size: 64, tint: .primary)
                Image(nsImage: BrandMark.templateImage(pointSize: 18))
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 520)
}
#endif
