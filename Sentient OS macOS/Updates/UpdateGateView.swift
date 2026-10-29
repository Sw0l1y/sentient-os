//
//  UpdateGateView.swift
//  Sentient OS macOS
//
//  The update surfaces. Two faces, chosen by UpdateModel.surface:
//   • gate — a required-update takeover, like Setup Assistant's "Software Update Required": the
//     window background covers the app, with the brand mark, a title, one sentence, a system
//     progress bar and a standard button pair. One action: Update (plus Quit, so a modal never
//     traps the user). No "skip" / "remind me".
//   • info — an alert-sized sheet for a user-initiated check: "Checking for Updates…",
//     "You’re Up to Date", or "Couldn’t Check for Updates". Never shown for a silent background
//     check. When a check finds an update, the surface turns .gate and the sheet closes itself.
//  RootView hosts this view as one overlay above every page, so the gate covers Home, Settings and
//  Knowledge alike, and the info sheet attaches to the main window. Draws nothing when
//  surface == .none. Follows the system appearance.
//

import SwiftUI
import AppKit

struct UpdateGateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    private var model: UpdateModel { appState.update.model }

    private var reduceMotion: Bool { motionOverride ?? systemReduceMotion }

    var body: some View {
        ZStack {
            if model.surface == .gate {
                gate.transition(.opacity)
            } else {
                Color.clear.allowsHitTesting(false)
            }
        }
        .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: model.surface)
        .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: model.phase)
        .sheet(isPresented: infoBinding) {
            infoSheet
                .interactiveDismissDisabled(!canDismissInfo)
        }
        .onChange(of: model.surface) { _, surface in
            // A gate or info surface just appeared — bring Sentient forward so it's seen even if it
            // was in the background or the user triggered the check from Settings.
            if surface != .none { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
    }

    private var infoBinding: Binding<Bool> {
        Binding(get: { model.surface == .info },
                set: { if !$0 && model.surface == .info { model.dismissInfo() } })
    }

    // MARK: - The required-update takeover

    private var gate: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            VStack(spacing: Space.l) {
                BrandMarkView(size: 64)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sentient")
                    .accessibilityAddTraits(.isImage)
                VStack(spacing: Space.s) {
                    Text("Software Update")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(gateTitle)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(gateBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                gateStatus
                    .padding(.top, Space.s)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, Space.xl)
        }
        .safeAreaInset(edge: .bottom) {
            Label(PrivacyCopy.trustRibbon, systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Progress and actions, per phase.
    @ViewBuilder private var gateStatus: some View {
        switch model.phase {
        case .found(let version):
            VStack(spacing: Space.m) {
                Text("Required to keep going · Version \(version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: Space.m) {
                    quitButton
                    Button("Update Now") {
                        MainNavigation.shared.confirmLeavingKnowledge { approved in
                            if approved { model.installNow() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }

        case .downloading(let fraction):
            progressBlock(fraction: fraction, label: downloadLabel(fraction), quittable: true)

        case .extracting(let fraction):
            progressBlock(fraction: fraction, label: "Preparing Update…", quittable: true)

        case .installing:
            progressBlock(fraction: nil, label: "Installing. Sentient will restart.", quittable: false)

        case .failed(let message, _):
            VStack(spacing: Space.m) {
                StatusLabel(message, tone: .warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.m) {
                    quitButton
                    Button("Try Again") {
                        model.dismissInfo()                 // acknowledge the error, reset
                        appState.update.checkForUpdatesNow(from: model.checkOrigin)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }

        default:
            EmptyView()
        }
    }

    /// A linear system progress bar (indeterminate when `fraction` is nil), its caption, and Quit.
    private func progressBlock(fraction: Double?, label: String, quittable: Bool) -> some View {
        VStack(spacing: Space.m) {
            Group {
                if let fraction {
                    ProgressView(value: max(0, min(1, fraction)))
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .frame(width: 280)
            .accessibilityLabel(label)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if quittable {
                quitButton
            }
        }
    }

    private var quitButton: some View {
        Button("Quit Sentient") { model.quit() }
            .buttonStyle(.bordered)
    }

    // MARK: - The alert-sized sheet (user-initiated check)

    private var infoSheet: some View {
        VStack(spacing: Space.m) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                if model.phase == .upToDate {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.multicolor)
                        .accessibilityHidden(true)
                }
            }

            switch model.phase {
            case .checking:
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Checking for Updates…").font(.headline)
                }
                infoButton("Cancel", prominent: false)

            case .upToDate:
                Text("You’re Up to Date").font(.headline)
                Text("Sentient is on version \(UpdateController.currentVersionString).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                infoButton("OK", prominent: true)

            case .failed(let message, _):
                Text("Couldn’t Check for Updates").font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                infoButton("OK", prominent: true)

            default:
                EmptyView()
            }
        }
        .frame(width: 300)
        .padding(20)
        .presentationSizing(.fitted)
    }

    @ViewBuilder private func infoButton(_ title: String, prominent: Bool) -> some View {
        let button = Button { model.dismissInfo() } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .padding(.top, Space.xs)
        if prominent {
            button.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        } else {
            button.buttonStyle(.bordered).keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Copy & state helpers

    private var canDismissInfo: Bool {
        switch model.phase {
        case .upToDate, .failed: return true
        default: return false     // the "Checking…" sheet closes only through Cancel
        }
    }

    private var gateTitle: String {
        switch model.phase {
        case .found:        return "A New Sentient Is Ready"
        case .downloading:  return "Updating Sentient…"
        case .extracting:   return "Almost There…"
        case .installing:   return "Installing…"
        case .failed:       return "Update Didn’t Finish"
        default:            return ""
        }
    }

    private var gateBody: String {
        switch model.phase {
        case .found:
            return "To keep doing things for you safely, Sentient always runs the latest version. This one’s quick; one tap and you’re set."
        case .downloading, .extracting:
            return "Hang tight while Sentient updates itself."
        case .installing:
            return "Sentient is installing the update and will reopen in a moment."
        case .failed:
            return "Something interrupted the update. Let’s try that again."
        default:
            return ""
        }
    }

    private func downloadLabel(_ fraction: Double?) -> String {
        guard let fraction else { return "Downloading Update…" }
        return "Downloading… \(Int(fraction * 100))%"
    }
}
