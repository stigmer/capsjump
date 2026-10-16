// The config file's parsing and validation: what a good file yields, and that a bad one
// names every problem at once, unknown keys included.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct ConfigTests {
    @Test func parsesSitesWithDefaultsAndExplicitMatch() throws {
        let config = try ConfigParser.parse("""
        sites:
          - name: github
            account: alex@acme.dev
            open: https://github.com/stigmer/stigmer/pulls
            match: [github.com/stigmer/stigmer/pulls, github.com/]
          - name: claude-kim
            account: kim@initech.com
            open: https://claude.ai/new
          - name: mail
            profile: Profile 26
            open: https://www.google.com/mail
        """)
        #expect(config.sites.map(\.name) == ["github", "claude-kim", "mail"])
        #expect(config.sites[0].match == ["github.com/stigmer/stigmer/pulls", "github.com/"])
        #expect(config.sites[1].match == ["claude.ai/"])
        #expect(config.sites[2].match == ["google.com/"])
        #expect(config.sites[2].profile == "Profile 26")
        #expect(config.sites[2].account == nil)
        #expect(config.site(named: "claude-kim")?.open.absoluteString == "https://claude.ai/new")
    }

    @Test func emptySitesListIsValid() throws {
        #expect(try ConfigParser.parse("sites: []").sites.isEmpty)
    }

    @Test(arguments: [
        ("", "the file is empty"),
        ("- a", "must be a mapping"),
        ("other: 1", "no `sites:` list"),
        ("sites: x", "`sites` must be a list"),
        ("sites: [\n", "not valid YAML"),
    ])
    func refusesBadShapes(yaml: String, expected: String) {
        let error = #expect(throws: ConfigError.self) { try ConfigParser.parse(yaml) }
        #expect(error?.description.contains(expected) == true, "\(error?.description ?? "")")
    }

    @Test func namesEveryProblemAtOnce() {
        let error = #expect(throws: ConfigError.self) {
            try ConfigParser.parse("""
            sites:
              - name: GitHub
                acount: alex@acme.dev
                open: ftp://github.com
              - name: _setup
                account: a@b.c
                open: https://x.com
                match: [https://x.com/]
              - account: a@b.c
                open: https://x.com
              - name: dup
                account: a@b.c
                open: https://x.com
              - name: dup
                account: a@b.c
                open: https://y.com
              - name: empty-match
                account: a@b.c
                open: https://x.com
                match: []
              - name: bad-match
                account: a@b.c
                open: https://x.com
                match: x.com
              - just text
            extra: true
            """)
        }
        let problems = error?.problems ?? []
        let expected = [
            "unknown key `extra`",
            "line 2: sites[0] (GitHub): unknown key `acount`",
            "sites[0] (GitHub): name `GitHub` may use only lower-case letters",
            "sites[0] (GitHub): give `account`",
            "sites[0] (GitHub): `open` must be an http or https URL, not `ftp://github.com`",
            "sites[1] (_setup): name `_setup` starts with `_`",
            "sites[1] (_setup): `match` entry `https://x.com/` must not carry a scheme; write it as `x.com/`",
            "sites[2]: `name` is missing",
            "sites[4]: name `dup` is already used by sites[3]",
            "sites[5] (empty-match): `match` is empty",
            "sites[6] (bad-match): `match` must be a list",
            "sites[7] must be a mapping",
        ]
        for fragment in expected {
            #expect(problems.contains { $0.contains(fragment) }, "missing: \(fragment)\nin: \(problems)")
        }
        #expect(problems.count == expected.count, "\(problems)")
    }

    @Test func refusesNonTextValues() {
        let error = #expect(throws: ConfigError.self) {
            try ConfigParser.parse("""
            sites:
              - name: x
                account: [a]
                open: {u: 1}
            """)
        }
        #expect(error?.problems.contains { $0.contains("`account` must be a non-empty text") } == true)
        #expect(error?.problems.contains { $0.contains("`open` must be a non-empty text") } == true)
    }

    @Test(arguments: [
        ("github", nil),
        ("claude-kim", nil),
        ("a1", nil),
        ("_setup", "reserved"),
        ("-x", "inner hyphens"),
        ("x-", "inner hyphens"),
        ("a.b", "inner hyphens"),
        ("Git", "inner hyphens"),
        ("", "inner hyphens"),
    ] as [(String, String?)])
    func siteNames(name: String, problem: String?) {
        let found = SiteName.problem(with: name)
        if let problem {
            #expect(found?.contains(problem) == true, "\(found ?? "nil")")
        } else {
            #expect(found == nil)
        }
    }

    @Test func starterIsCanonicalAndUsesTheFirstAccount() throws {
        let catalog = ProfileCatalog(profiles: [
            ChromeProfile(directory: "Profile 1", name: "acme.dev", email: "alex@acme.dev", givenName: "Alex"),
            ChromeProfile(directory: "Profile 26", name: "kim@initech.com", email: "", givenName: ""),
        ])
        let text = StarterConfig.render(catalog: catalog)
        #expect(ConfigWriter.isCanonical(text))
        let config = try ConfigParser.parse(text)
        #expect(config.sites.map(\.name) == ["github"])
        #expect(config.sites.first?.account == "alex@acme.dev")
        #expect(config.sites.first?.profile == nil)
        #expect(config.keys == [
            KeyBinding(key: "left", action: .window(.leftHalf)),
            KeyBinding(key: "right", action: .window(.rightHalf)),
            KeyBinding(key: "f", action: .window(.maximize)),
        ])

        let offline = StarterConfig.render(catalog: nil)
        #expect(ConfigWriter.isCanonical(offline))
        #expect(try ConfigParser.parse(offline).sites.first?.account == "you@example.com")
    }
}
