// PrivacyPolicyView.swift
// The privacy policy as a document sheet (`.presentationSizing(.page)`), shared by Settings ›
// General and onboarding. PrivacyCopy owns the wording. The text scrolls in a reading column in
// system text styles; Done stays pinned below a divider. It follows the system appearance.
// Doc: Documentation - Settings.md

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Privacy Policy")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(PrivacyCopy.headline)
                        .font(.title3)
                    Text(PrivacyCopy.summary)
                    Text(PrivacyCopy.intro)
                    ForEach(PrivacyCopy.sections) { section in
                        VStack(alignment: .leading, spacing: Space.s) {
                            Text(section.title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.paragraphs, id: \.self) { paragraph in
                                Text(paragraph)
                            }
                        }
                    }
                    Link("OpenAI API Data Controls",
                         destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                }
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.xxl)
                .centeredColumn(maxWidth: PageMetrics.readingColumn)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.l)
        }
        .presentationSizing(.page)
    }
}

#Preview("Privacy Policy") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            PrivacyPolicyView()
                .frame(width: 640, height: 640)
                .environment(\.colorScheme, scheme)
        }
    }
}
