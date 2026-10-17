// A site's own icon in the config window, as Chrome saved it for the account the site
// jumps into, read off the main thread and kept for as long as the window is open; opening
// the window again asks afresh, so an icon Chrome has learned since shows then. Until it is
// read, or when Chrome has none, the globe. The image crosses from the reading thread as
// bytes, with its tone judged there, and becomes an image on the main one. An icon of one
// light tone on a light list, or one dark tone on a dark list, sits on a plate of the other
// tone, so it never vanishes. Why an icon is missing is never shown; the first reason in
// each opening of the window is logged, without the page.

import AppKit
import ImageIO
import CapsJumpChrome
import CapsJumpCore
import OSLog
import SwiftUI

/// What a site's icon is read by: the Chrome profile folder and what to ask in it.
struct SiteIconKey: Hashable, Sendable {
    let profile: String
    let lookup: SiteIcon.Lookup
}

/// A site's icon as read, and the tone it is drawn in.
struct SiteIconImage {
    let image: NSImage
    let tone: IconTone
}

@MainActor
enum SiteIcons {
    /// Each icon read, nil when Chrome has none.
    private static var cache: [SiteIconKey: SiteIconImage?] = [:]
    private static var logged = false
    private static let logger = Logger(subsystem: Identity.bundleID, category: "editor")

    /// Forgets every icon read, for the window opened again.
    static func forget() {
        cache = [:]
        logged = false
    }

    static func cached(_ key: SiteIconKey) -> SiteIconImage?? {
        cache[key]
    }

    static func icon(_ key: SiteIconKey) async -> SiteIconImage? {
        if let known = cache[key] { return known }
        let file = ChromeFavicons.file(profile: key.profile)
        let lookup = key.lookup
        let result = await Task.detached(priority: .userInitiated) { () -> Result<(Data, IconTone), ChromeFavicons.Missing> in
            ChromeFavicons.icon(for: lookup, in: file).flatMap { data in
                tone(of: data).map { .success((data, $0)) } ?? .failure(.notAnImage)
            }
        }.value
        var icon: SiteIconImage?
        switch result {
        case let .success((data, tone)):
            icon = NSImage(data: data).map { SiteIconImage(image: $0, tone: tone) }
            if icon == nil { note(.notAnImage) }
        case let .failure(missing):
            note(missing)
        }
        cache[key] = icon
        return icon
    }

    /// The PNG's tone, from its pixels drawn at 16 by 16; nil when it doesn't decode.
    nonisolated static func tone(of png: Data) -> IconTone? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        // Undo the premultiplication, which IconTone doesn't expect.
        for pixel in stride(from: 0, to: pixels.count, by: 4) where pixels[pixel + 3] > 0 {
            let alpha = Double(pixels[pixel + 3])
            for channel in 0..<3 {
                pixels[pixel + channel] = UInt8(min(255, (Double(pixels[pixel + channel]) * 255 / alpha).rounded()))
            }
        }
        return IconTone.of(rgba: pixels)
    }

    private static func note(_ missing: ChromeFavicons.Missing) {
        guard !logged else { return }
        logged = true
        logger.info("a site has no icon: \(missing.description, privacy: .public)")
    }
}

/// A site's icon at 16 points in a 20-point slot, on a plate when its tone would vanish
/// against the list, or the globe.
struct SiteIconView: View {
    let key: SiteIconKey?
    @State private var icon: SiteIconImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let icon {
                let plated = (icon.tone == .light && scheme == .light) || (icon.tone == .dark && scheme == .dark)
                Image(nsImage: icon.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: plated ? 14 : 16, height: plated ? 14 : 16)
                    .frame(width: 20, height: 20)
                    .background {
                        if plated {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(nsColor: .labelColor).opacity(0.85))
                        }
                    }
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .task(id: key) {
            guard let key else {
                icon = nil
                return
            }
            if let known = SiteIcons.cached(key) {
                icon = known
            } else {
                icon = nil
                let found = await SiteIcons.icon(key)
                // An edited page asks again; a read it overtook doesn't land.
                if !Task.isCancelled { icon = found }
            }
        }
        .accessibilityHidden(true)
    }
}
