// OnboardingCompanyWelcome.swift
// A company welcome between email entry and source selection, laid out like the macOS
// "Welcome to [organization]" enrolment page: two logos, a title, a note from the founders
// and one primary. It arrives with a single gated fade.
// Doc: Documentation - Onboarding.md

import AppKit
import ImageIO
import SwiftUI

struct OnboardingCompanyWelcome: View {
    let company: YCCompanyWelcome
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var arrived = false

    private var reduceMotion: Bool { motionOverride ?? systemReduced }
    private static let logoSide: CGFloat = 72

    var body: some View {
        SetupAssistantPage(tile: nil, title: "Sentient OS × \(company.companyName)", message: company.welcomeLine) {
            VStack(spacing: Space.xl) {
                HStack(spacing: Space.xl) {
                    Image("SentientLogo")
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: Self.logoSide, height: Self.logoSide)
                        .accessibilityLabel("Sentient OS logo")

                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    companyLogo
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Sentient OS for \(company.companyName)")

                Text("From your fellow YC founders.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let attribution = company.displayAttributionLine {
                    OnboardingWelcomeAttribution(line: attribution)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        } footer: {
            SetupAssistantFooter(primaryTitle: "Let’s Get Started", primary: onContinue)
        }
        .opacity(arrived || reduceMotion ? 1 : 0)
        .offset(y: arrived || reduceMotion ? 0 : 8)
        .animation(Motion.gated(Motion.standard, reduceMotion: reduceMotion), value: arrived)
        .onAppear { arrived = true }
        .onExitCommand(perform: onContinue)
    }

    private var companyLogo: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile(Self.logoSide), style: .continuous)
        return WelcomeCompanyLogo(company: company)
            .frame(width: Self.logoSide, height: Self.logoSide)
            .background(.background.secondary, in: shape)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(company.companyName) logo")
    }
}

/// A missing or unusable logo leaves a deliberate company monogram, never an empty image.
private struct WelcomeCompanyLogo: View {
    let company: YCCompanyWelcome
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(verbatim: String(company.companyName.prefix(1)).uppercased())
                    .font(.system(.title, design: .rounded).weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 62, height: 62)
        .animation(Motion.gated(Motion.standard, reduceMotion: motionOverride ?? systemReduced), value: image != nil)
        .accessibilityHidden(true)
        .task(id: company.logoPath) {
            image = nil
            guard let data = await YCWelcomeClient.shared.logoData(for: company), !Task.isCancelled,
                  let thumbnail = await Self.thumbnail(from: data), !Task.isCancelled else { return }
            image = NSImage(cgImage: thumbnail, size: .zero)
        }
    }

    // Decode away from the UI, bounded in compressed size by the client and pixel size here.
    @concurrent private static func thumbnail(from data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              (1...4096).contains(width), (1...4096).contains(height) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 192,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }
}

#if DEBUG
extension YCCompanyWelcome {
    static let preview = YCCompanyWelcome(companyName: "Acme", welcomeLine:
        "Keep customer follow-ups moving while you build what comes next.", logoPath: nil, contentVersion: 1)
}

#Preview("Company welcome") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingCompanyWelcome(company: .preview, onContinue: {})
                .frame(width: 720, height: 620)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Long company name") {
    OnboardingCompanyWelcome(company: YCCompanyWelcome(companyName: "The Very Thoughtful Robotics Company",
        welcomeLine: "Keep supplier conversations, meeting preparation, and the next steps in view.",
        logoPath: nil, contentVersion: 1), onContinue: {})
        .frame(width: 720, height: 620)
}
#endif
