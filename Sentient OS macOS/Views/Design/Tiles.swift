//
//  Tiles.swift
//  Sentient OS macOS
//
//  The icon-tile catalogue (SPEC-00 2.5), declared once. Packages reference these statics and
//  never re-type a symbol/color pair for anything in the catalogue.
//

import SwiftUI

nonisolated struct TileSpec: Hashable, Sendable {
    let symbol: String
    let color: TileColor

    init(_ symbol: String, _ color: TileColor) {
        self.symbol = symbol
        self.color = color
    }

    // MARK: Permissions and system rows
    static let fullDiskAccess = TileSpec("internaldrive.fill", .gray)
    static let accessibility = TileSpec("accessibility", .blue)
    static let screenRecording = TileSpec("rectangle.dashed.badge.record", .red)
    static let automation = TileSpec("gearshape.2.fill", .gray)
    static let microphone = TileSpec("mic.fill", .orange)
    static let speech = TileSpec("waveform", .red)
    static let notifications = TileSpec("bell.badge.fill", .red)
    static let launchAtLogin = TileSpec("power", .green)
    static let overnight = TileSpec("moon.fill", .indigo)
    static let computerUse = TileSpec("cursorarrow.rays", .green)
    static let onDeviceModel = TileSpec("cpu", .purple)
    static let codex = TileSpec("terminal.fill", .gray)
    static let privacy = TileSpec("hand.raised.fill", .blue)
    static let diagnostics = TileSpec("stethoscope", .gray)
    static let invitations = TileSpec("gift.fill", .pink)
    static let updates = TileSpec("arrow.down.circle.fill", .blue)
    static let reset = TileSpec("arrow.counterclockwise", .orange)
    static let uninstall = TileSpec("trash.fill", .red)
    static let customInstructions = TileSpec("text.quote", .teal)
    static let memory = TileSpec("brain.head.profile.fill", .pink)
    static let speed = TileSpec("gauge.with.dots.needle.67percent", .orange)
    static let shortcutKey = TileSpec("command", .gray)
    static let notch = TileSpec("rectangle.topthird.inset.filled", .indigo)
    static let morningSuggestions = TileSpec("sun.horizon.fill", .orange)
    static let writingExamples = TileSpec("pencil.and.list.clipboard", .green)
    static let sharing = TileSpec("antenna.radiowaves.left.and.right", .teal)

    // MARK: Source categories and engines
    static let emailAndCalendar = TileSpec("envelope.fill", .blue)
    static let conversations = TileSpec("bubble.left.and.bubble.right.fill", .green)
    static let moreOfYourWorld = TileSpec("square.grid.2x2.fill", .gray)
    /// Fallback when Finder's folder icon is unavailable (AppIconImage(fileAt:) is preferred).
    static let folder = TileSpec("folder.fill", .blue)
    /// ChatGPT and Claude stand-ins until brand assets exist in the catalog (D4 open issue 4,
    /// promoted from FrontierEnginePicker at integration; ChatGPTSignInSheet uses the same one).
    static let engineChatGPT = TileSpec("bubble.left.fill", .green)
    static let engineClaude = TileSpec("asterisk", .orange)
    static let engineOpenRouter = TileSpec("globe", .indigo)
    static let engineLMStudio = TileSpec("desktopcomputer", .gray)
    static let engineCustom = TileSpec("slider.horizontal.3", .gray)

    // MARK: Home notices (NoticeBar, 30 pt)
    static let noticeSignedOut = TileSpec("person.crop.circle.badge.exclamationmark", .orange)
    static let noticeHealth = TileSpec("stethoscope", .red)
    static let noticeUpdating = TileSpec("arrow.down.circle.fill", .blue)
    static let noticeUpdateFailed = TileSpec("exclamationmark.triangle.fill", .red)
    static let noticeOvernight = TileSpec("moon.fill", .indigo)
    static let noticeConnector = TileSpec("link.badge.plus", .orange)
    static let noticeUpToDate = TileSpec("checkmark.circle.fill", .green)
    static let noticeAppUpdated = TileSpec("sparkles", .blue)
    static let noticeInvite = TileSpec("gift.fill", .pink)

    // MARK: Suggestions and pages
    /// The sealed gift letter (not a suggestion method).
    static let giftLetter = TileSpec("gift.fill", .pink)
    /// Demo/showcase deck rows without a method.
    static let demoSuggestion = TileSpec("sparkles", .indigo)
    /// The Analysis page and its status header.
    static let analysis = TileSpec("waveform.path", .purple)
    /// AppIconImage's fallback when an app is not installed.
    static let genericApp = TileSpec("app.fill", .gray)

    // MARK: Setup Assistant pages and gates (64 pt)
    static let setupChooseAI = TileSpec("cpu.fill", .purple)
    static let setupDoubleTap = TileSpec("hand.tap.fill", .orange)
    static let setupSidekick = TileSpec("sparkles", .indigo)
    static let gateComputerUse = TileSpec("cursorarrow.rays", .green)
    static let gateUpgrade = TileSpec("arrow.down.circle.fill", .blue)
    static let gateDoctor = TileSpec("stethoscope", .green)
    static let setupModelDownload = TileSpec("arrow.down.circle.fill", .purple)
    static let setupUninstall = TileSpec("trash.fill", .red)
    /// The invite celebration sheet (72 pt).
    static let inviteCelebration = TileSpec("gift.fill", .pink)

    // MARK: Finish Setup feature rows
    static let featureDoubleTap = TileSpec("hand.tap.fill", .orange)
    /// Morning suggestions (the `proactive` feature).
    static let featureProactive = TileSpec("sun.horizon.fill", .orange)
    static let featureKnowledge = TileSpec("books.vertical.fill", .brown)
    static let featureSidekick = TileSpec("sparkles", .indigo)

    /// The Settings pane tiles (20 pt in the sidebar).
    @MainActor static func pane(_ pane: SettingsView.Pane) -> TileSpec {
        switch pane {
        case .sources: return TileSpec("tray.full.fill", .blue)
        case .frontierModel: return TileSpec("cpu.fill", .purple)
        case .doubleTap: return TileSpec("hand.tap.fill", .orange)
        case .proactive: return TileSpec("sparkles", .indigo)
        case .shareKnowledge: return TileSpec("antenna.radiowaves.left.and.right", .teal)
        case .system: return TileSpec("gearshape.fill", .gray)
        case .health: return TileSpec("checkmark.shield.fill", .green)
        }
    }

    /// The suggestion-method tiles (30 pt). Symbol fallback only: rows show the target app's real
    /// icon (AppIconImage) or the connector's brand logo (LogoTile) when one is known.
    @MainActor static func method(_ method: PreparedAction.Method) -> TileSpec {
        switch method {
        case .computer: return TileSpec("cursorarrow.rays", .blue)
        case .gmail: return TileSpec("envelope.fill", .red)
        case .calendar: return TileSpec("calendar", .red)
        case .mcp: return TileSpec("puzzlepiece.extension.fill", .gray)
        case .research: return TileSpec("magnifyingglass", .purple)
        }
    }
}
