// Window pairing and the jump decision, on the window lists measured on a real Mac:
// Chrome shortens names with "…", two profiles show the same page, and a window
// Accessibility can't see must cost only its own pairing.

import Foundation
import Testing
@testable import CapsJumpCore

private func title(_ page: String, _ label: String) -> String {
    "\(page) - Google Chrome \u{2013} \(label)"
}

private let acme = "Alex (acme.dev)"
private let kim = "kim@initech.com"
private let lee = "lee@initech.com"

@Suite struct WindowPairingTests {
    @Test func namePrefixStopsAtEllipsisAndCaps() {
        #expect(WindowPairing.namePrefix("Login | 1Password \u{2014} Password M\u{2026}ams, \u{2026}") == "Login | 1Password \u{2014} ")
        #expect(WindowPairing.namePrefix("Short\u{2026}") == "Short")
        #expect(WindowPairing.namePrefix("New chat - Claude") == "New chat - Claude")
        #expect(WindowPairing.namePrefix("") == "")
    }

    @Test func pairsTheMeasuredFiveWindows() {
        let chrome = [
            ChromeWindow(id: "1", name: "1Password for Acme"),
            ChromeWindow(id: "2", name: "Inbox - alex@umbrella.co - Umbrella Mail"),
            ChromeWindow(id: "3", name: "New chat - Claude"),
            ChromeWindow(id: "4", name: "New chat - Claude"),
            ChromeWindow(id: "5", name: "Inbox - alex@globex.io - Globex Mail"),
        ]
        let titles = [
            title("1Password for Acme", acme),
            title("Inbox - alex@umbrella.co - Umbrella Mail - High memory usage - 1.0 GB", "Alex (alex@umbrella.co)"),
            title("New chat - Claude", kim),
            title("New chat - Claude", lee),
            title("Inbox - alex@globex.io - Globex Mail", "Alex (globex.io)"),
        ]
        let pairing = WindowPairing.pair(chrome: chrome, titles: titles)
        #expect(pairing == ["1": 0, "2": 1, "3": 2, "4": 3, "5": 4])
        #expect(WindowPairing.windows(labelled: lee, chrome: chrome, titles: titles, pairing: pairing).map(\.window.id) == ["4"])
    }

    @Test func shortenedNamePairsWithItsWholeTitle() {
        let chrome = [ChromeWindow(id: "7", name: "Login | 1Password \u{2014} Password M\u{2026}ams, \u{2026}")]
        let titles = [title("Login | 1Password \u{2014} Password Manager for Teams, Businesses", acme)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["7": 0])
    }

    @Test func windowMissingFromAccessibilityCostsOnlyItsGroup() {
        // Window 2 is on another Space: Accessibility lists four titles for five windows.
        let chrome = [
            ChromeWindow(id: "1", name: "GitHub"),
            ChromeWindow(id: "2", name: "Gmail"),
            ChromeWindow(id: "3", name: "New chat - Claude"),
            ChromeWindow(id: "4", name: "New chat - Claude"),
            ChromeWindow(id: "5", name: "Docs"),
        ]
        let titles = [
            title("GitHub", acme),
            title("New chat - Claude", kim),
            title("New chat - Claude", lee),
            title("Docs", acme),
        ]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["1": 0, "3": 1, "4": 2, "5": 3])
    }

    @Test func identicalWindowsWithOneMissingStayUnpaired() {
        // Two windows on the same page, one invisible: no title can say which is which.
        let chrome = [
            ChromeWindow(id: "1", name: "New chat - Claude"),
            ChromeWindow(id: "2", name: "New chat - Claude"),
            ChromeWindow(id: "3", name: "GitHub"),
        ]
        let titles = [title("New chat - Claude", lee), title("GitHub", acme)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["3": 1])
    }

    @Test func orderBreaksTiesBetweenIdenticalWindows() {
        let chrome = [ChromeWindow(id: "10", name: "New Tab"), ChromeWindow(id: "20", name: "New Tab")]
        let titles = [title("New Tab", lee), title("New Tab", kim)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["10": 0, "20": 1])
    }

    @Test func singleCompletePairingWinsWhenOrderDisagrees() {
        // "New" is compatible with both titles, "New chat - Claude" only with the first;
        // front-to-back order would pair "New" with the chat, leaving the other stranded.
        let chrome = [ChromeWindow(id: "1", name: "New"), ChromeWindow(id: "2", name: "New chat - Claude")]
        let titles = [title("New chat - Claude", kim), title("New Tab", lee)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["1": 1, "2": 0])
    }

    @Test func labelMustBeTheWholeEnding() {
        let chrome = [ChromeWindow(id: "1", name: "X")]
        let titles = [title("X", "Alex (globex.io)")]
        let pairing = WindowPairing.pair(chrome: chrome, titles: titles)
        #expect(WindowPairing.windows(labelled: "globex.io", chrome: chrome, titles: titles, pairing: pairing).isEmpty)
        #expect(WindowPairing.windows(labelled: "Alex (globex.io)", chrome: chrome, titles: titles, pairing: pairing).count == 1)
    }

    @Test func namelessWindowPairsWithNothingAndHarmsNoOne() {
        let chrome = [ChromeWindow(id: "1", name: ""), ChromeWindow(id: "2", name: "GitHub")]
        let titles = [title("Untitled", kim), title("GitHub", acme)]
        #expect(WindowPairing.pair(chrome: chrome, titles: titles) == ["2": 1])
    }

    @Test func noWindowsPairsNothing() {
        #expect(WindowPairing.pair(chrome: [], titles: []).isEmpty)
        #expect(WindowPairing.pair(chrome: [], titles: [title("X", acme)]).isEmpty)
    }
}

