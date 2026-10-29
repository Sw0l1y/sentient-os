//
//  CaretSwirl.swift
//  Sentient OS macOS
//
//  Double Tap's light: a focus ring at the user's text cursor. The instant the second tap lands,
//  one thin accent ring appears about 2.2× wider than the caret and closes in on it, with a single
//  highlight travelling around it while the reply is drafted (the gather). When the reply arrives
//  the ring completes as the text lands, and a small brand mark fades in and out just above the
//  caret (the landing); when there is nothing to paste the ring widens slightly and fades (the
//  dissolve). With Reduce Motion the ring sits at the caret and only fades.
//
//  It lives in its own click-through, non-activating panel above everything, and it never takes
//  key (the ⌘V must land in the user's own box). It stays visible to screen capture on purpose,
//  so recordings and demos carry the light; the tap's own screenshot carries the ring too, since
//  the ring is up before the shot fires. Everything drawn is a pure function of time in ONE
//  Canvas, with no per-frame state. The phase changes are continuous: a landing or a dissolve
//  starts from the exact radius and angle the ring had at that moment.
//
//  Key methods: begin(at:) · land() · dissolve() · landingDelay.
//  Doc: Documentation - Double Tap.md (this folder).
//

import SwiftUI
import AppKit

@MainActor
final class CaretSwirl {
    /// How long after `land()` the paste should fire, so the text appears as the ring completes.
    static let landingDelay: Duration = .milliseconds(170)

    private let model = SwirlModel()
    private var panel: NSPanel?
    private var closeTask: Task<Void, Never>?

    /// Re-asserted on every reveal: macOS drops `.canJoinAllSpaces` when a window is re-ordered.
    private static let collectionBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

    /// Show the ring, wide, centred on the caret, and start the gather.
    func begin(at target: CaretLocator.Target) {
        closeTask?.cancel(); closeTask = nil
        model.begin(orbit: max(15, Double(target.height) * 0.95))
        let side = SwirlMath.canvasSide
        let frame = NSRect(x: target.point.x - side / 2, y: target.point.y - side / 2, width: side, height: side)
        let panel = self.panel ?? makePanel()
        panel.setFrame(frame, display: false)
        panel.collectionBehavior = Self.collectionBehavior
        panel.orderFrontRegardless()
    }

    /// The reply is here: complete the ring at the caret. Ignored unless the ring is gathering.
    func land() {
        guard case .gathering = model.phase else { return }
        model.transition(landing: true)
        scheduleClose(after: SwirlMath.landDuration)
    }

    /// Nothing to paste: loosen and fade. Ignored unless the ring is gathering.
    func dissolve() {
        guard case .gathering = model.phase else { return }
        model.transition(landing: false)
        scheduleClose(after: SwirlMath.dissolveDuration)
    }

    private func scheduleClose(after seconds: Double) {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            self.model.phase = .idle
        }
    }

    private func makePanel() -> NSPanel {
        let side = SwirlMath.canvasSide
        let panel = SwirlPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.level = .screenSaver
        panel.collectionBehavior = Self.collectionBehavior
        let host = NSHostingView(rootView: CaretSwirlView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        panel.contentView = host
        self.panel = panel
        return panel
    }
}

/// Never key, never main: the user's own field keeps keyboard focus for the paste.
private final class SwirlPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - The model (what phase the ring is in; the view derives every frame from time)

@MainActor @Observable
final class SwirlModel {
    enum Phase {
        case idle
        case gathering
        case landing(since: Date, from: SwirlMath.State)
        case dissolving(since: Date, from: SwirlMath.State)
    }

    var phase: Phase = .idle
    private(set) var began = Date()
    private(set) var orbit = 18.0
    private(set) var initialRadius = SwirlMath.startRadius

    func begin(orbit: Double, initialRadius: Double = SwirlMath.startRadius) {
        self.orbit = orbit
        self.initialRadius = initialRadius
        began = Date()
        phase = .gathering
    }

    /// Leave the gather from exactly where the ring is now, so the motion never jumps.
    func transition(landing: Bool) {
        let now = Date()
        let from = SwirlMath.gather(t: now.timeIntervalSince(began), orbit: orbit, initialRadius: initialRadius)
        phase = landing ? .landing(since: now, from: from) : .dissolving(since: now, from: from)
    }
}

// MARK: - The view

struct CaretSwirlView: View {
    let model: SwirlModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    private var paused: Bool {
        if case .idle = model.phase { return true }
        return false
    }

    /// Reduce Motion, the Sidekick override or Low Power Mode: the ring only fades.
    private var still: Bool {
        Motion.gated(Motion.standard, reduceMotion: motionOverride ?? reduceMotion) == nil
    }

