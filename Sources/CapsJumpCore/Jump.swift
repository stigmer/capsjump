// What one jump does, decided from what Chrome and Accessibility report: focus a tab that
// already shows the site, or open the site in its profile. The live side gathers the
// facts and carries out the decision; every rule is here.

import Foundation

public struct WindowTabs: Sendable, Equatable {
    public let windowID: String
    /// Every tab's URL, in tab order.
    public let urls: [String]
    /// The active tab, counted from 1 as Chrome counts.
    public let activeIndex: Int

    public init(windowID: String, urls: [String], activeIndex: Int) {
        self.windowID = windowID
        self.urls = urls
        self.activeIndex = activeIndex
    }
}

public enum Action: Sendable, Equatable {
    /// Activate tab `tabIndex` (from 1) of Chrome window `windowID`, whose Accessibility
    /// title is `titles[titleIndex]`.
    case focus(windowID: String, tabIndex: Int, titleIndex: Int)
    /// Open `url` in the profile folder `profileDirectory`.
    case open(profileDirectory: String, url: URL, reason: OpenReason)
}

public enum OpenReason: String, Sendable, Equatable {
    case chromeNotRunning = "Chrome is not running"
    case sharedLabel = "another profile's windows carry the same label"
    case noMatchingTab = "no open tab matches"
}

public enum Jump {
    /// The tab to bring forward: for each prefix in turn, the first window (front to back)
    /// whose active tab matches, else whose any tab matches.
    public static func chooseTab(prefixes: [String], windows: [WindowTabs]) -> (windowID: String, tabIndex: Int)? {
        for prefix in prefixes {
            for window in windows {
                if window.urls.indices.contains(window.activeIndex - 1),
                   URLPrefix.matches(window.urls[window.activeIndex - 1], prefix: prefix) {
                    return (window.windowID, window.activeIndex)
                }
                if let i = window.urls.firstIndex(where: { URLPrefix.matches($0, prefix: prefix) }) {
                    return (window.windowID, i + 1)
                }
            }
        }
        return nil
    }

    /// Decides the jump. `tabs` reads one window's tabs and is called only for the target
    /// profile's paired windows; an error from it (a refused permission) is thrown, never
    /// turned into opening a duplicate tab.
    public static func decide<E: Error>(
        target: Target,
        chromeRunning: Bool,
        windows: [ChromeWindow],
        titles: [String],
        tabs: (String) throws(E) -> WindowTabs
    ) throws(E) -> Action {
        let open = { (reason: OpenReason) in
            Action.open(profileDirectory: target.profile.directory, url: target.site.open, reason: reason)
        }
        guard chromeRunning else { return open(.chromeNotRunning) }
        guard target.canFocus else { return open(.sharedLabel) }

        let pairing = WindowPairing.pair(chrome: windows, titles: titles)
        let ours = WindowPairing.windows(labelled: target.label, chrome: windows, titles: titles, pairing: pairing)
        var read: [WindowTabs] = []
        for (window, _) in ours {
            read.append(try tabs(window.id))
        }
        guard let choice = chooseTab(prefixes: target.site.match, windows: read),
              let title = ours.first(where: { $0.window.id == choice.windowID })?.title
        else { return open(.noMatchingTab) }
        return .focus(windowID: choice.windowID, tabIndex: choice.tabIndex, titleIndex: title)
    }
}
