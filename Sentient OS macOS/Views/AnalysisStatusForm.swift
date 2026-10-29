// AnalysisStatusForm.swift
// The words the Analysis page and its window subtitle show for each analysis state: the
// short subtitle, the status-header headline, and the per-cause failure title, body and symbol.
// Pure presentation helpers, no state. ProcessingView and ProcessingWindowView both read them,
// so the subtitle and the page can never disagree.
// Doc: Documentation - Views - Home, Processing & Shared UI.md

import SwiftUI

enum AnalysisStatusText {
    /// The window subtitle for the Analysis page (SPEC-00 5.6): a short state, never an action.
    /// `initialComplete` separates "Up to date" from a first analysis that has not run yet.
    static func subtitle(state: ProcessingCoordinator.State, progress: RunProgress,
                         needsAnotherPass: Bool, gated: Bool, initialComplete: Bool = true) -> String {
        if gated { return "Not started" }
        switch state {
        case .idle: return initialComplete ? "Up to date" : "Not started"
        case .scheduled: return "Scheduled"
        case .waiting: return "Waiting"
        case .paused: return "Paused"
        case .stopping: return "Pausing…"
        case .loadingModel: return "Analyzing"
        case .processing:
            let percent = progress.total > 0 ? Int(Double(progress.done) / Double(progress.total) * 100) : 0
            return "Analyzing · \(percent)%"
        case .preparing: return "Building knowledge"
        case .completed: return needsAnotherPass ? "Needs attention" : "Up to date"
        case .failed, .diskFull: return "Needs attention"
        }
    }

    /// The status header's headline, one per state (SPEC-D3 A2–A5).
    static func headline(state: ProcessingCoordinator.State, progress: RunProgress, needsAnotherPass: Bool,
                         prepStatus: String, onDevice: Bool, cloudLabel: String) -> String {
        switch state {
        case .idle: return "Ready to Analyze"
        case .scheduled: return "Analysis Scheduled"
        case .waiting: return "Waiting to Start"
        case .paused: return "Analysis Paused"
        case .stopping: return "Pausing…"
        case .loadingModel: return onDevice ? "Loading On-Device Model…" : cloudLabel + "…"
        case .processing: return progress.sourceRead.map { "Analyzing \($0.name)" } ?? "Analyzing Your Sources"
        case .preparing: return prepStatus
        case .completed:
            return !progress.sourceReadFailures.isEmpty ? "Some sources need another try"
                : needsAnotherPass ? "Analysis saved" : "Analysis complete"
        case .failed(let failure): return failureTitle(failure.kind)
        case .diskFull: return failureTitle(.diskFull)
        }
    }

    /// Another pass is needed when the run left a notice, a source read failed, or Apple Mail
    /// did not finish or deferred messages.
    static func needsAnotherPass(notice: String?, progress: RunProgress) -> Bool {
        notice != nil || !progress.sourceReadFailures.isEmpty
            || progress.mailIncomplete || progress.mailDeferred > 0
    }

    static func failureTitle(_ kind: OvernightCaution.Kind?) -> String {
        let claude = ModelBackend.current == .claude
        return switch kind {
        case .loggedOut:      claude ? "Claude Isn’t Signed In" : "Codex Isn’t Logged In"
        case .usageLimit:     claude ? "Claude Usage Limit Reached" : "ChatGPT Usage Limit Reached"
        case .noInternet:     "No Internet Connection"
        case .inputTooLarge:  "This Batch Was Too Big to Send"
        case .diskFull:       "Your Mac’s Disk Is Full"
        case .connectorAuth:  "A Connected App Needs a Fresh Sign-In"
        case .stalled:        "Processing Got Stuck"   // recorded only by the 3 AM watchdog; here for exhaustiveness
        case nil:             "Processing Failed"
        }
    }

    /// Classified failures get a friendly, actionable line (the raw detail is in the log +
    /// Sentry); unclassified ones show the step's own message, as before.
    static func failureBody(kind: OvernightCaution.Kind?, message: String) -> String {
        let claude = ModelBackend.current == .claude
        return switch kind {
        case .loggedOut:      claude
            ? "Sentient runs on your own Claude account through Claude Code, and that sign-in has stopped working. Sign back in and I’ll pick up right where we stopped."
            : "Sentient runs on your own ChatGPT account through codex, and that login has stopped working. Log back in and I’ll pick up right where we stopped."
        case .usageLimit:     "Your plan’s window resets on its own. Everything so far is saved; retry in a while and I’ll pick up right where we stopped."
        case .noInternet:     "This step runs in the cloud. Once you’re back online, hit Retry; everything so far is saved."
        case .inputTooLarge:  claude
            ? "Sentient tried to send Claude more than it accepts in one request. Your analysis is saved; if a retry hits this again, update Sentient OS and retry once more."
            : "Sentient tried to send ChatGPT more than it accepts in one request. Your analysis is saved; if a retry hits this again, update Sentient OS and retry once more."
        case .diskFull:       "I can’t save what I read until there’s room on this Mac. Free up some space (a few GB is plenty), then hit Retry; everything so far is saved and I’ll pick up right where we stopped."
        case .connectorAuth:  claude
            ? "One of your connected apps has stopped accepting its sign-in. Reconnect it on claude.ai, then hit Retry; everything so far is saved."
            : "One of your connected apps has stopped accepting its sign-in. Reconnect it on chatgpt.com, then hit Retry; everything so far is saved."
        case .stalled:        "The work stopped making progress, so I ended it. Everything so far is saved; hit Retry and I’ll pick up right where we stopped."
        case nil:             message
        }
    }

    /// One symbol per cause, so a failure is never just a generic triangle.
    static func failureSymbol(_ kind: OvernightCaution.Kind?) -> String {
        switch kind {
        case .loggedOut:      "person.crop.circle.badge.exclamationmark"
        case .usageLimit:     "hourglass"
        case .noInternet:     "wifi.slash"
        case .inputTooLarge:  "arrow.up.doc"
        case .diskFull:       "externaldrive.badge.exclamationmark"
        case .connectorAuth:  "key.slash"
        case .stalled:        "clock.badge.exclamationmark"
        case nil:             "exclamationmark.triangle"
        }
    }
}
