// The window's wording for each problem a form can produce, with every message made by the
// rules themselves, so a rule that changes its words shows up here rather than as a file
// message in a form.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct FormWordingTests {
    private func wording(_ sites: [SiteSource] = [], _ keys: [KeySource] = []) -> [String] {
        guard case let .failure(error) = ConfigRules.validate(ConfigSource(sites: sites, keys: keys)) else { return [] }
        return error.found.map { FormWording.text($0.message) }
    }

    @Test func sitesProblemsReadAsTheFormsFields() {
        #expect(wording([SiteSource(index: 0, name: nil, account: "a", open: nil)]) == [
            "Give it a name.",
            "Give the page it opens.",
        ])
        #expect(wording([SiteSource(index: 0, name: "a", open: "ftp://x")]) == [
            "Pick the account this site opens in.",
            "The page must start with http:// or https://, not “ftp://x”.",
        ])
        #expect(wording([SiteSource(index: 0, name: "a", account: "a", open: "https://x.com", match: ["https://x.com/a"])]) == [
            "Leave out the scheme: write “x.com/a”, not “https://x.com/a”.",
        ])
        #expect(wording([
            SiteSource(index: 0, name: "a", account: "a", open: "https://x.com"),
            SiteSource(index: 1, name: "a", account: "a", open: "https://y.com"),
        ]) == ["Another site is already called “a”."])
        #expect(wording([SiteSource(index: 0, name: "Big", account: "a", open: "https://x.com")]) == [
            "name “Big” may use only lower-case letters, digits and inner hyphens",
        ])
    }

    @Test func keysProblemsReadAsTheFormsPickers() {
        #expect(wording([], [
            KeySource(index: 0, key: "a", action: nil),
            KeySource(index: 1, key: "b", action: ActionSource(.app, "")),
            KeySource(index: 2, key: "c", action: ActionSource(.site, "")),
            KeySource(index: 3, key: "d", action: ActionSource(.site, "gone")),
            KeySource(index: 4, key: "e", action: ActionSource(.url, "")),
            KeySource(index: 5, key: "f", action: ActionSource(.url, "example.com")),
            KeySource(index: 6, key: "g", action: ActionSource(.app, "Applications/X.app")),
        ]) == [
            "Pick what it does.",
            "Pick an app.",
            "Pick a site, or give the one it jumps to a name.",
            "No site is called “gone”.",
            "Give the link.",
            "The link needs a scheme, such as https:// or slack://, not “example.com”.",
            "“app” must be an app's name, such as “Safari”, or a path to an .app that starts with “/” or “~/”, not “Applications/X.app”",
        ])
    }
}
