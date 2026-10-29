// An explicit analysis choice. Only the overnight choice presents wake/login setup;
// neither choosing now nor opening Home asks for those optional capabilities.
// A window-attached form sheet like Time Machine's schedule choice: a radio choice, the
// requirement rows revealed for the scheduled option, and Back / Continue at the bottom right.
import SwiftUI

struct AnalysisTimingSheet: View {
    var viewportHeight: CGFloat = 620
    let onChoose: (ProcessingCoordinator.Timing) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var timing: ProcessingCoordinator.Timing = .now
    @State private var overnightReady = false
    @State private var sourcesReady = SourceSelection.selectionCount >= SourceSelection.minimumSelections
    @State private var nextOvernight = OvernightScheduler.nextOccurrence(minutesSinceMidnight: OvernightScheduler.configuredMinutes)
    private var canContinue: Bool { sourcesReady && (timing == .now || overnightReady) }

    private let nowFooter = "Progress is saved as it runs. You can close the analysis window and keep using Sentient."
    private let overnightFooter = "Keep Sentient open in your menu bar. Plug in your Mac overnight or leave at least 50% battery."

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("When Should Analysis Run?")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Group {
                            Text("Your first analysis can take over an hour to understand your sources and build your knowledge base.")
                            Text(CodexAuth.knowledgeBaseOnly
                                 ? "You can explore Sentient while it runs. Double Tap becomes available after your knowledge is ready."
                                 : "Keep using Sidekick while it runs. Personal context and Double Tap become available after your knowledge is ready.")
                        }
                        .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    radioRow(.now, "Now", "Build your knowledge in the background while you use Sentient.")
                    radioRow(.overnight, "Overnight", "Next run: \(ProcessingCoordinator.scheduleLabel(nextOvernight)).")
                } header: {
                    Text("Run Analysis")
                } footer: {
                    Text(timing == .now ? nowFooter : overnightFooter)
                }
                if timing == .overnight {
                    Section("For Overnight Analysis") {
                        OvernightSetupRequirements { overnightReady = $0 }
                    }
                }
                if !sourcesReady {
                    Section {
                        StatusLabel("Some sources are no longer available. Go back and choose three available sources.",
                                    tone: .warning)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)

            // The footer never scrolls: a sheet gets a finite viewport from its owner, so the
            // overnight requirements scroll inside the form instead of growing the window.
            HStack {
                Button("Back") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(timing == .now ? "Start Analysis" : "Schedule Analysis") {
                    guard canContinue else { return }
                    onChoose(timing)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
                .accessibilityIdentifier("analysis.timing.continue")
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.l)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 560, height: viewportHeight)
        .presentationSizing(.fitted)
        .task {
            while !Task.isCancelled {
                nextOvernight = OvernightScheduler.nextOccurrence(minutesSinceMidnight: OvernightScheduler.configuredMinutes)
                sourcesReady = SourceSelection.selectionCount >= SourceSelection.minimumSelections
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    /// A real Button (the lab asserts AXButton + enabled for both ids), drawn as a radio row.
    /// `Picker(.radioGroup)` would expose AXRadioButtons with no per-option identifiers.
    private func radioRow(_ value: ProcessingCoordinator.Timing, _ title: String, _ detail: String) -> some View {
        Button { timing = value } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: timing == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(timing == value ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("analysis.timing.\(value.rawValue)")
        .accessibilityAddTraits(timing == value ? .isSelected : [])
    }
}

#Preview {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            AnalysisTimingSheet(onChoose: { _ in })
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
