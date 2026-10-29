// An explicit, read-only helper check against a temporary Sentient-owned window.
// No model, customer app, clicks, TCC reads/writes, persistent readiness flag or stored payloads.
import AppKit
import Observation

@MainActor @Observable final class NativePermissionCheck {
    static let shared = NativePermissionCheck()
    private init() {}

    private(set) var snapshot = NativePermissionReadiness.Snapshot()
    private var helper: NSRunningApplication?
    private var configuration: OpenAIComputerUse.Configuration?
    @ObservationIgnored private var connection: OpenAIComputerUseSession?
    @ObservationIgnored private var activeCheck: Task<Void, Error>?
    @ObservationIgnored private var closingConnections: [UUID: Task<Void, Never>] = [:]
    private var activeCheckID: UUID?
    private var closeDepth = 0
    private var generation = UUID()
    var isChecking: Bool { activeCheckID != nil }

    /// Background callers only inspect this evidence. They never create a check window.
    func refresh() {
        guard snapshot.isReady else { return }
        guard let helper, !helper.isTerminated, let configuration,
              helper.bundleURL?.standardizedFileURL == configuration.appURL.standardizedFileURL,
              configuration.appURL == OpenAIComputerUse.appURL,
              OpenAIComputerUse.installation(at: configuration.appURL) != nil else { invalidate(); return }
    }

    func refresh(configuration: OpenAIComputerUse.Configuration, helper: NSRunningApplication) async {
        refresh()
        guard snapshot.isReady else { return }
        guard self.configuration == configuration, self.helper?.processIdentifier == helper.processIdentifier,
              await connection?.isUsable() == true else { invalidate(); return }
    }

    func invalidate(failure: NativeComputerUseFailure? = nil) {
        activeCheck?.cancel()
        clearEvidence(failure: failure)
    }

    private func clearEvidence(failure: NativeComputerUseFailure? = nil) {
        generation = UUID()
        snapshot = NativePermissionReadiness.afterFailure(failure)
        helper = nil; configuration = nil
        let previous = connection; connection = nil
        if let previous {
            let id = UUID()
            closingConnections[id] = Task {
                await previous.close()
                closingConnections[id] = nil
            }
        }
    }

    func close() async {
        closeDepth += 1
        defer { closeDepth -= 1 }
        let checking = activeCheck
        checking?.cancel()
        _ = await checking?.result
        let previous = connection; connection = nil
        clearEvidence()
        await previous?.close()
        // Invalidating a permission during an active task also retires the retained client.
        // Teardown must join those earlier retirements, not only the current connection.
        while !closingConnections.isEmpty {
            for closing in Array(closingConnections.values) { await closing.value }
        }
    }

    /// Called only by an explicit setup/check action or a user-started held computer task.
    /// Keeping this model-free connection alive preserves the tested helper process; otherwise
    /// idle teardown could immediately discard the proof before the user presses Continue.
    func check(configuration: OpenAIComputerUse.Configuration, helper: NSRunningApplication) async throws {
        try Task.checkCancellation()
        guard closeDepth == 0 else { throw CancellationError() }
        if let activeCheck {
            try await withTaskCancellationHandler { try await activeCheck.value } onCancel: { activeCheck.cancel() }
            try Task.checkCancellation()
        }
        guard closeDepth == 0 else { throw CancellationError() }
        refresh()
        if snapshot.isReady, self.configuration == configuration,
           self.helper?.processIdentifier == helper.processIdentifier,
           await connection?.isUsable() == true { return }
        let id = UUID()
        let task = Task { try await self.performCheck(configuration: configuration, helper: helper) }
        activeCheckID = id; activeCheck = task
        defer { if activeCheckID == id { activeCheck = nil; activeCheckID = nil } }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func performCheck(configuration: OpenAIComputerUse.Configuration, helper: NSRunningApplication) async throws {
        try Task.checkCancellation()
        let runtime = OpenAIComputerUseRuntime.shared
        guard let reservation = runtime.reserveDiagnostic() else { throw OpenAIComputerUse.RuntimeError.helperRunning }
        defer { runtime.endDiagnostic(reservation) }
        let previous = connection; connection = nil
        clearEvidence()
        await previous?.close()
        let lease = try await CodexRuntime.sharedRuntimeLease()
        defer { lease.unlock() }
        let configuration = try configuration.afterRuntimeLease()
        _ = try await OpenAIComputerUse.validate(at: configuration.appURL)
        try Task.checkCancellation()
        let checkID = generation
        let panel = NativePermissionCheckWindow()
        panel.show()
        defer { panel.close() }
        var opened: OpenAIComputerUseSession?
        do {
            // Give AppKit one frame before asking another process to read the new window.
            try await Task.sleep(for: .milliseconds(120))
            let session = try await OpenAIComputerUseSession.open(configuration)
            opened = session
            let result = try await NativePermissionReadiness.verify(app: Bundle.main.bundleURL.path,
                marker: panel.marker, isCurrent: { panel.isCurrent }, call: { tool, arguments in
                    try await session.call(tool, arguments: arguments, timeout: 12)
                })
            try Task.checkCancellation()
            guard generation == checkID, !helper.isTerminated else { throw CancellationError() }
            snapshot = result; self.helper = helper; self.configuration = configuration
            connection = session
        } catch {
            await opened?.close()
            if generation == checkID { clearEvidence(failure: error as? NativeComputerUseFailure) }
            throw error
        }
    }
}

@MainActor private final class NativePermissionCheckWindow {
    let marker = "Sentient permission check " + UUID().uuidString
    private let panel: NSWindow
    private weak var previous: NSWindow?
    /// A small system progress panel: a spinner, the status line (which carries the AX marker the
    /// readiness check looks for, so it stays a visible label) and "This closes automatically."
    init() {
        panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                         styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Checking computer use"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: "Checking computer use…")
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.setAccessibilityLabel(marker)
        let detail = NSTextField(labelWithString: "This closes automatically.")
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor

        let lines = NSStackView(views: [label, detail])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 2

        let row = NSStackView(views: [spinner, lines])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        row.translatesAutoresizingMaskIntoConstraints = false
        if let content = panel.contentView {
            content.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                row.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
                row.centerYAnchor.constraint(equalTo: content.centerYAnchor)
            ])
        }
    }
    var isCurrent: Bool {
        panel.isVisible && panel.isOnActiveSpace && !panel.isMiniaturized && NSApp.keyWindow === panel
    }
    func show() {
        previous = NSApp.keyWindow
        panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    func close() {
        let restore = NSApp.keyWindow === panel
        panel.close()
        if restore, let previous, previous.isVisible { previous.makeKeyAndOrderFront(nil) }
    }
}
