// Shared setup window layout and Sentient's own permission rows for Double Tap and computer use.
// PermissionSetupView is a Setup Assistant privacy page (tile, large title, a grouped list of
// permission rows, the primary action pinned at the bottom); SentientAppPermissionRows opens the
// existing grant flows.
// Doc: Documentation - Permission Gate & Guide.md

import SwiftUI
import AppKit

struct PermissionSetupView<Content: View>: View {
    private let tile: TileSpec?
    private let title: String
    private let caption: String?
    private let message: String?
    private let continueTitle: String
    private let canContinue: Bool
    private let primaryID: String?
    private let onContinue: () -> Void
    private let content: Content

    /// The existing call shape: no tile, the "One-time setup" caption.
    init(title: String, continueTitle: String, canContinue: Bool, onContinue: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.init(tile: nil, title: title, continueTitle: continueTitle, canContinue: canContinue,
                  onContinue: onContinue, content: content)
    }

    init(tile: TileSpec?, title: String, caption: String? = "One-time setup", message: String? = nil,
         continueTitle: String, canContinue: Bool, primaryID: String? = nil,
         onContinue: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.tile = tile
        self.title = title
        self.caption = caption
        self.message = message
        self.continueTitle = continueTitle
        self.canContinue = canContinue
        self.primaryID = primaryID
        self.onContinue = onContinue
        self.content = content()
    }

    var body: some View {
        SetupAssistantPage(tile: tile, title: title, message: message) {
            VStack(alignment: .leading, spacing: Space.l) {
                if let caption {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                content
            }
        } footer: {
            SetupAssistantFooter(primaryTitle: continueTitle, primaryEnabled: canContinue,
                                 primaryID: primaryID, primary: onContinue)
        }
    }
}

/// A nil Accessibility state omits that row when only Sentient's screen context is required.
/// These grants always belong to Sentient itself, independently of the computer-use helper.
/// Emits one Section, so it belongs inside a Form (GateForm in the gates, PaneForm in Health).
struct SentientAppPermissionRows: View {
    var accessibility: Bool?
    let screen: Bool
    var accessibilityTitle = "Accessibility"
    var accessibilityTip = "Lets Sentient read windows and act inside your apps in the background."
    /// Section footer (Double Tap's closing sentence).
    var footer: String? = nil

    var body: some View {
        Section {
            if let accessibility {
                GatePermissionRow(accessibilityTitle, tile: .accessibility,
                                  detail: accessibility ? "Granted" : "Not granted",
                                  tone: accessibility ? .ok : .error,
                                  info: accessibilityTip,
                                  fixTitle: "Allow…",
                                  fix: accessibility ? nil : {
                    PermissionGuide.shared.guide(.accessibility, dragging: Bundle.main.bundleURL)
                })
            }
            GatePermissionRow("Screen Recording", tile: .screenRecording,
                              detail: screen ? "Granted" : "Not granted",
                              tone: screen ? .ok : .error,
                              info: PrivacyCopy.screenCapture,
                              fixTitle: "Allow…",
                              fix: screen ? nil : {
                // Sentient may not be in Tahoe's list yet. The guide carries its app bundle.
                PermissionGuide.shared.guide(.screenRecording, dragging: Bundle.main.bundleURL)
            })
        } header: {
            Text("Sentient Permissions")
        } footer: {
            if let footer {
                Text(footer)
            }
        }
    }
}
