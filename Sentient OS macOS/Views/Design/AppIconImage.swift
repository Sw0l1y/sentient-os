//
//  AppIconImage.swift
//  Sentient OS macOS
//
//  A real app's icon (Mail, Calendar, Messages, Notes, Finder, a suggestion's target app) or
//  Finder's icon for a folder or file (SPEC-00 3.5). The real icon has its own shape, so it is never
//  put on a tile background. A missing app shows its fallback IconTile.
//  ChatGPTSignInSheet.swift must not use this type (test_home_codex_sign_in.py forbids NSWorkspace there).
//

import SwiftUI
import AppKit

struct AppIconImage: View {
    private enum Source {
        case bundle(String, fallback: TileSpec)
        case file(String)
    }

    private let source: Source
    private let size: CGFloat

    init(bundleID: String, size: CGFloat = 20, fallback: TileSpec = .genericApp) {
        self.source = .bundle(bundleID, fallback: fallback)
        self.size = size
    }

    /// Finder's icon for a folder or file.
    init(fileAt path: String, size: CGFloat = 20) {
        self.source = .file(path)
        self.size = size
    }

    var body: some View {
        switch source {
        case .bundle(let bundleID, let fallback):
            if let image = AppIconCache.image(bundleID: bundleID) {
                icon(image)
            } else {
                IconTile(fallback, size: size)
            }
        case .file(let path):
            icon(AppIconCache.image(forFile: path))
        }
    }

    private func icon(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Icons by bundle id or path, cached for the session. A bundle id that resolves to no installed
/// app is looked up again next time (the app may be installed meanwhile); found icons are cached.
enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    /// NSWorkspace urlForApplication + icon(forFile:); nil when no app has this bundle id.
    @MainActor static func image(bundleID: String) -> NSImage? {
        let key = "bundle:\(bundleID)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }

    @MainActor static func image(forFile path: String) -> NSImage {
        let key = "file:\(path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: key)
        return image
    }
}

#Preview("App icons") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            HStack(spacing: Space.m) {
                AppIconImage(bundleID: "com.apple.mail", size: 30)
                AppIconImage(bundleID: "com.apple.iCal", size: 30)
                AppIconImage(bundleID: "com.example.not-installed", size: 30)
                AppIconImage(fileAt: NSHomeDirectory(), size: 30)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 480)
}
