// URL prefixes are compared without their scheme or a leading `www.`, so
// `github.com/` matches `https://github.com/…` and `https://www.github.com/…` alike.

import Foundation

public enum URLPrefix {
    /// The URL without `https://`, `http://` and a following `www.`.
    public static func bare(_ url: String) -> String {
        var s = Substring(url)
        for prefix in ["https://", "http://", "www."] where s.hasPrefix(prefix) && s.count > prefix.count {
            s = s.dropFirst(prefix.count)
        }
        return String(s)
    }

    /// The prefix a site matches when it names none: the open URL's host, e.g. `claude.ai/`.
    public static func defaultMatch(for open: URL) -> String {
        bare("\(open.scheme ?? "https")://\(open.host ?? "")") + "/"
    }

    public static func matches(_ url: String, prefix: String) -> Bool {
        bare(url).hasPrefix(prefix)
    }
}
