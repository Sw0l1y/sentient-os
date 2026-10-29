//
// ConnectorLogo.swift
// Shared brand artwork for source pills and connection sheets. Apple's own apps (Mail, Calendar,
// Notes, Messages) show their real, installed icon, falling back to the exported artwork when the
// app is missing. Third-party marks keep their original colors and alpha; Granola's square artwork
// uses a continuous squircle mask at every size.
// Doc: Documentation - Views - Home, Processing & Shared UI.md
//

import SwiftUI
import AppKit

struct ConnectorLogo: View {
    let asset: String
    var size: CGFloat = 34

    /// The installed Apple app an asset stands for, or nil for third-party marks.
    static func appleAppBundleID(for asset: String) -> String? {
        switch asset {
        case "AppleMailMark": "com.apple.mail"
        case "AppleCalendarMark": "com.apple.iCal"
        case "AppleNotesMark": "com.apple.Notes"
        case "IMessageMark": "com.apple.MobileSMS"
        default: nil
        }
    }

    /// Match visible weight inside a fixed layout slot. Exported Mac app icons have
    /// about 19% transparent padding; the solid square marks need a little breathing room.
    private var artworkScale: CGFloat {
        switch asset {
        case "WhatsAppMark", "IMessageMark", "AppleNotesMark", "AppleMailMark", "AppleCalendarMark", "SiYuanMark": 1.11
        case "GoogleCalendarMark", "GranolaMark": 0.9
        case "OutlookMark": 0.95
        default: 1
        }
    }

    var body: some View {
        if let id = Self.appleAppBundleID(for: asset), AppIconCache.image(bundleID: id) != nil {
            AppIconImage(bundleID: id, size: size * 1.11)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            assetImage
        }
    }

    private var assetImage: some View {
        Image(asset)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size * artworkScale, height: size * artworkScale)
            .clipShape(RoundedRectangle(cornerRadius: asset == "GranolaMark" ? size * artworkScale * 0.23 : 0,
                                        style: .continuous))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Connection logos") {
    VStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            HStack(alignment: .top, spacing: 28) {
                ForEach(["GmailMark", "GoogleCalendarMark", "GoogleDriveMark", "SlackMark",
                         "OutlookMark", "NotionMark", "GranolaMark", "WhatsAppMark", "IMessageMark",
                         "AppleNotesMark", "AppleMailMark", "AppleCalendarMark", "SiYuanMark"], id: \.self) { asset in
                    VStack(spacing: 16) {
                        ConnectorLogo(asset: asset)
                        Text(asset.replacingOccurrences(of: "Mark", with: ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 72)
                }
            }
            .padding(36)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
}
