//
//  FileThumbnail.swift
//  Sentient OS macOS
//
//  Shared file preview: a real QuickLook thumbnail (PDF page / image / doc preview), falling
//  back to the workspace file-type icon, then to a quiet document glyph. A leaf view with no
//  fixed colors: a quaternary fill and a separator hairline, so it reads in light and dark.
//  Used by the Analysis page's "Just Processed" section (ProcessingView). SPEC-D1 S14.
//

import SwiftUI
import AppKit
import QuickLookThumbnailing

struct FileThumbnail: View {
    let path: String?
    let size: CGFloat
    var cornerRadius: CGFloat?

    @State private var image: NSImage?

    private var radius: CGFloat { cornerRadius ?? Radius.thumbnail }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else if let path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable().aspectRatio(contentMode: .fit).padding(size * 0.16)
            } else {
                Image(systemName: "doc")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.3)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityHidden(true)
        .task(id: path) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        image = nil
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size * 2, height: size * 2),
            scale: scale, representationTypes: .thumbnail
        )
        let nsImage: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep?.nsImage)
            }
        }
        if let nsImage { image = nsImage }
    }
}

#Preview("Thumbnails") {
    HStack(spacing: Space.l) {
        FileThumbnail(path: nil, size: 48)
        FileThumbnail(path: "/Applications", size: 48)
    }
    .padding()
}
