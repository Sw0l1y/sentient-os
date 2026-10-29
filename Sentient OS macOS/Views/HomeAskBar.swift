//
//  HomeAskBar.swift
//  Sentient OS macOS
//
//  Home's input, pinned to the bottom of the column the way Messages pins its field (SPEC-D1 S5):
//  the Ask field (SidekickComposer, which also draws its RecoveryCard, reply chip and error line)
//  floating in glass, then exactly one caption line under it — the notch hint while it is still
//  worth teaching, otherwise "Private by design." (both from HomeNotchHint).
//

import SwiftUI

struct HomeAskBar: View {
    let coordinator: CommandCoordinator
    let presentation: SidekickPresentation
    let isPresented: Bool
    let kbOnly: Bool
    let inConversation: Bool
    let focusRequest: Int
    let onAccepted: () -> Void

    var body: some View {
        VStack(spacing: Space.s) {
            if kbOnly {
                // The knowledge-base-only Home has no Sidekick; the field stays, disabled, and says why.
                TextField("Sidekick needs ChatGPT Plus", text: .constant(""))
                    .textFieldStyle(.plain)
                    .disabled(true)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
                    .floatingGlass(in: Capsule())
                    .accessibilityHint("Upgrade to ChatGPT Plus to use Sidekick")
            } else {
                SidekickComposer(coordinator: coordinator, presentation: presentation,
                                 isPresented: isPresented, onAccepted: onAccepted,
                                 focusRequest: focusRequest)
            }
            HomeNotchHint(coordinator: coordinator, allowsHint: !inConversation && !kbOnly)
        }
        .frame(maxWidth: PageMetrics.readingColumn)
        .padding(.horizontal, Space.xl)
        .padding(.bottom, Space.m)
        .frame(maxWidth: .infinity)
    }
}
