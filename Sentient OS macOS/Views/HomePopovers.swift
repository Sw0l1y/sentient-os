//
//  HomePopovers.swift
//  Sentient OS macOS
//
//  The Analysis status, built like the Time Machine / Backups status popover from the menu bar:
//   · HomeAnalysisSummary — the shared status block (things understood, the vault, last and next
//     run, why it is waiting). Home's Today block and the popover both draw THIS view, so their
//     counts can never disagree. It carries no accessibility ids (both surfaces embed it).
//   · AnalysisPopover — the summary, the live status line, a two-column source checklist (the
//     inputs to analysis), the overnight-on-battery switch and one default button.
//  The vault counts are real (disk); the demo deck substitutes its showcase last-run stamp.
//  SPEC-D1 S13.
//

import SwiftUI
import AppKit

/// Which sources are armed to run — drives the Analysis popover's source checklist.
struct HomeSources: Equatable {
    var files = true
    var whatsapp = false
    var imessage = false
    var notes = false
    var whatsappAvailable = true   // false → WhatsApp isn't installed on this Mac; hide its row entirely
}

// MARK: - The shared summary

/// What analysis has done and what it will do next. `sources` and `customRoots` are kept for the
/// cross-package signature (SPEC-00 Part 9); the source checklist lives in AnalysisPopover only.
/// It does NOT draw `processing.statusLine`: Today shows that line as its status button, the
/// popover as its own line, so it appears once per surface.
struct HomeAnalysisSummary: View {
    let thingsUnderstood: Int
    let sources: HomeSources
    let lastRun: String                    // last full cycle, pre-formatted by HomeView (deck-aware)
    let nextWakeAt: Date?
    let schedulerEnabled: Bool
    let schedulerNeedsSetup: Bool
    let customRoots: [URL]

    @State private var processing = ProcessingCoordinator.shared
    @State private var vault: (notes: Int, domains: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(understoodLine)
                    .font(.headline)
                    .monospacedDigit()
                Text(vaultLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.xs) {
                GridRow {
                    Text("Last Run").foregroundStyle(.secondary)
                    Text(lastRun)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Text("Next Run").foregroundStyle(.secondary)
                    Text(nextRunLine)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.callout)
            if case .waiting = processing.state {
                StatusLabel(processing.waitingDetail, tone: .warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = processing.record.notice, !notice.isEmpty {
                StatusLabel(notice, tone: .warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { vault = HomeStats.countVault() }
    }

    private var understoodLine: String {
        switch thingsUnderstood {
        case 0:  "Ready to begin."
        case 1:  "1 thing understood."
        default: "\(thingsUnderstood.formatted()) things understood."
        }
    }

    private var vaultLine: String {
        guard let v = vault, v.notes > 0 else { return "No vault yet · your first analysis builds it" }
        return "\(v.notes) notes · \(v.domains) domains in your knowledge"
    }

    private var nextRunLine: String {
        if processing.paused { return "Paused until you resume" }
        if schedulerNeedsSetup { return "Set up overnight wake in Settings" }
        if let nextWakeAt { return ProcessingCoordinator.scheduleLabel(nextWakeAt) }
        if schedulerEnabled { return "Scheduling the next overnight run…" }
        return "Overnight processing is off"
    }
}

// MARK: - The popover

struct AnalysisPopover: View {
    let thingsUnderstood: Int
    let sources: HomeSources               // for whatsappAvailable (hide the row when WhatsApp isn't installed)
    let lastRun: String                    // last full cycle, pre-formatted by HomeView (deck-aware)
    var nextWakeAt: Date? = nil
    var schedulerEnabled = false
    var schedulerNeedsSetup = false
    @State private var processing = ProcessingCoordinator.shared
    var onAnalyze: () -> Void
    var onPickWhatsApp: () -> Void = {}    // WhatsApp / iMessage open the chat picker (in HomeView)
    var onPickIMessage: () -> Void = {}
    var onPickGmail: () -> Void = {}       // Gmail / Calendar open the connect sheet (in HomeView)
    var onPickAppleMail: () -> Void = {}
    var onPickCalendar: () -> Void = {}
    var customRoots: [URL] = []            // session folders added in Dev Tools — shown so this mirrors the picker exactly

    // Live source selection — the SAME keys SourceSelection / DevTools use. @AppStorage so a click toggles
    // the real selection AND the row updates instantly. FDA is still enforced at run time (Analyze Now).
    @AppStorage("dbg.run.downloads")      private var runDownloads = false
    @AppStorage("dbg.run.desktop")        private var runDesktop = false
    @AppStorage("dbg.run.documents")      private var runDocuments = false
    @AppStorage("dbg.run.notes")          private var runNotes = false
    @AppStorage(SiYuanSource.enabledKey)  private var runSiYuan = false
    @AppStorage(AppleMailSelection.key)    private var appleMailAccounts = ""
    @AppStorage("dbg.whatsapp.chats")     private var whatsappCSV = ""
    @AppStorage("dbg.imessage.chats")     private var imessageCSV = ""
    @AppStorage("dbg.run.gmail")          private var runGmail = false
    @AppStorage("dbg.run.calendar")       private var runCalendar = false

    // The overnight run's battery preference — the production scheduler key, so the 3 AM gate and this
    // switch are one truth. Battery processing is on by default; an explicit off choice is retained.
    @AppStorage(OvernightScheduler.allowBatteryKey) private var overnightOnBattery = true

    @State private var hasBattery = false   // desktop Macs hide the battery row entirely

    private var anyArmed: Bool {
        runDownloads || runDesktop || runDocuments || runNotes || (runSiYuan && SiYuanSource.isInstalled)
            || !customRoots.isEmpty
            || !whatsappCSV.isEmpty || !imessageCSV.isEmpty
            || !appleMailAccounts.isEmpty || runGmail || runCalendar || !MCPSource.kbSlugs().isEmpty
    }
    private var armed: Bool {
        anyArmed || processing.isBusy || processing.record.status == .scheduled || processing.record.status == .requested
    }

    private static let batteryInfo = "Overnight on battery: 50% for first analysis, 30% for updates. Pauses at 20% to save power. Run now has no battery requirement."

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.s) {
                HomeAnalysisSummary(thingsUnderstood: thingsUnderstood, sources: sources, lastRun: lastRun,
                                    nextWakeAt: nextWakeAt, schedulerEnabled: schedulerEnabled,
                                    schedulerNeedsSetup: schedulerNeedsSetup, customRoots: customRoots)
                Text(processing.statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: Space.s) {
                Text("Sources")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: Space.xs) {
                    sourceList
                }
            }

            if hasBattery {
                HStack(spacing: Space.s) {
                    if armed {
                        Toggle("Run on battery too", isOn: $overnightOnBattery)
                            .toggleStyle(.switch)
                    } else {
                        Text("Overnight on battery")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Space.s)
                    InfoPopoverButton(Self.batteryInfo, title: "Battery")
                }
                .font(.callout)
            }

            HStack {
                Spacer()
                Button(analyzeButtonTitle, action: onAnalyze)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!armed)
            }
        }
        .padding(Space.l)
        .frame(width: PageMetrics.popover)
        .task { hasBattery = PowerState.batteryPercent() != nil }
    }

    /// The same sources, in the same order, as the old chip rows.
    @ViewBuilder private var sourceList: some View {
        SourceChip("Downloads", on: runDownloads) { runDownloads.toggle() }
        SourceChip("Desktop",   on: runDesktop)   { runDesktop.toggle() }
        SourceChip("Documents", on: runDocuments) { runDocuments.toggle() }
        // Session folders added in Dev Tools — shown (✓) so the popover mirrors the picker
        // exactly; add/remove still lives in Dev Tools (the owner of the session roots).
        ForEach(customRoots, id: \.self) { url in
            SourceChip(url.lastPathComponent, on: true)
        }
        if sources.whatsappAvailable {
            SourceChip("WhatsApp", on: !whatsappCSV.isEmpty, action: onPickWhatsApp)
        }
        SourceChip("iMessage", on: !imessageCSV.isEmpty, action: onPickIMessage)
        SourceChip("Notes", on: runNotes) { runNotes.toggle() }
        SourceChip("Apple Mail", on: !appleMailAccounts.isEmpty, action: onPickAppleMail)
        if SiYuanSource.isInstalled {
            SourceChip("SiYuan", on: runSiYuan) { runSiYuan.toggle() }
        }
        SourceChip("Gmail", on: runGmail, locked: CodexAuth.connectorsLocked, action: onPickGmail)
        SourceChip("Calendar", on: runCalendar, locked: CodexAuth.connectorsLocked, action: onPickCalendar)
    }

    private var analyzeButtonTitle: String {
        if processing.isBusy || processing.record.status == .requested { return "View Progress" }
        if processing.paused { return "Resume Analysis" }
        return processing.record.status == .scheduled ? "Start Now" : "Analyze Now"
    }
}

// MARK: - Shared bits

/// One source in the checklist (a filled check when armed). Clickable when an `action` is set
/// (toggles a source / opens a chat picker or connect sheet). `locked` (knowledge-base-only mode's
/// Gmail/Calendar) shows a lock, ignores its action and explains itself in the help tag.
struct SourceChip: View {
    let name: String
    let on: Bool
    var locked: Bool = false
    var action: (() -> Void)? = nil

