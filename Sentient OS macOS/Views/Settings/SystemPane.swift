//
//  SystemPane.swift
//  Sentient OS macOS
//
//  Settings › General, laid out like System Settings › General (+ Login Items, Software Update,
//  Privacy & Security › Analytics): tiled rows in named sections.
//  Startup: launch at login (LoginItem.swift), held on while its keep-Sentient-alive alert asks.
//  Overnight: the daily wake time and the wake helper row (only when overnight analysis is on).
//  Updates: the version, the conditional last-checked line, Check for Updates.
//  Privacy: the two reporting switches (crash reports → CrashReporting/Sentry · analytics →
//  Analytics/TelemetryDeck) and the Privacy Policy sheet.
//  Diagnostics: export a diagnostics file.
//  Invitations: InviteSettingsSection (WP13).
//  Reset and Uninstall: the shared FactoryReset wipe and the full System/Uninstall teardown,
//  marked destructive by role, not by color.
//

import SwiftUI
import AppKit

struct SystemPane: View {
    @Environment(AppState.self) private var appState   // for the updater (Check Now / version)

    /// Crash reports (Sentry): the original `diagnosticsEnabled` key, kept so existing installs
    /// carry their choice over. Analytics has its own key since the two toggles split.
    @AppStorage("diagnosticsEnabled") private var crashReportsEnabled = true
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true
    @AppStorage(OvernightScheduler.minutesKey) private var wakeMinutes = OvernightScheduler.defaultMinutes

    @State private var launchAtLogin = LoginItem.cachedIsEnabled
    @State private var confirmLoginOff = false
    @State private var confirmReset = false
    @State private var resetting = false
    @State private var resetError: String?
    @State private var showUninstall = false
    @State private var showPrivacyPolicy = false
    @State private var exportingDiagnostics = false
    @State private var diagnosticFile: URL?
    @State private var diagnosticError: String?
    @State private var wakeSetup = OvernightWakeSetup()

