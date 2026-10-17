// Which pages' icon stands for a site. Chrome keeps the icon of every page it has shown, per
// profile, and a site can change its icon from page to page (GitHub's follows a pull
// request's state), so the site's own `open` page is asked first. Failing that, the icon
// most pages under the site's `match` prefixes share, which on a busy site is its plain
// one. Prefixes are written without a scheme or `www.` while Chrome stores whole URLs, so
// each becomes the four ways a page under it may be stored. Pure: what to ask, not how.

import Foundation

public enum SiteIcon {
    public struct Lookup: Sendable, Equatable, Hashable {
        /// The page asked first, exactly as the site's `open` gives it.
        public let page: String
        /// Then the URL prefixes whose pages are counted, by the icon they share.
        public let prefixes: [String]

        public init(page: String, prefixes: [String]) {
            self.page = page
            self.prefixes = prefixes
        }
    }

    /// What to ask for a site that opens `open` and matches `match` (the default prefix
    /// from `open` when nil); nil when `open` isn't a web page.
    public static func lookup(open: String, match: [String]?) -> Lookup? {
        guard let url = ConfigRules.httpURL(open) else { return nil }
        let bare = (match ?? [URLPrefix.defaultMatch(for: url)]).map(URLPrefix.bare).filter { !$0.isEmpty }
        var prefixes: [String] = []
        for prefix in bare {
            for stored in urls(under: prefix) where !prefixes.contains(stored) {
                prefixes.append(stored)
            }
        }
        return Lookup(page: open, prefixes: prefixes)
    }

    /// The ways Chrome may store a page under a bare prefix.
    static func urls(under prefix: String) -> [String] {
        ["https://", "https://www.", "http://", "http://www."].map { $0 + prefix }
    }
}
