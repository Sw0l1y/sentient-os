//
//  SkyRenderer.swift
//  Sentient OS macOS
//
//  The Knowledge graph's layout engine. It owns the shared visual facts that more than one view
//  needs (the domain palette, node sizes) and the collision-aware placement of note titles. It
//  draws nothing: NightSkyView's painter draws the node-and-edge map from these answers.
//  Stateless: reads NightSkyModel.
//

import SwiftUI
import AppKit

struct SkyRenderer {

    /// One system colour per domain (top-level folder), biggest domain first. They adapt to light
    /// and dark automatically. The Overview root (`d < 0`) uses the label colour; domains past the
    /// sixth share gray.
    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]

    static func domainColor(_ d: Int, alpha: Double = 1) -> Color {
        let base: Color
        if d < 0 { base = Color(nsColor: .labelColor) }
        else if d < palette.count { base = palette[d] }
        else { base = .gray }
        return base.opacity(alpha)
    }

    // MARK: Nodes

    /// A node's radius on screen: 2–7 pt at zoom 1 by `sqrt(degree / maxDegree)` (a 4–14 pt
    /// diameter); the root is 7 pt. `zf` scales sizes sub-linearly with the camera zoom.
    static func starRadius(_ n: SkyNode, maxDegree: Int, zf: CGFloat) -> CGFloat {
        let degN = sqrt(Double(n.degree) / Double(max(maxDegree, 1)))
        let world: CGFloat = n.isRoot ? 7 : (2 + 5 * CGFloat(degN))
        return world * zf
    }

    /// The zoom factor node sizes follow (sub-linear, so zooming in spreads nodes apart faster
    /// than it inflates them).
    static func sizeFactor(_ model: NightSkyModel) -> CGFloat {
        CGFloat(pow(Double(model.camera.zoom), 0.62))
    }

    // MARK: Decorative dust (retired)

    /// Kept for NightSkyModel's `dust` property, whose initializer calls `makeDust()`.
    /// The graph draws no background particles, so the list is always empty.
    struct Speck {
        let base: CGPoint
        let size: CGFloat
        let alpha: Double
        let parallax: CGFloat
        let drift: CGPoint
        let phase: Double
    }

    static func makeDust() -> [Speck] { [] }

    // MARK: Title placement

    /// Where note titles go this frame. Titles appear only when zoomed in past 1.0, or while a
    /// node is hovered or highlighted. Each node has its own zoom threshold (`2.0 - 0.55 * degN`,
    /// the root 1.2); the hovered neighbourhood is always a candidate. Candidates are placed
    /// greedily by priority (hovered > highlighted > busiest), and a title whose measured rect
    /// would overlap an already placed one, or the hover card, is not placed. `measure` returns
    /// the size of node i's resolved title (a static func cannot resolve Text itself).
    static func titlePlacements(model: NightSkyModel, size: CGSize,
                                measure: (Int) -> CGSize) -> [(index: Int, anchor: CGPoint, opacity: Double)] {
        guard let graph = model.graph, let sim = model.sim else { return [] }
        let zoom = Double(model.camera.zoom)
        guard zoom > 1.0 || model.focusIndex != nil || model.highlightIndex != nil else { return [] }
        let zf = sizeFactor(model)
        let margin: CGFloat = 40
        let focusSet: Set<Int> = {
            guard let f = model.focusIndex else { return [] }
            return model.focusNeighbors.union([f])
        }()

        struct Candidate {
            let i: Int
            let anchor: CGPoint
            let alpha: Double
            let priority: Double     // static per hover session, so placement never flickers
        }
        var candidates: [Candidate] = []
        for (i, n) in graph.nodes.enumerated() {
            let degN = sqrt(Double(n.degree) / Double(max(graph.maxDegree, 1)))
            let threshold = n.isRoot ? 1.2 : 2.0 - 0.55 * degN
            let g = model.glow.indices.contains(i) ? model.glow[i] : 0
            var a = max(0, min(1, (zoom - threshold) / 0.4))
            if i == model.focusIndex || i == model.highlightIndex || focusSet.contains(i) {
                a = max(a, g * 0.92)                       // the hovered neighbourhood gets named too
            }
            if !focusSet.isEmpty && !focusSet.contains(i) { a *= 1 - 0.62 * model.focusBlend }
            guard a > 0.03 else { continue }
            let p = model.toScreen(sim.pos[i], size: size)
            guard p.x > -margin, p.x < size.width + margin, p.y > -margin, p.y < size.height + margin
            else { continue }
            let r = starRadius(n, maxDegree: graph.maxDegree, zf: zf)
            let priority: Double = i == model.focusIndex ? 3 : (i == model.highlightIndex ? 2 : degN)
            candidates.append(Candidate(i: i, anchor: CGPoint(x: p.x, y: p.y + r + 12),
                                        alpha: a, priority: priority))
        }

        candidates.sort { $0.priority != $1.priority ? $0.priority > $1.priority : $0.i < $1.i }
        var placed: [CGRect] = []
        var out: [(index: Int, anchor: CGPoint, opacity: Double)] = []
        if let card = model.hoverCardRect(in: size) { placed.append(card) }
        for c in candidates {
            let sz = measure(c.i)
            let rect = CGRect(x: c.anchor.x - sz.width / 2, y: c.anchor.y - sz.height / 2,
                              width: sz.width, height: sz.height).insetBy(dx: -6, dy: -3)
            guard !placed.contains(where: { $0.intersects(rect) }) else { continue }
            placed.append(rect)
            out.append((index: c.i, anchor: c.anchor, opacity: c.alpha))
        }
        return out
    }
}
