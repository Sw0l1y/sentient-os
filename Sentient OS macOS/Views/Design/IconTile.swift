//
//  IconTile.swift
//  Sentient OS macOS
//
//  System Settings' row icons: a white SF Symbol on a colored continuous rounded square (IconTile),
//  a brand logo or real app icon on a white one (LogoTile), and the row label that pairs a tile
//  with a title and an optional one-line state subtitle (TileLabel). SPEC-00 3.4.
//

import SwiftUI
import AppKit

/// A white SF Symbol centered on a rounded square filled with the tile color's gradient.
/// Decorative: hidden from accessibility (the row's title says what it is).
struct IconTile: View {
    private let spec: TileSpec
    private let size: CGFloat

    init(_ spec: TileSpec, size: CGFloat = 20) {
        self.spec = spec
        self.size = size
    }

    init(symbol: String, color: TileColor, size: CGFloat = 20) {
        self.init(TileSpec(symbol, color), size: size)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.tile(size), style: .continuous)
            .fill(spec.color.color.gradient)
            .overlay {
                Image(systemName: spec.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: size * 0.6, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A brand logo or real app icon on a white continuous rounded square with a separator hairline.
/// White here is the logo's paper (SPEC-00 1.10 allows it).
struct LogoTile<Logo: View>: View {
    private let size: CGFloat
    private let logo: Logo
    @Environment(\.pixelLength) private var pixelLength

    init(size: CGFloat = 20, @ViewBuilder logo: () -> Logo) {
        self.size = size
        self.logo = logo()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile(size), style: .continuous)
        shape
            .fill(.white)
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: pixelLength))
            .overlay { logo.padding(size * 0.15) }
            .frame(width: size, height: size)
    }
}

/// The System Settings row label: tile, title, optional one-line subtitle. The subtitle is for
/// state or data only ("Connected · 3 accounts", "Granted"), never explanatory prose.
/// One accessibility element, read as "title, subtitle".
struct TileLabel<Icon: View>: View {
    private let title: String
    private let subtitle: String?
    private let icon: Icon

    init(_ title: String, subtitle: String? = nil, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
    }
}

extension TileLabel where Icon == IconTile {
    init(_ title: String, subtitle: String? = nil, tile: TileSpec, size: CGFloat = 20) {
        self.init(title, subtitle: subtitle) { IconTile(tile, size: size) }
    }
}

#Preview("Icon tiles") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    IconTile(.fullDiskAccess)
                    IconTile(.screenRecording, size: 30)
                    IconTile(.overnight, size: 40)
                    IconTile(.setupChooseAI, size: 64)
                }
                LogoTile(size: 30) { Image(systemName: "envelope").resizable().scaledToFit() }
                TileLabel("Full Disk Access", subtitle: "Granted", tile: .fullDiskAccess)
                TileLabel("Overnight Analysis", tile: .overnight)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 560)
}
