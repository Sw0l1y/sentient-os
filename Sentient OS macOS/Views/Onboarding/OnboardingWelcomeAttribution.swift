// The welcome's founder signature: a heart and two small contact boxes, each with a Copy button.
// Formats the existing optional attribution payload without embedding contact details in the app.
// Doc: Documentation - Onboarding.md

import AppKit
import SwiftUI

struct OnboardingWelcomeAttribution: View {
    let line: String

    var body: some View {
        if let contacts = WelcomeFounderContact.parse(line) {
            VStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Made with")
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("by")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Made with love by")

                HStack(spacing: 12) {
                    ForEach(contacts, id: \.name) { contact in
                        WelcomeContactButton(contact: contact)
                    }
                }
            }
        } else if line.hasPrefix("Made with love ") {
            Text("Made with \(Image(systemName: "heart.fill")) \(String(line.dropFirst("Made with love ".count)))")
                .accessibilityLabel(line)
        } else {
            Text(verbatim: line)
        }
    }
}

private struct WelcomeContactButton: View {
    let contact: WelcomeFounderContact
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride

    var body: some View {
        GroupBox {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: contact.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(verbatim: contact.phone)
                        .font(.subheadline).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(contact.phone, forType: .string)
                } label: {
                    Label("Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .animation(Motion.gated(Motion.quick, reduceMotion: motionOverride ?? systemReduced), value: copied)
                .help(copied ? "Number copied" : "Copy \(contact.name)’s number")
                .accessibilityLabel("\(contact.name), \(contact.phone)")
                .accessibilityValue(copied ? "Number copied" : "")
                .accessibilityHint("Copies the phone number")
            }
            .padding(.horizontal, Space.xs)
        }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }
}

/// The server currently sends a single sentence. Recognize its two-contact form, preserving
/// other attribution copy verbatim; only presentation changes, never the source payload.
struct WelcomeFounderContact {
    let name: String
    let phone: String

    static func parse(_ line: String) -> [Self]? {
        let pattern = #"^Made with love by (.+?) \((\+?[0-9][0-9 ()-]*[0-9])\) and (.+?) \((\+?[0-9][0-9 ()-]*[0-9])\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        let fields = (1...4).compactMap { index -> String? in
            guard let range = Range(match.range(at: index), in: line) else { return nil }
            return String(line[range])
        }
        guard fields.count == 4 else { return nil }
        return [Self(name: fields[0], phone: fields[1]), Self(name: fields[2], phone: fields[3])]
    }
}

#if DEBUG
#Preview("Founder contacts") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingWelcomeAttribution(line:
                "Made with love by Alex (+1 (202) 555-0101) and Sam (+1 (202) 555-0102)")
                .font(.callout).foregroundStyle(.secondary)
                .padding(40)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
#endif