    init(_ name: String, on: Bool, locked: Bool = false, action: (() -> Void)? = nil) {
        self.name = name; self.on = on; self.locked = locked; self.action = action
    }

    var body: some View {
        if locked {
            label
                .foregroundStyle(.secondary)
                .help(CodexAuth.connectorLockedTip)
                .accessibilityElement(children: .combine)
                .accessibilityValue("Locked")
        } else if let action {
            Button(action: action) { label }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .accessibilityValue(on ? "On" : "Off")
        } else {
            label
                .accessibilityElement(children: .combine)
                .accessibilityValue(on ? "On" : "Off")
        }
    }

    private var label: some View {
        Label {
            Text(name).lineLimit(1)
        } icon: {
            Image(systemName: locked ? "lock.fill" : on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(locked ? AnyShapeStyle(.tertiary)
                                 : on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .font(.callout)
    }
}

enum HomeStats {
    /// Counts the real vault on disk (notes = .md files, domains = top-level folders).
    static func countVault() -> (notes: Int, domains: Int)? {
        let fm = FileManager.default
        let root = VaultGenerator.vaultRoot
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        var notes = 0
        for case let url as URL in walker where url.pathExtension == "md" { notes += 1 }
        let domains = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter {
                !$0.lastPathComponent.hasPrefix(".")
                    && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.count) ?? 0
        return (notes, domains)
    }
}

#Preview("Analysis") {
    HStack(spacing: 0) {
        AnalysisPopover(thingsUnderstood: 3339, sources: .init(files: true, whatsapp: true, imessage: true, notes: true),
                        lastRun: "3:41 AM", onAnalyze: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)
        AnalysisPopover(thingsUnderstood: 3339, sources: .init(files: true, whatsapp: true, imessage: true, notes: true),
                        lastRun: "3:41 AM", onAnalyze: {})
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
    }
}
