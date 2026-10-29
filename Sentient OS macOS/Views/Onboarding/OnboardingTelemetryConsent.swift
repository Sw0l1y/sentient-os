//
//  OnboardingTelemetryConsent.swift
//  Sentient OS macOS
//
//  Choose Your AI's privacy small print (SPEC-D6 S10), the Setup Assistant "Analytics" footnote:
//  one line, "Sentient shares crash reports and basic usage. Read More · Configure…". Read More
//  opens the Settings Privacy Policy sheet (PrivacyPolicyView, reused verbatim); Configure… opens
//  a popover with the two anonymous-telemetry switches (crash reports → Sentry · analytics →
//  TelemetryDeck) and the always-on core analytics text. The switches use the SAME @AppStorage
//  keys as Settings → General, applied live through CrashReporting/Analytics.applyEnabledChange(),
//  so the choice made here IS the Settings choice.
//

import SwiftUI
import AppKit

struct OnboardingTelemetryConsent: View {
    /// Same keys as Settings → General (SystemPane) — the original `diagnosticsEnabled` name
    /// carries existing installs' crash-reports choice; analytics has its own key.
    @AppStorage("diagnosticsEnabled") private var crashReportsEnabled = true
    @AppStorage("analyticsEnabled") private var analyticsEnabled = true

    @State private var configuring = false
    @State private var showPrivacyPolicy = false

    var body: some View {
        HStack(spacing: Space.xs) {
            Text("Sentient shares crash reports and basic usage.")
                .foregroundStyle(.secondary)
            Button("Read More") { showPrivacyPolicy = true }
                .buttonStyle(.link)
                .foregroundStyle(Color(nsColor: .linkColor))
            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Button("Configure…") { configuring = true }
                .buttonStyle(.link)
                .foregroundStyle(Color(nsColor: .linkColor))
                .popover(isPresented: $configuring, arrowEdge: .top) { configurePopover }
        }
        .font(.footnote)
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: crashReportsEnabled) { _, _ in CrashReporting.applyEnabledChange() }
        .onChange(of: analyticsEnabled) { _, _ in Analytics.applyEnabledChange() }
        .sheet(isPresented: $showPrivacyPolicy) { PrivacyPolicyView() }
    }

    /// The two switches, each with its explanation, and the core reporting that always runs.
    private var configurePopover: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label(PrivacyCopy.headline, systemImage: "hand.raised.fill")
                .font(.headline)
            VStack(alignment: .leading, spacing: Space.xs) {
                Toggle("Share crash reports", isOn: $crashReportsEnabled)
                Text(PrivacyCopy.crashReports)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Toggle("Share extended analytics", isOn: $analyticsEnabled)
                Text(PrivacyCopy.extendedAnalytics)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            // Always visible: core reporting is independent of these switches.
            Text(PrivacyCopy.coreAnalytics)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(14)
        .frame(width: PageMetrics.popover, alignment: .leading)
    }
}

#if DEBUG
#Preview("Telemetry footnote") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingTelemetryConsent()
                .padding(Space.xl)
                .frame(width: 520, height: 120)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
#endif
