// Which pages stand for a site's icon: its own open page first, then every page under its
// match prefixes, each prefix in the four ways Chrome may have stored a page under it.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct SiteIconTests {
    @Test func theOpenPageIsAskedAsWritten() {
        let lookup = SiteIcon.lookup(open: "https://mail.google.com/mail/u/0/#inbox", match: nil)
        #expect(lookup?.page == "https://mail.google.com/mail/u/0/#inbox")
    }

    @Test func withoutAMatchTheHostIsThePrefix() {
        let lookup = SiteIcon.lookup(open: "https://www.github.com/stigmer/stigmer/pulls", match: nil)
        #expect(lookup?.prefixes == [
            "https://github.com/", "https://www.github.com/", "http://github.com/", "http://www.github.com/",
        ])
    }

    @Test func eachMatchPrefixIsAskedInEveryStoredForm() {
        let lookup = SiteIcon.lookup(open: "https://github.com/pulls", match: ["github.com/pulls", "www.github.com/", "https://github.com/pulls"])
        #expect(lookup?.prefixes == [
            "https://github.com/pulls", "https://www.github.com/pulls", "http://github.com/pulls", "http://www.github.com/pulls",
            "https://github.com/", "https://www.github.com/", "http://github.com/", "http://www.github.com/",
        ])
    }

    @Test func aPageThatIsNotOnTheWebHasNoIcon() {
        #expect(SiteIcon.lookup(open: "slack://open", match: nil) == nil)
        #expect(SiteIcon.lookup(open: "", match: nil) == nil)
        #expect(SiteIcon.lookup(open: "github.com", match: nil) == nil)
    }
}
