//
//  NightSkyView.swift
//  Sentient OS macOS
//
//  The Knowledge graph: every note as a node, every wikilink as an edge, laid out once by the
//  existing simulation and then still. A plain node-and-edge map on the document background
//  (Freeform, the Xcode dependency graph), with Maps-style floating zoom controls.
//  An AppKit event catcher gives pan (two-finger scroll), zoom (pinch, mouse wheel, ⌘-scroll),
//  node dragging, hover (a callout card), click (→ open the note in the reader) and Esc
//  (→ back to the reader).
//
//  Data: SkyGraph · layout physics: SkySimulation · interaction: NightSkyModel ·
//  title placement and palette: SkyRenderer · drawing: KnowledgeGraphPainter (below).
//  Doc: Views/Knowledge/Documentation - Knowledge Window (Constellation & Reader).md
//

import SwiftUI
import AppKit

struct NightSkyView: View {
    let vault: KnowledgeVault?
    var vaultLoaded = true       // false only while KnowledgeView's vault scan is still in flight
    @ObservedObject var model: NightSkyModel
    var entranceReady = true
    var isActive = true
    var animationsEnabled = true
    var showsHUD = true
    var takesKeyboardFocus = true
    var onOpen: (URL) -> Void
    var onExit: () -> Void
    private struct LoadKey: Equatable {
        let root: URL?
        let ready: Bool
        let active: Bool
    }

    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var reduce: Bool { motionOverride ?? systemReduced }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                if let graph = model.graph, !graph.nodes.isEmpty {
                    Canvas { ctx, size in
                        // The model's static path: the layout settles in one tick and then
                        // stays put; pan, zoom, drag, hover and highlight redraw on demand.
                        if isActive && entranceReady { model.tick(now: 0, size: size) }
                        KnowledgeGraphPainter.draw(ctx, size: size, model: model, graph: graph)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Knowledge Graph")

                    if isActive && entranceReady {
                        SkyEventCatcher(model: model, takesKeyboardFocus: takesKeyboardFocus, onOpen: onOpen, onExit: onExit)
                    }
                    if let info = model.hoverInfo, let card = model.hoverCardRect(in: geo.size) {
                        SkyHoverCard(info: info,
                                     linkCount: graph.nodes.firstIndex { $0.url == info.url }
                                        .map { graph.adjacency[$0].count } ?? 0,
                                     width: card.width)
                            .position(x: card.midX, y: card.midY)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                    if showsHUD {
                        GraphZoomControls(model: model, size: geo.size)
                            .padding(Space.l)
                    }
                } else if entranceReady && (model.graph != nil || (vaultLoaded && vault == nil)) {
                    emptyState
                } else {
                    Color.clear      // vault scan or graph build in flight: show nothing new
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(Motion.gated(Motion.quick, reduceMotion: reduce), value: model.hoverInfo)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .graphBackgroundExtension(showsHUD)
        // The graph never animates on its own: the model's static path settles the layout once.
        .onChange(of: animationsEnabled, initial: true) { _, _ in model.animates = false }
        // Reruns on every Graph entry (silent refresh) AND when the vault first arrives, because
        // this view can mount before the async vault scan finishes.
        .task(id: LoadKey(root: vault?.root, ready: entranceReady, active: isActive)) {
            guard entranceReady, isActive else { return }
            await model.load(vault: vault)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView("No Knowledge Base Yet", systemImage: "books.vertical",
                               description: Text("Once Sentient has analyzed your sources, every note appears here."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    /// The live Knowledge page lets the canvas extend under the sidebar and toolbar on macOS 26
    /// (`extendsBackground()`); the embedded Home showcase (no HUD) sits in a clipped card and
    /// does not.
    @ViewBuilder
    func graphBackgroundExtension(_ enabled: Bool) -> some View {
        if enabled { self.extendsBackground() } else { self }
    }
}

// MARK: - The painter

/// Draws the map in painter's order: edges, domain label plates, title halos, nodes and their
/// rings, title text. Text always sits on a backing in the document background colour, so edges
/// never cut through it; labels are placed clear of the nodes (SkyRenderer), and a title's halo
/// sits under the nodes so it never hides one.
private enum KnowledgeGraphPainter {
    /// The page background (NightSkyView's own), used for text backings in both appearances.
    private static var backing: Color { Color(nsColor: .textBackgroundColor) }

    private struct PlacedTitle {
        let text: GraphicsContext.ResolvedText
        let anchor: CGPoint
        let size: CGSize
        let opacity: Double
    }

    static func draw(_ ctx: GraphicsContext, size: CGSize, model: NightSkyModel, graph: SkyGraph) {
        guard let sim = model.sim, sim.pos.count == graph.nodes.count else { return }
        let zf = SkyRenderer.sizeFactor(model)
        let focusSet: Set<Int> = {
            guard let f = model.focusIndex else { return [] }
            return model.focusNeighbors.union([f])
        }()
        let accentIndices: Set<Int> = Set([model.hoverIndex, model.highlightIndex].compactMap { $0 })
        let positions = graph.nodes.indices.map { model.toScreen(sim.pos[$0], size: size) }

        drawEdges(ctx, graph: graph, positions: positions, accentIndices: accentIndices)
        let labelPlates = drawDomainLabels(ctx, size: size, model: model, graph: graph, positions: positions)
        let titles = layoutTitles(ctx, size: size, model: model, graph: graph, avoiding: labelPlates)
        drawTitleHalos(ctx, titles)
        drawNodes(ctx, size: size, model: model, graph: graph, positions: positions, zf: zf, focusSet: focusSet)
        drawTitleText(ctx, titles)
    }

    /// Hairline edges in the separator colour; edges touching the hovered or highlighted note
    /// switch to the accent at 1 pt.
    private static func drawEdges(_ ctx: GraphicsContext, graph: SkyGraph, positions: [CGPoint],
                                  accentIndices: Set<Int>) {
        var resting = Path()
        var lit = Path()
        for e in graph.edges {
            let a = positions[e.a], b = positions[e.b]
            if accentIndices.contains(e.a) || accentIndices.contains(e.b) {
                lit.move(to: a); lit.addLine(to: b)
            } else {
                resting.move(to: a); resting.addLine(to: b)
            }
        }
        ctx.stroke(resting, with: .color(Color(nsColor: .separatorColor)), lineWidth: 0.5)
        ctx.stroke(lit, with: .color(Color.accentColor), lineWidth: 1)
    }

    /// Each domain's name with a dot in the domain colour, on a thin capsule plate in the page
    /// background (hairline separator border) so edges pass under it. SkyRenderer places the plate
    /// clear of the nodes (under the domain's hub when there is room). Labels fade as you zoom in
    /// (titles take over) and while a note is hovered. Returns the plates still clearly showing,
    /// for the titles to avoid.
    private static func drawDomainLabels(_ ctx: GraphicsContext, size: CGSize, model: NightSkyModel,
                                         graph: SkyGraph, positions: [CGPoint]) -> [CGRect] {
        let zoom = Double(model.camera.zoom)
        let opacity = max(0, min(1, (1.9 - zoom) / 0.9)) * (1 - 0.5 * model.focusBlend)
        guard opacity > 0.02, !graph.domains.isEmpty else { return [] }
        var layer = ctx
        layer.opacity = opacity
        let dot: CGFloat = 6, gap: CGFloat = 5, padX: CGFloat = 8, padY: CGFloat = 3
        var texts: [Int: (text: GraphicsContext.ResolvedText, size: CGSize)] = [:]
        func text(_ d: Int) -> (text: GraphicsContext.ResolvedText, size: CGSize) {
            if let t = texts[d] { return t }
            let resolved = layer.resolve(Text(graph.domains[d]).font(.caption.weight(.semibold))
                .foregroundStyle(.secondary))
            let t = (text: resolved, size: resolved.measure(in: CGSize(width: 320, height: 40)))
            texts[d] = t
            return t
        }
        let slots = SkyRenderer.domainLabelPlacements(model: model, graph: graph, positions: positions,
                                                      size: size) { d in
            let sz = text(d).size
            return CGSize(width: ceil(padX + dot + gap + sz.width + padX),
                          height: ceil(max(sz.height, dot) + padY * 2))
        }
        for slot in slots {
            let plate = slot.plate
            let shape = Path(roundedRect: plate, cornerRadius: plate.height / 2, style: .continuous)
            layer.fill(shape, with: .color(backing.opacity(0.92)))
            layer.stroke(shape, with: .color(Color(nsColor: .separatorColor)), lineWidth: 0.5)
            let left = plate.minX + padX
            layer.fill(Path(ellipseIn: CGRect(x: left, y: plate.midY - dot / 2, width: dot, height: dot)),
                       with: .color(SkyRenderer.domainColor(slot.domain)))
            layer.draw(text(slot.domain).text, at: CGPoint(x: left + dot + gap, y: plate.midY), anchor: .leading)
        }
        return opacity > 0.35 ? slots.map(\.plate) : []
    }

    /// Filled circles in the domain colour, sized by degree. Notes outside the hovered
    /// neighbourhood dim; "Changed last night" notes wear a 1.5 pt accent ring, and the note you
    /// came back from wears a 2 pt one.
    private static func drawNodes(_ ctx: GraphicsContext, size: CGSize, model: NightSkyModel, graph: SkyGraph,
                                  positions: [CGPoint], zf: CGFloat, focusSet: Set<Int>) {
        let margin: CGFloat = 40
        let dimmed = 1 - 0.7 * model.focusBlend
        for (i, n) in graph.nodes.enumerated() {
            let p = positions[i]
            guard p.x > -margin, p.x < size.width + margin, p.y > -margin, p.y < size.height + margin
            else { continue }
            let r = SkyRenderer.starRadius(n, maxDegree: graph.maxDegree, zf: zf)
            let opacity = (focusSet.isEmpty || focusSet.contains(i)) ? 1 : dimmed
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .color(SkyRenderer.domainColor(n.domain, alpha: opacity)))

            let ringR = r + 3
            let ring = Path(ellipseIn: CGRect(x: p.x - ringR, y: p.y - ringR, width: ringR * 2, height: ringR * 2))
            if i == model.highlightIndex {
                ctx.stroke(ring, with: .color(Color.accentColor), lineWidth: 2)
            } else if n.recentlyChanged {
                ctx.stroke(ring, with: .color(Color.accentColor.opacity(opacity)), lineWidth: 1.5)
            }
        }
    }

    /// Note titles where SkyRenderer's collision-aware placement allows them (clear of each other,
    /// the hover card and the domain label plates).
    private static func layoutTitles(_ ctx: GraphicsContext, size: CGSize, model: NightSkyModel, graph: SkyGraph,
                                     avoiding labelPlates: [CGRect]) -> [PlacedTitle] {
        var resolved: [Int: GraphicsContext.ResolvedText] = [:]
        func text(_ i: Int) -> GraphicsContext.ResolvedText {
            if let t = resolved[i] { return t }
            let strong = i == model.hoverIndex || i == model.highlightIndex
            let t = ctx.resolve(Text(graph.nodes[i].title).font(.caption)
                .foregroundStyle(strong ? Color.primary : Color.secondary))
            resolved[i] = t
            return t
        }
        let measureBox = CGSize(width: 360, height: 60)
        let placements = SkyRenderer.titlePlacements(model: model, size: size, avoiding: labelPlates) { i in
            text(i).measure(in: measureBox)
        }
        return placements.map { p in
            let t = text(p.index)
            return PlacedTitle(text: t, anchor: p.anchor, size: t.measure(in: measureBox), opacity: p.opacity)
        }
    }

    /// A soft plate in the page background behind each title (a halo: invisible on the empty page,
    /// it only shows where it masks an edge). Drawn before the nodes, so it never covers one.
    private static func drawTitleHalos(_ ctx: GraphicsContext, _ titles: [PlacedTitle]) {
        for title in titles {
            let rect = CGRect(x: title.anchor.x - title.size.width / 2, y: title.anchor.y - title.size.height / 2,
                              width: title.size.width, height: title.size.height).insetBy(dx: -4, dy: -1.5)
            var layer = ctx
            layer.opacity = title.opacity
            layer.fill(Path(roundedRect: rect, cornerRadius: 4, style: .continuous),
                       with: .color(backing.opacity(0.85)))
        }
    }

    private static func drawTitleText(_ ctx: GraphicsContext, _ titles: [PlacedTitle]) {
        for title in titles {
            var layer = ctx
            layer.opacity = title.opacity
            layer.draw(title.text, at: title.anchor, anchor: .center)
        }
    }
}

// MARK: - The hover card

/// A popover-style callout for the hovered note: title, first line, folder, link count. It is
/// not interactive (it sits above the event catcher); clicking the node opens the note.
private struct SkyHoverCard: View {
    let info: SkyHoverInfo
    let linkCount: Int
    var width: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                if info.recentlyChanged {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        .help("Changed last night")
                        .accessibilityLabel("Changed last night")
                }
                Text(info.title).font(.headline).lineLimit(1)
            }
            if !info.preview.isEmpty {
                Text(info.preview).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Label(info.domainName == "You" ? "Overview" : info.domainName, systemImage: "folder")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(linkCount == 1 ? "1 link" : "\(linkCount) links").monospacedDigit()
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("Click to Open").font(.caption).foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .padding(Space.m)
        .frame(width: width, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Zoom controls

/// The Maps-style floating zoom group: Zoom Out, Zoom to Fit, Zoom In (⌘−, ⌘0, ⌘=).
private struct GraphZoomControls: View {
    let model: NightSkyModel
    let size: CGSize

    private var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    var body: some View {
        ControlGroup {
            Button { model.zoom(by: 1 / 1.25, at: center, size: size) } label: {
                Label("Zoom Out", systemImage: "minus")
            }
            .help("Zoom Out")
            .keyboardShortcut("-", modifiers: .command)
            Button { model.fitToContent(in: size) } label: {
                Label("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("Zoom to Fit")
            .keyboardShortcut("0", modifiers: .command)
            Button { model.zoom(by: 1.25, at: center, size: size) } label: {
                Label("Zoom In", systemImage: "plus")
            }
            .help("Zoom In")
            .keyboardShortcut("=", modifiers: .command)
        }
        .labelStyle(.iconOnly)
        .controlSize(.regular)
        .fixedSize()
        .padding(Space.xs)
        .floatingGlass(in: Capsule())
    }
}

// MARK: - Event catcher (real AppKit events: scroll, pinch, drag, hover, click, Esc)

private struct SkyEventCatcher: NSViewRepresentable {
    let model: NightSkyModel
    let takesKeyboardFocus: Bool
    let onOpen: (URL) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> SkyEventNSView {
        let view = SkyEventNSView()
        view.takesKeyboardFocus = takesKeyboardFocus
        return view
    }

    func updateNSView(_ v: SkyEventNSView, context: Context) {
        v.model = model
        v.takesKeyboardFocus = takesKeyboardFocus
        v.onOpen = onOpen
        v.onExit = onExit
    }

    static func dismantleNSView(_ view: SkyEventNSView, coordinator: ()) {
        view.model?.endDrag(); view.model?.clearHover()
        view.model = nil; view.onOpen = nil; view.onExit = nil
        if view.window?.firstResponder === view { view.window?.makeFirstResponder(nil) }
    }
}

private final class SkyEventNSView: NSView {
    weak var model: NightSkyModel?
    var takesKeyboardFocus = true
    var onOpen: ((URL) -> Void)?
    var onExit: (() -> Void)?

    private enum DragMode { case none, star(Int), pan }
    private var dragMode: DragMode = .none
    private var downPoint: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var moved = false

    override var acceptsFirstResponder: Bool { takesKeyboardFocus }
    override var isFlipped: Bool { true }           // match SwiftUI/Canvas coordinates

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.takesKeyboardFocus, self.model != nil, let w = self.window else { return }
            w.makeFirstResponder(self)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited,
                                                 .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    // MARK: Hover

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        model?.updateHover(p, size: bounds.size)
        (model?.hoverIndex != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func mouseExited(with event: NSEvent) {
        model?.clearHover()
        NSCursor.arrow.set()
    }

    // MARK: Click / drag (a still click opens the note; a drag moves a node or pans the map)

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        downPoint = p
        lastDragPoint = p
        moved = false
        if let i = model?.hitTest(p, size: bounds.size) {
            dragMode = .star(i)
            model?.beginDrag(i)
        } else {
            dragMode = .pan
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if (p - downPoint).length > 3 { moved = true }
        switch dragMode {
        case .star:
            model?.dragStar(to: p, size: bounds.size)
        case .pan:
            model?.panBy(dx: p.x - lastDragPoint.x, dy: p.y - lastDragPoint.y)
        case .none:
            break
        }
        lastDragPoint = p
    }

    override func mouseUp(with event: NSEvent) {
        if case .star(let i) = dragMode {
            model?.endDrag()
            if !moved, let url = model?.nodeURL(i) { onOpen?(url) }
        }
        dragMode = .none
    }

    // MARK: Scroll + pinch (trackpad pans, wheel/⌘-scroll/pinch zoom — Figma manners)

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            model?.panBy(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        } else {
            let scale = event.hasPreciseScrollingDeltas ? 0.01 : 0.05
            model?.zoom(by: exp(event.scrollingDeltaY * scale), at: p, size: bounds.size)
        }
    }

    override func magnify(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        model?.zoom(by: 1 + event.magnification, at: p, size: bounds.size)
    }

    // MARK: Keys (Esc returns to the reader; everything else is quietly ignored — no beeps)

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?() }
    }
}

// MARK: - Previews (the mock graph is seeded, so renders are stable)

#Preview("Knowledge Graph") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            NightSkyView(vault: nil, model: .preview(), onOpen: { _ in }, onExit: {})
                .frame(width: 640, height: 480)
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Knowledge Graph — hover") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            NightSkyView(vault: nil, model: .preview(hovering: 22), onOpen: { _ in }, onExit: {})
                .frame(width: 640, height: 480)
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Knowledge Graph — hover card") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            SkyHoverCard(info: SkyHoverInfo(url: URL(fileURLWithPath: "/mock/a.md"),
                                            title: "Sentient OS – Launch Timeline",
                                            domainName: "Sentient OS",
                                            preview: "Beta invite waves, the Reddit playbook, and what has to be true before strangers see it.",
                                            recentlyChanged: true,
                                            anchor: .zero),
                         linkCount: 4)
                .padding(24)
                .background(Color(nsColor: .textBackgroundColor))
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Knowledge Graph — empty") {
    NightSkyView(vault: nil, model: NightSkyModel(), onOpen: { _ in }, onExit: {})
        .frame(width: 640, height: 480)
}
