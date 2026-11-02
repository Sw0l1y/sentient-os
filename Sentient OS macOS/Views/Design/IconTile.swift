//
//  IconTile.swift
//  Sentient OS macOS
//
//  The app's one icon family (NAV-SPEC 5): an SF Symbol drawn alone, monochrome, centred in a fixed
//  square frame (IconTile); a brand logo or real app icon on a white rounded square (LogoTile); and
//  the row label that pairs an icon with a title and an optional one-line state subtitle (TileLabel).
//  There are no colored rounded squares: color is left to status glyphs (StatusTone), a notice's
//  leading glyph (`IconTile.tinted()`), brand logos and real app icons.
//

import SwiftUI
import AppKit

/// An SF Symbol alone, in a fixed `size` × `size` frame: monochrome, `.secondary`, `.regular`
/// weight, at one point size per frame size (`IconTile.pointSize(for:frame:)`), so every row's icon
/// has the same optical size and the titles beside them line up. The symbol scales with the frame
/// (a 64 pt Setup Assistant hero gets a 64 pt-frame symbol). Decorative: hidden from accessibility
/// (the row's title says what it is).
struct IconTile: View {
    private let spec: TileSpec
    private let size: CGFloat
    private var tint: Color?

    init(_ spec: TileSpec, size: CGFloat = 20) {
        self.spec = spec
        self.size = size
    }

    init(symbol: String, color: TileColor, size: CGFloat = 20) {
        self.init(TileSpec(symbol, color), size: size)
    }

    /// The same glyph in its TileSpec color instead of `.secondary`. Only for the places NAV-SPEC 5
    /// lets keep tone: a notice's leading glyph (NoticeBar) and status. Everything else stays monochrome.
    func tinted(_ on: Bool = true) -> IconTile {
        var copy = self
        copy.tint = on ? spec.color.color : nil
        return copy
    }

    var body: some View {
        Image(systemName: spec.symbol)
            // Monochrome, not hierarchical: on `.secondary` the hierarchical layers fade to near
            // invisible (Accessibility's ring, Speed's gauge, Sharing's waves, the bell), so the
            // family would read as uneven weights. One ink keeps every glyph the same density.
            .symbolRenderingMode(.monochrome)
            .font(.system(size: Self.pointSize(for: spec.symbol, frame: size), weight: .regular))
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    // MARK: Sizing

    /// The symbol's point size for a frame: 0.65 × the frame, so a 20 pt row icon is set at 13 pt,
    /// the same size as the row's `.body` title (SF Symbols are drawn to match text of their point
    /// size). A symbol's drawn box is about 1.1–1.4 × its point size, so 0.65 keeps ordinary glyphs
    /// inside the square; the rare glyph that would still overflow (taller than the frame, or wider
    /// than 1.2 × it) is set smaller just enough to fit.
    static func pointSize(for symbol: String, frame: CGFloat) -> CGFloat {
        let base = frame * 0.65
        guard let ratio = extentRatio(symbol) else { return base }
        let fit = min(frame / ratio.height, frame * 1.2 / ratio.width)
        return min(base, fit)
    }

    /// A symbol's drawn width and height per point of size, measured once per symbol and cached.
    private static var extents: [String: CGSize] = [:]

    private static func extentRatio(_ symbol: String) -> CGSize? {
        if let known = extents[symbol] { return known }
        let probe: CGFloat = 100
        let configuration = NSImage.SymbolConfiguration(pointSize: probe, weight: .regular)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration),
              image.size.width > 0, image.size.height > 0 else { return nil }
        let ratio = CGSize(width: image.size.width / probe, height: image.size.height / probe)
        extents[symbol] = ratio
        return ratio
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

/// The System Settings row label: icon, title, optional one-line subtitle. The subtitle is for
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
        // 8 pt, as a system Label: the icon is a bare glyph centred in its square, so the square's
        // own margin already separates it from the title.
        HStack(spacing: 8) {
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

#Preview("Icon family") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    IconTile(.fullDiskAccess)
                    IconTile(.screenRecording, size: 30)
                    IconTile(.overnight, size: 40)
                    IconTile(.setupChooseAI, size: 64)
                    IconTile(.noticeUpdateFailed, size: 30).tinted()
                }
                LogoTile(size: 30) { Image(systemName: "envelope").resizable().scaledToFit() }
                Form {
                    TileLabel("Full Disk Access", subtitle: "Granted", tile: .fullDiskAccess)
                    TileLabel("Overnight Analysis", tile: .overnight)
                    TileLabel("Conversations", tile: .conversations)
                    TileLabel("Speed & Intelligence", tile: .speed)
                }
                .formStyle(.grouped)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .environment(\.colorScheme, scheme)
        }
    }
    .frame(width: 720, height: 420)
}
