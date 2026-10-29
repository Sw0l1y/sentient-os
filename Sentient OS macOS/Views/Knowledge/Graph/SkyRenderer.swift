//
//  SkyRenderer.swift
//  Sentient OS macOS
//
//  The Knowledge graph's layout engine. It owns the shared visual facts that more than one view
//  needs (the domain palette, node sizes) and the collision-aware placement of domain labels and
//  note titles. It
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

    // MARK: Domain label placement

    /// Where each domain's name plate goes this frame, measured against the nodes so a label never
    /// sits on one. Each domain tries, in order: under its hub (its busiest note), over the hub,
    /// under / over / beside the domain's bounding box, beside the hub, then the centroid. The first
    /// slot whose rect clears every node circle (grown by 3 pt) and every plate already placed wins;
    /// when none is clear, the slot with the fewest collisions does (nodes count more than plates,
    /// leaving the screen counts least). Domains are placed biggest first. `positions` are the
    /// nodes' screen points; `measure(d)` returns domain d's whole plate size (dot, name, padding).
    static func domainLabelPlacements(model: NightSkyModel, graph: SkyGraph, positions: [CGPoint],
                                      size: CGSize, measure: (Int) -> CGSize) -> [(domain: Int, plate: CGRect)] {
        guard positions.count == graph.nodes.count, !graph.domains.isEmpty else { return [] }
        let zf = sizeFactor(model)
        let radii = graph.nodes.map { starRadius($0, maxDegree: graph.maxDegree, zf: zf) }
        let bounds = CGRect(origin: .zero, size: size)
        let nearby = bounds.insetBy(dx: -60, dy: -60)
        let obstacles = graph.nodes.indices.filter { nearby.contains(positions[$0]) }
        let clearance: CGFloat = 3, gap: CGFloat = 6

        var members = [[Int]](repeating: [], count: graph.domains.count)
        for (i, n) in graph.nodes.enumerated() where n.domain >= 0 && n.domain < graph.domains.count {
            members[n.domain].append(i)
        }

        var placed: [CGRect] = []
        var out: [(domain: Int, plate: CGRect)] = []
        for (d, idx) in members.enumerated() where !idx.isEmpty {
            let plate = measure(d)
            let w = plate.width, h = plate.height
            // The hub: highest degree, lowest index on a tie (stable frame to frame).
            let hub = idx.max { a, b in
                graph.nodes[a].degree != graph.nodes[b].degree
                    ? graph.nodes[a].degree < graph.nodes[b].degree : a > b
            }!
            let hp = positions[hub], hr = radii[hub]
            var box = CGRect.null
            var sum = CGPoint.zero
            for i in idx {
                let p = positions[i], r = radii[i]
                box = box.union(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                sum += p
            }
            let c = sum * (1 / CGFloat(idx.count))
            let centers: [CGPoint] = [
                CGPoint(x: hp.x, y: hp.y + hr + gap + h / 2),          // under the hub
                CGPoint(x: hp.x, y: hp.y - hr - gap - h / 2),          // over the hub
                CGPoint(x: c.x, y: box.maxY + gap + h / 2),            // under the domain
                CGPoint(x: c.x, y: box.minY - gap - h / 2),            // over the domain
                CGPoint(x: box.maxX + gap + w / 2, y: c.y),            // right of the domain
                CGPoint(x: box.minX - gap - w / 2, y: c.y),            // left of the domain
                CGPoint(x: hp.x + hr + gap + w / 2, y: hp.y),          // right of the hub
                CGPoint(x: hp.x - hr - gap - w / 2, y: hp.y),          // left of the hub
                c,
            ]
            var best: (rect: CGRect, score: Int)?
            for p in centers {
                let rect = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
                var score = 0
                for i in obstacles where circle(positions[i], radius: radii[i] + clearance, hits: rect) {
                    score += 4
                }
                for other in placed where other.intersects(rect) { score += 3 }
                if !bounds.contains(rect) { score += 1 }
                if best == nil || score < best!.score { best = (rect, score) }
                if score == 0 { break }
            }
            guard let best else { continue }
            placed.append(best.rect)
            out.append((domain: d, plate: best.rect))
        }
        return out
    }

    /// Whether a circle overlaps a rect (closest-point test).
    private static func circle(_ center: CGPoint, radius: CGFloat, hits rect: CGRect) -> Bool {
        let dx = center.x - max(rect.minX, min(center.x, rect.maxX))
        let dy = center.y - max(rect.minY, min(center.y, rect.maxY))
        return dx * dx + dy * dy < radius * radius
    }

    // MARK: Title placement

    /// Where note titles go this frame. Titles appear only when zoomed in past 1.0, or while a
    /// node is hovered or highlighted. Each node has its own zoom threshold (`2.0 - 0.55 * degN`,
    /// the root 1.2); the hovered neighbourhood is always a candidate. Candidates are placed
    /// greedily by priority (hovered > highlighted > busiest), and a title whose measured rect
    /// would overlap an already placed one, or the hover card, is not placed. `reserved` rects
    /// (the domain label plates still showing) also turn titles away, except the hovered and
    /// highlighted note's, which draw over them. `measure` returns the size of node i's resolved
    /// title (a static func cannot resolve Text itself).
    static func titlePlacements(model: NightSkyModel, size: CGSize, avoiding reserved: [CGRect] = [],
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
            if c.priority < 2, reserved.contains(where: { $0.intersects(rect) }) { continue }
            placed.append(rect)
            out.append((index: c.i, anchor: c.anchor, opacity: c.alpha))
        }
        return out
    }
}
