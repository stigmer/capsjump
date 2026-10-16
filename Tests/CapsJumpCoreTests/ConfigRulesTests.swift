// The rules applied apart from reading: each problem's place, so the window can show it
// beside its field; reading's problems and the rules' reported together in file order; a
// key bound twice, which only a form can produce; and a source with no lines, as the
// window builds one.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct ConfigRulesTests {
    private func found(_ yaml: String) -> [Problem] {
        guard case let .failure(error) = ConfigRules.validate(ConfigReader.read(yaml)) else { return [] }
        return error.found
    }

    @Test func eachProblemKnowsItsEntryAndField() {
        let problems = found("""
        sites:
          - name: GitHub
            acount: alex@acme.dev
            open: ftp://github.com
          - name: ok
            account: a@b.c
            open: https://x.com
            match: [https://x.com/]
          - just text
        keys:
          G: { window: maximize }
          a: { site: gitlab }
          j: Slack
        """)
        #expect(problems.map(\.place) == [
            .site(index: 0, name: "GitHub", field: .unknownKey),
            .site(index: 0, name: "GitHub", field: .name),
            .site(index: 0, name: "GitHub", field: .accountOrProfile),
            .site(index: 0, name: "GitHub", field: .open),
            .site(index: 1, name: "ok", field: .match),
            .site(index: 2, name: nil, field: .entry),
            .key(index: 0, name: "G", field: .key),
            .key(index: 1, name: "a", field: .action),
            .key(index: 2, name: "j", field: .entry),
        ])
        #expect(problems.map(\.line) == [2, 2, 2, 2, 5, 9, 11, 12, 13])
        #expect(problems[1].message == "name `GitHub` may use only lower-case letters, digits and inner hyphens")
        #expect(problems[5].description == "line 9: sites[2] must be a mapping with name, account and open")
        #expect(problems[8].description == "line 13: keys.j must be a mapping with one of app, site, window or url, such as `{ app: Safari }`")
    }

    @Test func readingAndTheRulesReportTogetherInFileOrder() {
        let problems = found("""
        sites:
          - name: Bad
            account: [a]
            open: https://x.com
        keys:
          G: { app: Slack, colour: red }
        extra: 1
        """).map(\.description)
        #expect(problems == [
            "the file: unknown key `extra` (known keys: `keys`, `sites`)",
            "line 2: sites[0] (Bad): name `Bad` may use only lower-case letters, digits and inner hyphens",
            "line 2: sites[0] (Bad): `account` must be a non-empty text",
            "line 2: sites[0] (Bad): give `account` (an email, or the profile's name) or `profile` (a folder such as `Profile 26`)",
            "line 6: keys.G: unknown key name `G` (key names: a–z, 0–9, f1–f12, left, right, up, down)",
            "line 6: keys.G: unknown key `colour` (known keys: `app`, `site`, `url`, `window`)",
        ])
    }

    @Test func readingAloneFindsOnlyWhatYAMLGetsWrong() {
        let source = ConfigReader.read("""
        sites:
          - name: Bad
            open: nope
            match: x.com
        keys:
          G: { window: top-half }
          b: { app: Slack, site: github }
        """)
        #expect(source.problems.map(\.description) == [
            "line 2: sites[0] (Bad): `match` must be a list",
            "line 7: keys.b: give one action, not `app` and `site`",
        ])
        #expect(source.sites == [SiteSource(index: 0, line: 2, name: "Bad", open: "nope")])
        #expect(source.keys == [
            KeySource(index: 0, line: 6, key: "G", action: ActionSource(.window, "top-half")),
            KeySource(index: 1, line: 7, key: "b", action: nil),
        ])
    }

    @Test func aMatchLeftOutIsNilAndTheDefaultComesFromTheRules() throws {
        let source = ConfigReader.read("sites:\n  - name: a\n    account: x\n    open: https://claude.ai/new\n")
        #expect(source.sites.first?.match == nil)
        let config = try ConfigRules.validate(source).get()
        #expect(config.sites.first?.match == ["claude.ai/"])
    }

    @Test func aKeyBoundTwiceInAFormIsAProblem() {
        let source = ConfigSource(keys: [
            KeySource(index: 0, key: "g", action: ActionSource(.window, "maximize")),
            KeySource(index: 1, key: "g", action: ActionSource(.window, "left-half")),
        ])
        guard case let .failure(error) = ConfigRules.validate(source) else {
            Issue.record("a key bound twice passed")
            return
        }
        #expect(error.found == [Problem(.key(index: 1, name: "g", field: .key), "`g` is bound twice")])
        #expect(error.problems == ["keys.g: `g` is bound twice"])
    }

    @Test func aFormsSourceHasNoLinesAndBlankFieldsAreProblems() {
        let source = ConfigSource(
            sites: [SiteSource(index: 0, name: "a", account: " ", open: "")],
            keys: [KeySource(index: 0, key: "g", action: nil), KeySource(index: 1, key: "h", action: ActionSource(.app, ""))]
        )
        guard case let .failure(error) = ConfigRules.validate(source) else {
            Issue.record("blank fields passed")
            return
        }
        #expect(error.problems == [
            "sites[0] (a): `account` must be a non-empty text",
            "sites[0] (a): give `account` (an email, or the profile's name) or `profile` (a folder such as `Profile 26`)",
            "sites[0] (a): `open` must be a non-empty text",
            "keys.g: give one of `app`, `site`, `window` or `url`",
            "keys.h: `app` must be a non-empty text",
        ])
    }
}
