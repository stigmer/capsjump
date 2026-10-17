// A site's own icon in the config window, as Chrome saved it for the account the site
// jumps into, read off the main thread and kept for as long as the window is open; opening
// the window again asks afresh, so an icon Chrome has learned since shows then. Until it is
// read, or when Chrome has none, the globe. The image crosses from the reading thread as
// bytes and becomes an image on the main one. Why an icon is missing is never shown; the
// first reason in each opening of the window is logged, without the page.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import OSLog
import SwiftUI

/// What a site's icon is read by: the Chrome profile folder and what to ask in it.
struct SiteIconKey: Hashable, Sendable {
    let profile: String
    let lookup: SiteIcon.Lookup
}

@MainActor
enum SiteIcons {
    /// Each icon read, nil when Chrome has none.
    private static var cache: [SiteIconKey: NSImage?] = [:]
    private static var logged = false
    private static let logger = Logger(subsystem: Identity.bundleID, category: "editor")

    /// Forgets every icon read, for the window opened again.
    static func forget() {
        cache = [:]
        logged = false
    }

    static func cached(_ key: SiteIconKey) -> NSImage?? {
        cache[key]
    }

    static func icon(_ key: SiteIconKey) async -> NSImage? {
        if let known = cache[key] { return known }
        let file = ChromeFavicons.file(profile: key.profile)
        let lookup = key.lookup
        let result = await Task.detached(priority: .userInitiated) { ChromeFavicons.icon(for: lookup, in: file) }.value
        var icon: NSImage?
        switch result {
        case let .success(data):
            icon = NSImage(data: data)
            if icon == nil { note(.notAnImage) }
        case let .failure(missing):
            note(missing)
        }
        cache[key] = icon
        return icon
    }

    private static func note(_ missing: ChromeFavicons.Missing) {
        guard !logged else { return }
        logged = true
        logger.info("a site has no icon: \(missing.description, privacy: .public)")
    }
}

/// A site's icon at 16 points in a 20-point slot, or the globe.
struct SiteIconView: View {
    let key: SiteIconKey?
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
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
