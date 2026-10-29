//
// OnboardingReadyView.swift
// The Finish Setup page's content: the same source picker Settings uses, as a grouped form,
// closed by a pinned Setup Assistant footer with the count, the explainer and Start Analysis.
// Start requires the shared three-source minimum and opens the analysis timing sheet. The
// selection feeds the first analysis and overnight runs.
// Doc: Documentation - Onboarding.md
//

import SwiftUI
import AppKit
import Observation

struct OnboardingReadyView: View {
    let onStart: (ProcessingCoordinator.Timing) -> Void
    var isProcessing = false
    @AppStorage(PersonalSetupProgress.stageKey) private var stageRaw = PersonalSetupProgress.Stage.sources.rawValue
    @State private var selectionCount = SourceSelection.selectionCount
    @State private var showTiming = false
    @State private var timingHandoff = AnalysisTimingHandoff()
    @AppStorage(PersonalSetupProgress.homeKey) private var homeAdmitted = false
    private var canStart: Bool { !isProcessing && !timingHandoff.isPending && selectionCount >= SourceSelection.minimumSelections }
    private var minimumMet: Bool { selectionCount >= SourceSelection.minimumSelections }

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: geometry.size.width, height: geometry.size.height)
                .sheet(isPresented: $showTiming, onDismiss: {
                    stageRaw = PersonalSetupProgress.Stage.sources.rawValue
                    timingHandoff.sheetDidDismiss()
                }) {
                    AnalysisTimingSheet(viewportHeight: max(420, min(620, geometry.size.height - 16))) { timing in
                        if timingHandoff.choose(timing, onStart: onStart) { showTiming = false }
                    }
                }
        }
        .background(AnalysisTimingOwnerAttachment(handoff: timingHandoff))
        .pageSubtitle(minimumMet ? "Ready to analyze" : "Choose at least 3 sources", page: .setup)
        .onDisappear { timingHandoff.cancel() }
        .onChange(of: homeAdmitted) { _, admitted in
            if !admitted { timingHandoff.cancel(); showTiming = false }
        }
        .onAppear {
            selectionCount = SourceSelection.selectionCount
            showTiming = stageRaw == PersonalSetupProgress.Stage.timing.rawValue && canStart
        }
    }

    /// The picker is the page's Form (it owns its sheets and tasks), so the introduction goes in
    /// as its leading section. Start Analysis is pinned below the form, so it stays on screen
    /// however long the source list grows.
    private var content: some View {
        KnowledgeSourcesPicker(context: .onboarding) { count in
            selectionCount = count
        }
        .leadingSections {
            Section {} header: {
                Text("Choose at least three sources to give Sentient personal context. You can add more later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                SetupAssistantFooter(primaryTitle: "Start Analysis", primaryEnabled: canStart,
                                     primaryID: "personalSetup.startAnalysis") {
                    VStack(alignment: .leading, spacing: 2) {
                        StatusLabel(countText, tone: canStart ? .ok : .warning)
                        explainer
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } primary: {
                    startAnalysis()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Space.m)
            }
            .background(.bar)
        }
    }

    private var countText: String {
        canStart ? "\(selectionCount) sources chosen"
                 : "\(selectionCount) of \(SourceSelection.minimumSelections) minimum chosen"
    }

    private var explainer: Text {
        CodexAuth.knowledgeBaseOnly
            ? Text("Choose when to build your knowledge.")
            : Text("Keep using Sidekick while your Mac learns. Analysis runs in the background to give Sidekick personal context and unlock Double Tap.")
    }

    private func startAnalysis() {
        // Recheck the persisted selection in case a connection changed this turn.
        guard SourceSelection.selectionCount >= SourceSelection.minimumSelections else { return }
        stageRaw = PersonalSetupProgress.Stage.timing.rawValue
        showTiming = true
    }
}

#if DEBUG
#Preview("Finish Setup") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingReadyView(onStart: { _ in })
                .frame(width: 900, height: 700)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
#endif

/// SwiftUI's onDismiss can precede AppKit's actual sheet detachment. Keep the chosen action
/// until both lifecycle signals agree, so its callback may safely close the setup window.
@MainActor @Observable
final class AnalysisTimingHandoff {
    private(set) var isPending = false
    @ObservationIgnored private weak var owner: NSWindow?
    @ObservationIgnored private var chosen: ProcessingCoordinator.Timing?
    @ObservationIgnored private var onStart: ((ProcessingCoordinator.Timing) -> Void)?
    @ObservationIgnored private var swiftUIDismissed = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var delivery: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var nativeSheetObservation: NSKeyValueObservation?

    func attach(to window: NSWindow?) {
        guard owner !== window else { return }
        cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        nativeSheetObservation?.invalidate(); nativeSheetObservation = nil
        owner = window
        guard let window else { return }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification,
            object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleDelivery() }
            })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
            object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        nativeSheetObservation = window.observe(\.attachedSheet, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.scheduleDelivery() }
        }
    }

    @discardableResult
    func choose(_ timing: ProcessingCoordinator.Timing, onStart: @escaping (ProcessingCoordinator.Timing) -> Void) -> Bool {
        guard owner != nil, !isPending else { return false }
        generation &+= 1
        chosen = timing; self.onStart = onStart
        swiftUIDismissed = false; isPending = true
        return true
    }

    func sheetDidDismiss() {
        guard isPending else { return }
        swiftUIDismissed = true
        scheduleDelivery()
    }

    func cancel() {
        generation &+= 1
        delivery?.cancel(); delivery = nil
        chosen = nil; onStart = nil; swiftUIDismissed = false; isPending = false
    }

    private func scheduleDelivery() {
        guard isPending, swiftUIDismissed, delivery == nil else { return }
        let ticket = generation
        delivery = Task { @MainActor [weak self] in
            // Finish the current AppKit notification/update before inspecting attachment.
            // This is event-driven; no guessed animation duration or polling timer is used.
            await Task.yield()
            guard let self, !Task.isCancelled, self.generation == ticket else { return }
            self.delivery = nil
            guard self.swiftUIDismissed, let owner = self.owner, owner.attachedSheet == nil,
                  let timing = self.chosen, let callback = self.onStart else { return }
            self.cancel() // consume before callbacks can close/reset/recreate the owner
            callback(timing)
        }
    }
}

/// Mounted in the parent content, not the sheet. Moving/closing the owner invalidates the
/// handoff, including late SwiftUI dismissal or native notification callbacks after reset.
private struct AnalysisTimingOwnerAttachment: NSViewRepresentable {
    let handoff: AnalysisTimingHandoff
    func makeNSView(context: Context) -> Attachment { Attachment(handoff: handoff) }
    func updateNSView(_ view: Attachment, context: Context) { view.handoff = handoff; handoff.attach(to: view.window) }
    static func dismantleNSView(_ view: Attachment, coordinator: ()) { view.handoff?.attach(to: nil) }

    final class Attachment: NSView {
        weak var handoff: AnalysisTimingHandoff?
        init(handoff: AnalysisTimingHandoff) { self.handoff = handoff; super.init(frame: .zero) }
        required init?(coder: NSCoder) { return nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); handoff?.attach(to: window) }
    }
}
