//
//  HomeAskBar.swift
//  Sentient OS macOS
//
//  Home's input, pinned to the bottom of the column the way Messages pins its field (SPEC-D1 S5):
//  the Ask field (SidekickComposer, which also draws its RecoveryCard, reply chip and error line)
//  floating in glass, then exactly one caption line under it (HomeAskCaption) — the notch hint
//  while it is still worth teaching, otherwise "Private by design." (both from HomeNotchHint).
//
//  The caption is not part of the floating bar: HomeView stacks it on the page below the scroll
//  view. Text in the bar that is not on glass makes the system draw the bar's scroll edge hard (an
//  opaque band that slices rows), whatever style the page asks for; with only glass in the bar the
//  rows fade softly under the field.
//

import SwiftUI

struct HomeAskBar: View {
    let coordinator: CommandCoordinator
    let presentation: SidekickPresentation
    let isPresented: Bool
    let kbOnly: Bool
    let focusRequest: Int
    let onAccepted: () -> Void

    var body: some View {
        Group {
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
        }
        .frame(maxWidth: PageMetrics.readingColumn)
        .padding(.horizontal, Space.xl)
        // The gap to the caption, which starts where the scroll view ends.
        .padding(.bottom, Space.s)
        .frame(maxWidth: .infinity)
    }
}

/// The one caption line under the Ask bar, on the page itself, in the bar's column.
struct HomeAskCaption: View {
    let coordinator: CommandCoordinator
    let kbOnly: Bool
    let inConversation: Bool

    var body: some View {
        HomeNotchHint(coordinator: coordinator, allowsHint: !inConversation && !kbOnly)
            .frame(maxWidth: PageMetrics.readingColumn)
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.m)
            .frame(maxWidth: .infinity)
    }
}
