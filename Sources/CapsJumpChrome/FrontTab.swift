// The tab in front of Chrome, read the way a jump reads Chrome: the front window's id and
// active tab from Apple Events, every window's whole title from Accessibility, and the two
// paired by title, so the front window's title (which ends in its profile's label) is
// known. Read before any CapsJump window opens, while Chrome's window order is the user's.

import AppKit
import CapsJumpCore

public struct FrontTab: Sendable, Equatable {
    public let url: String
    /// The front window's whole title, or nil when it couldn't be paired with one.
    public let title: String?

    public init(url: String, title: String?) {
        self.url = url
        self.title = title
    }
}

@MainActor
public enum FrontTabReader {
    /// The active tab of Chrome's front window; nil when Chrome isn't running or shows no window.
    public static func read() throws(ChromeError) -> FrontTab? {
        guard let chrome = ChromeLauncher.runningChrome else { return nil }
        let axWindows = try ChromeAccessibility.windows(of: chrome)
        let scripting = try ChromeScripting()
        let windows = try scripting.windows()
        guard let front = windows.first else { return nil }
        let tabs = try scripting.tabs(windowID: front.id)
        guard tabs.urls.indices.contains(tabs.activeIndex - 1) else { return nil }
        let titles = axWindows.map(\.title)
        let title = WindowPairing.pair(chrome: windows, titles: titles)[front.id].map { titles[$0] }
        return FrontTab(url: tabs.urls[tabs.activeIndex - 1], title: title)
    }
}