    var body: some View {
        let isStill = still          // read once here, captured by value by the Canvas closure
        TimelineView(.animation(paused: paused)) { context in
            Canvas { graphics, size in
                guard let frame = SwirlMath.frame(phase: model.phase, began: model.began,
                                                  orbit: model.orbit, at: context.date,
                                                  initialRadius: model.initialRadius, still: isStill) else { return }
                SwirlMath.draw(frame, in: &graphics, size: size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The math (pure functions of time)

enum SwirlMath {
    /// The panel is a square of this side, centred on the caret; wide enough for the widest ring.
    static let canvasSide: CGFloat = 560
    /// nonisolated: SwirlModel.begin's default argument reads it from a nonisolated context.
    nonisolated static let startRadius = 168.0
    static let landDuration = 0.68
    static let dissolveDuration = 0.62

    /// The ring at an instant: a landing or a dissolve starts from exactly these numbers.
    struct State {
        var radius: Double      // points from the caret
        var angle: Double       // radians, clockwise on screen: where the highlight's head is
        var omega: Double       // revolutions per second
        var tighten: Double     // 0 (just appeared, wide) → 1 (settled at the caret)
    }

    /// What one frame draws: the ring, its travelling highlight arc and the brand mark.
    struct Frame {
        var radius, opacity, arcHead, arcSpan, arcOpacity, markOpacity: Double
    }

    private static let kRadius = 2.3, turn = 1.6, startScale = 2.2
    private static let arcSpan = Double.pi / 3                 // the highlight: 60° of the ring
    private static let markFade = 0.4                          // the mark's fade in and out
    private static let markGap = 12.0                          // points between the ring and the mark
    private static let markSide = 14.0

    /// The paste fires `landingDelay` after `land()`; the ring completes at that moment.
    private static var landingSplit: Double {
        let c = CaretSwirl.landingDelay.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    /// The gather: the radius closes from 2.2× the orbit to the orbit (exponential, so it eases
    /// in rather than stops), and the highlight turns once every 1.6 s.
    /// `initialRadius` is accepted for API compatibility. The ring always starts at 2.2× orbit.
    static func gather(t: Double, orbit: Double, initialRadius: Double = startRadius) -> State {
        let e = exp(-kRadius * t)
        return State(radius: orbit * (1 + (startScale - 1) * e), angle: 2 * .pi * t / turn,
                     omega: 1 / turn, tighten: 1 - e)
    }

    static func frame(phase: SwirlModel.Phase, began: Date, orbit: Double, at now: Date,
                      initialRadius: Double = startRadius, still: Bool = false) -> Frame? {
        let t = now.timeIntervalSince(began)
        switch phase {
        case .idle:
            return nil

        case .gathering:
            let base = gather(t: t, orbit: orbit, initialRadius: initialRadius)
            let fadeIn = min(max(t, 0) / 0.12, 1)
            return Frame(radius: still ? orbit : base.radius,
                         opacity: (still ? 0.6 : 0.35) * fadeIn,
                         arcHead: base.angle, arcSpan: arcSpan,
                         arcOpacity: still ? 0 : fadeIn, markOpacity: 0)

        case .landing(let since, let from):
            let u = max(now.timeIntervalSince(since), 0)
            let split = landingSplit
            let head = from.angle + 2 * .pi * u / turn
            if u < split {
                // The ring closes on the caret and completes as the paste lands.
                let k = u / split
                let ease = 1 - (1 - k) * (1 - k)
                let startOpacity = still ? 0.6 : 0.35
                return Frame(radius: still ? orbit : from.radius + (orbit - from.radius) * ease,
                             opacity: startOpacity + (1 - startOpacity) * k,
                             arcHead: head, arcSpan: arcSpan + (2 * .pi - arcSpan) * k,
                             arcOpacity: still ? 0 : 1, markOpacity: 0)
            }
            let q = (u - split) / markFade
            guard q < 1 else { return nil }                    // gone; the panel closes at landDuration
            return Frame(radius: orbit, opacity: 1 - q * q,
                         arcHead: head, arcSpan: 0, arcOpacity: 0,
                         markOpacity: sin(.pi * q))

        case .dissolving(let since, let from):
            let v = max(now.timeIntervalSince(since), 0)
            let p = min(v / dissolveDuration, 1)
            let fade = pow(1 - p, 1.3)
            return Frame(radius: still ? orbit : from.radius * (1 + 0.35 * p),
                         opacity: (still ? 0.6 : 0.35) * fade,
                         arcHead: from.angle + 2 * .pi * v / turn, arcSpan: arcSpan,
                         arcOpacity: still ? 0 : fade, markOpacity: 0)
        }
    }

    // MARK: The drawing (one Canvas pass, no filters)

    static func draw(_ f: Frame, in g: inout GraphicsContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = max(f.radius, 0)
        let accent = Color.accentColor
        let line = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        if f.opacity > 0.01 {
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            g.stroke(ring, with: .color(accent.opacity(f.opacity)), style: line)
        }

        // The highlight, a polyline (never Path.addArc, whose `clockwise` reads inverted on a
        // y-down canvas), sampled at most 3° apart.
        if f.arcOpacity > 0.01 && f.arcSpan > 0 {
            let steps = max(2, Int((f.arcSpan / (3 * .pi / 180)).rounded(.up)))
            let start = f.arcHead - f.arcSpan
            var arc = Path()
            for i in 0...steps {
                let a = start + f.arcSpan * Double(i) / Double(steps)
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
            }
            g.stroke(arc, with: .color(accent.opacity(f.arcOpacity)), style: line)
        }

        // The mark sits just above the ring, never on the freshly pasted text.
        if f.markOpacity > 0.01 {
            let rect = CGRect(x: c.x - markSide / 2, y: c.y - r - markGap - markSide / 2,
                              width: markSide, height: markSide)
            g.fill(BrandMark(variant: .compact).path(in: rect), with: .color(accent.opacity(f.markOpacity)))
        }
    }
}
