//
//  PromptBar.swift
//  Sentient OS macOS
//
//  AgentMode: what the agent may drive. The old PromptBar view was removed in the Home remake.
//

import SwiftUI

/// What the agent is allowed to drive when it acts on the user's request.
nonisolated enum AgentMode: String, CaseIterable {
    case computer
    var label: String { "Computer use" }
    var icon: String { "desktopcomputer" }
    /// The command-bar prompt phrase: "Using <promptPhrase>, <task>" — fed to CodexCLI.runAgentCommand.
    var promptPhrase: String { "computer use" }
}