    var body: some View {
        PaneForm {
            startupSection
            overnightSection
            updatesSection
            privacySection
            diagnosticsSection
            InviteSettingsSection()
            resetSection
        }
        .pageSubtitle("Version \(UpdateController.currentVersionString)", page: .settings, pane: .system)
        .task { launchAtLogin = await LoginItem.refreshedIsEnabled() }   // live status: revocable in System Settings
        .onChange(of: launchAtLogin) { _, on in
            if on {
                if !LoginItem.enable() { launchAtLogin = false }
            } else if LoginItem.isEnabled {
                launchAtLogin = true          // hold the switch until the user confirms
                confirmLoginOff = true
            }
        }
        .onChange(of: crashReportsEnabled) { _, _ in CrashReporting.applyEnabledChange() }
        .onChange(of: analyticsEnabled) { _, _ in Analytics.applyEnabledChange() }
        .alert("Turn Off Launch at Login?", isPresented: $confirmLoginOff) {
            Button("Keep It On", role: .cancel) {}
            Button("Turn Off Anyway", role: .destructive) {
                Task {
                    await LoginItem.disable()
                    launchAtLogin = LoginItem.isEnabled
                }
            }
        } message: {
            Text("To stay helpful, your Sentient runs its on-device intelligence at your chosen overnight wake time, and that can only happen if Sentient is already running. It's heavily optimized and stays out of your RAM and CPU the rest of the time.\n\nWe recommend leaving this on to keep your Sentient alive.")
        }
        .alert("Erase Everything Sentient Has Learned?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Knowledge", role: .destructive) {
                resetting = true
                Task {
                    resetError = nil
                    let completed = await FactoryReset.run(appState: appState)
                    resetting = false
                    if completed { HomeWindowOpening.open() }
                    else { resetError = "Reset couldn’t clear saved app connections. Unlock your Mac and try again." }
                }
            }
        } message: {
            Text(PrivacyCopy.resetConfirmation)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView().environment(\.settingsFormStyle, false)
        }
        .sheet(isPresented: $showUninstall) {
            UninstallView().environment(\.settingsFormStyle, false)
        }
    }

    // MARK: - Startup

    private var startupSection: some View {
        Section {
            Toggle(isOn: $launchAtLogin) {
                TileLabel("Launch at Login", tile: .launchAtLogin)
            }
            .toggleStyle(.switch)
        } header: {
            Text("Startup")
        } footer: {
            Text("How Sentient lives on this Mac. Keep Sentient ready in your menu bar.")
        }
    }

    // MARK: - Overnight

    private var overnightSection: some View {
        Section {
            DatePicker(selection: wakeTime, displayedComponents: .hourAndMinute) {
                TileLabel("Overnight Wake Time", tile: .overnight)
            }
            .datePickerStyle(.field)
            .accessibilityIdentifier("settings.overnightWakeTime")
            // Same rule as Permissions & Health: no red "Not set up" for a feature not asked for.
            if HealthCaution.overnightRequested() {
                OvernightWakeRow(setup: wakeSetup)
            } else {
                StatusRow("Overnight Wake", tile: .overnight,
                          detail: "Overnight analysis is off. Wake setup is optional.", tone: .off)
            }
            DisclosureGroup("When Does Overnight Intelligence Run?") {
                Text(PrivacyCopy.overnight)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Overnight")
        } footer: {
            Text("Start overnight intelligence daily at this time, in your Mac’s local time zone.")
        }
    }

    private var wakeTime: Binding<Date> {
        Binding(get: {
            let minutes = OvernightScheduler.validatedMinutes(wakeMinutes)
            // A fixed date keeps the time-only editor independent of today's DST transition.
            return Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 15,
                hour: minutes / 60, minute: minutes % 60)) ?? Date()
        }, set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            let minutes = (components.hour ?? 3) * 60 + (components.minute ?? 0)
            guard minutes != wakeMinutes else { return }
            wakeMinutes = minutes
            appState.scheduler.commit()
        })
    }

    // MARK: - Updates (Sparkle: the story is "we keep you current", not a dial)

    private var updatesSection: some View {
        Section {
            LabeledContent {
                Button("Check for Updates") {
                    appState.update.checkForUpdatesNow(from: .settings)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!UpdateController.appUpdatesEnabled)
            } label: {
                TileLabel("Version \(UpdateController.currentVersionString)",
                          subtitle: appState.update.lastCheckDate.map {
                              "Last checked \($0.formatted(date: .abbreviated, time: .shortened))"
                          },
                          tile: .updates)
            }
        } header: {
            Text("Updates")
        } footer: {
            if !UpdateController.appUpdatesEnabled {
                Text("Updates are turned off in this development build.")
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Toggle(isOn: $crashReportsEnabled) {
                HStack(spacing: Space.s) {
                    Text("Share Crash Reports")
                    InfoPopoverButton(PrivacyCopy.crashReports)
                }
            }
            .toggleStyle(.switch)
            Toggle(isOn: $analyticsEnabled) {
                HStack(spacing: Space.s) {
                    Text("Share Extended Usage Analytics")
                    InfoPopoverButton(PrivacyCopy.extendedAnalytics)
                }
            }
            .toggleStyle(.switch)
            LabeledContent {
                Button("Privacy Policy…") { showPrivacyPolicy = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } label: {
                TileLabel("Your Data", tile: .privacy)
            }
        } header: {
            Text("Privacy")
        } footer: {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(PrivacyCopy.headline)
                Text(PrivacyCopy.coreAnalytics)
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section {
            LabeledContent {
                Button(exportingDiagnostics ? "Preparing…" : "Export…", action: exportDiagnostics)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(exportingDiagnostics)
                    .accessibilityLabel("Export diagnostic file")
            } label: {
                TileLabel("Export Diagnostic File", tile: .diagnostics)
            }
            if let diagnosticFile {
                LabeledContent {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([diagnosticFile])
                    }
                    .buttonStyle(.link)
                } label: {
                    StatusLabel("Saved. Review the file before sharing.", tone: .ok)
                }
            }
            if let diagnosticError {
                StatusLabel(diagnosticError, tone: .error)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Send this diagnostics file to the developers to help fix any bugs you’re facing. \(DiagnosticExport.disclosure) \(DiagnosticExport.sharingNote)")
        }
    }

    private func exportDiagnostics() {
        exportingDiagnostics = true
        diagnosticError = nil
        diagnosticFile = nil
        Task {
            defer { exportingDiagnostics = false }
            do { diagnosticFile = try await DiagnosticExport.save(appState: appState) }
            catch {
                diagnosticError = DiskSpace.isDiskFull(error)
                    ? "Your disk is full. Free up space and try exporting again."
                    : "The diagnostics file couldn't be saved. Try another location."
                Log("Diagnostics export: save failed (\(ErrorLabel(error)))")
            }
        }
    }

    // MARK: - Reset and Uninstall

    // Running analysis is cancellable. Only another teardown blocks these actions.
    private var maintenanceInProgress: Bool {
        resetting || appState.processing.isSuspended || appState.isUninstalling
    }

    private var resetTitle: String {
        guard resetting else { return "Reset Sentient…" }
        return appState.processing.isBusy || appState.commandCoordinator.run.isRunning
            ? "Stopping…" : "Erasing…"
    }

    private var resetSection: some View {
        Section {
            LabeledContent {
                Button(resetTitle, role: .destructive) { confirmReset = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(maintenanceInProgress)
            } label: {
                TileLabel("Reset Sentient", tile: .reset)
            }
            DisclosureGroup("What Gets Removed?") {
                Text(PrivacyCopy.reset)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if appState.processing.isBusy {
                StatusLabel(resetting ? "Stopping analysis safely before erasing your knowledge."
                            : "Reset will stop analysis before erasing your knowledge.",
                            tone: .working)
            }
            if let resetError {
                StatusLabel(resetError, tone: .error)
            }
            LabeledContent {
                Button("Uninstall…", role: .destructive) { showUninstall = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(maintenanceInProgress)
            } label: {
                TileLabel("Uninstall Sentient", tile: .uninstall)
            }
            DisclosureGroup("What Gets Removed?") {
                Text(PrivacyCopy.uninstall)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if appState.processing.isBusy {
                StatusLabel("Uninstall will stop analysis before removing Sentient’s data.", tone: .working)
            }
        } header: {
            Text("Reset and Uninstall")
        } footer: {
            Text("Remove your knowledge or uninstall Sentient. Reset erases learned knowledge and returns to setup. Uninstall removes Sentient and its local data from this Mac.")
        }
    }
}

#Preview("General pane") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            SystemPane()
                .environment(AppState())
                .frame(width: 720, height: 760)
                .environment(\.colorScheme, scheme)
        }
    }
}