@Suite struct JumpTests {
    private let profile = ChromeProfile(directory: "Profile 26", name: kim, email: "", givenName: "")

    private func target(match: [String] = ["claude.ai/"], shared: Bool = false) -> Target {
        Target(
            site: Site(name: "claude-kim", account: kim, profile: nil, open: URL(string: "https://claude.ai/new")!, match: match),
            profile: profile,
            sharedLabelWith: shared ? [ChromeProfile(directory: "Profile 27", name: kim, email: "", givenName: "")] : []
        )
    }

    private let chrome = [
        ChromeWindow(id: "1", name: "GitHub"),
        ChromeWindow(id: "2", name: "New chat - Claude"),
        ChromeWindow(id: "3", name: "Docs"),
    ]
    private let titles = [
        title("GitHub", kim),
        title("New chat - Claude", lee),
        title("Docs", kim),
    ]

    private func tabs(_ table: [String: WindowTabs]) -> (String) throws(TabsError) -> WindowTabs {
        { id throws(TabsError) in
            guard let tabs = table[id] else { throw TabsError.unexpectedWindow(id) }
            return tabs
        }
    }

    enum TabsError: Error, Equatable { case unexpectedWindow(String), denied }

    @Test func activeTabWinsThenFirstMatchFrontToBack() {
        let windows = [
            WindowTabs(windowID: "1", urls: ["https://claude.ai/a", "https://claude.ai/b"], activeIndex: 2),
            WindowTabs(windowID: "3", urls: ["https://claude.ai/c"], activeIndex: 1),
        ]
        #expect(Jump.chooseTab(prefixes: ["claude.ai/"], windows: windows)! == ("1", 2))
        #expect(Jump.chooseTab(prefixes: ["claude.ai/c", "claude.ai/"], windows: windows)! == ("3", 1))
        let inactive = [WindowTabs(windowID: "1", urls: ["https://x.com", "https://www.claude.ai/z"], activeIndex: 1)]
        #expect(Jump.chooseTab(prefixes: ["claude.ai/"], windows: inactive)! == ("1", 2))
        #expect(Jump.chooseTab(prefixes: ["github.com/"], windows: windows) == nil)
        #expect(Jump.chooseTab(prefixes: ["x.com/"], windows: [WindowTabs(windowID: "9", urls: [], activeIndex: 0)]) == nil)
    }

    @Test func focusesOnlyTheProfilesWindows() throws {
        // Window 2 shows Claude but belongs to lee; it is never read.
        let action = try Jump.decide(target: target(), chromeRunning: true, windows: chrome, titles: titles, tabs: tabs([
            "1": WindowTabs(windowID: "1", urls: ["https://github.com"], activeIndex: 1),
            "3": WindowTabs(windowID: "3", urls: ["https://docs.x", "https://claude.ai/chat/1"], activeIndex: 1),
        ]))
        #expect(action == .focus(windowID: "3", tabIndex: 2, titleIndex: 2))
    }

    @Test func opensWhenNothingMatches() throws {
        let action = try Jump.decide(target: target(match: ["mail.google.com/"]), chromeRunning: true, windows: chrome, titles: titles, tabs: tabs([
            "1": WindowTabs(windowID: "1", urls: ["https://github.com"], activeIndex: 1),
            "3": WindowTabs(windowID: "3", urls: ["https://docs.x"], activeIndex: 1),
        ]))
        #expect(action == .open(profileDirectory: "Profile 26", url: URL(string: "https://claude.ai/new")!, reason: .noMatchingTab))
    }

    @Test func opensWithoutReadingWhenChromeIsClosedOrLabelShared() throws {
        let none = tabs([:])
        #expect(try Jump.decide(target: target(), chromeRunning: false, windows: chrome, titles: titles, tabs: none)
            == .open(profileDirectory: "Profile 26", url: URL(string: "https://claude.ai/new")!, reason: .chromeNotRunning))
        #expect(try Jump.decide(target: target(shared: true), chromeRunning: true, windows: chrome, titles: titles, tabs: none)
            == .open(profileDirectory: "Profile 26", url: URL(string: "https://claude.ai/new")!, reason: .sharedLabel))
    }

    @Test func readErrorIsThrownNeverOpened() {
        #expect(throws: TabsError.denied) {
            try Jump.decide(target: target(), chromeRunning: true, windows: chrome, titles: titles) { (_: String) throws(TabsError) -> WindowTabs in
                throw TabsError.denied
            }
        }
    }
}
