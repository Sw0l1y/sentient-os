// Shared pieces of the gate windows (SPEC-D7 1.1): a grouped Form that sizes itself inside a
// Setup Assistant page, the permission row with an optional fix button, and the window chrome
// every gate window applies (system window background, system appearance).
// Doc: Documentation - Permission Gate & Guide.md

import SwiftUI
import AppKit

/// A grouped Form sized to its own content, for use inside SetupAssistantPage's ScrollView.
/// A Form inside a ScrollView collapses to zero height, so this one measures its scroll content
/// and pins its frame to it. Rows inside look exactly like Health's rows.
struct GateForm<Content: View>: View {
    private let content: Content
    @State private var height: CGFloat = 120

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)          // the sections keep their own grouped fill
            .scrollDisabled(true)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
            }, action: { _, measured in
                // Whole points only, so a sub-point jitter cannot loop layout.
                let rounded = measured.rounded(.up)
                if abs(rounded - height) >= 1 { height = rounded }
            })
            .frame(height: max(height, 44))
    }
}

/// StatusRow with an optional fix button. StatusLine(fixTitle:) hid its button whenever fix
/// was nil; StatusRow's fix overload always draws one. This wrapper restores the old meaning.
struct GatePermissionRow: View {
    private let title: String
    private let tile: TileSpec?
    private let detail: String
    private let tone: StatusTone
    private let info: String?
    private let fixTitle: String?
    private let fix: (() -> Void)?

    init(_ title: String, tile: TileSpec?, detail: String, tone: StatusTone, info: String? = nil,
         fixTitle: String? = nil, fix: (() -> Void)? = nil) {
        self.title = title
        self.tile = tile
        self.detail = detail
        self.tone = tone
        self.info = info
        self.fixTitle = fixTitle
        self.fix = fix
    }

    var body: some View {
        if let fixTitle, let fix {
            StatusRow(title, tile: tile, detail: detail, tone: tone, info: info, fixTitle: fixTitle, fix: fix)
        } else {
            StatusRow(title, tile: tile, detail: detail, tone: tone, info: info)
        }
    }
}

/// Window chrome shared by the gate windows: the opaque system window background in the system
/// appearance (no forced dark, no black). Called below ComputerUseGate's "// MARK: Window
/// lifecycle" marker and in the DoubleTap, upgrade and Doctor present code.
enum GateWindowStyle {
    static func apply(to window: NSWindow, hidesTitle: Bool = true) {
        window.appearance = nil
        window.backgroundColor = .windowBackgroundColor
        if hidesTitle {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
    }
}

#Preview("Gate rows") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            SetupAssistantPage(tile: .gateComputerUse, title: "Allow Sidekick to Use Your Computer") {
                GateForm {
                    Section {
                        GatePermissionRow("Accessibility", tile: .accessibility, detail: "Granted", tone: .ok,
                                          info: "Lets Sentient read windows and act inside your apps.")
                        GatePermissionRow("Screen Recording", tile: .screenRecording, detail: "Not granted",
                                          tone: .error, fixTitle: "Allow…", fix: {})
                    } header: {
                        Text("Sentient Permissions")
                    } footer: {
                        Text("When setup is complete, focus your reply field and double tap again.")
                    }
                }
            }
            .frame(width: 560, height: 520)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
}
