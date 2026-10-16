// The file CapsJump writes: its exact layout, that reading it back gives the same config
// (for every good file the other suites parse, and for values YAML finds awkward), that
// writing is stable, and which files count as canonical, so a save warns only when it
// would lose something.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct ConfigWriterTests {
    /// Every good file the parser's own suites read.
    static let goodFiles = [
        """
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
        """,
        "sites: []",
        """
        sites:
          - name: github
            account: alex@acme.dev
            open: https://github.com/
        keys:
          s: { app: iTerm }
          t: { app: Finder.app }
          o: { app: ~/Applications/Obsidian.app }
          x: { app: /Applications/Xcode.app }
          g: { site: github }
          left: { window: left-half }
          right: { window: right-half }
          f: { window: maximize }
          w: { url: "slack://channel?team=T123&id=C456" }
          e: { url: https://example.com/a?b=c }
          f1: { site: github }
        """,
        "keys:\n  t: { app: Terminal }\n",
        "sites: []\nkeys:\n",
        "keys:\n  n: { window: maximize }\n  y: { window: maximize }\n  1: { window: maximize }\n  0: { window: maximize }\n",
        """
        sites:
          - name: github
            account: alex@globex.io
            open: https://github.com
          - name: shared
            account: globex.io
            open: https://x.com
          - name: a
            profile: A
            account: Work
            open: https://x.com
        keys:
          s: { app: iTerm }
          n: { app: Notes Plus }
          m: { url: "zoommtg://join" }
        """,
    ]

    /// Values YAML reads as something else, or can't write plainly.
    static let awkward: Config = {
        let names = ["yes", "no", "null", "true", "y", "n", "0", "123", "1e3", "on", "a-b"]
        let accounts = ["a, b", "a: b", "#hash", "{brace}", "[bracket]", "'single'", "\"double\"", "~", "null", "Kim (Work)",
                        " lead", "trail ", "Zoë Ünïcode 日本", "a\\b", "@at", "%pct", "*star", "&amp", "!bang", "|pipe", ">gt", "- dash", "? q"]
        let sites = names.indices.map { index in
            let open = ["https://x.com/a?b=c&d=e#frag", "http://localhost:8080/", "https://x.com/%E6%97%A5", "https://x.com/"][index % 4]
            let match: [String] = index % 3 == 0 ? ["x.com/a, b", "x.com/#x", "x.com/{y}", "x.com/: z"] : [URLPrefix.defaultMatch(for: URL(string: open)!)]
            return Site(name: names[index], account: accounts[index], profile: index % 2 == 0 ? "Profile \(index)" : nil, open: URL(string: open)!, match: match)
        } + accounts.dropFirst(names.count).enumerated().map { index, account in
            Site(name: "s\(index)", account: account, profile: nil, open: URL(string: "https://x.com/")!, match: ["x.com/"])
        }
        let actions: [KeyAction] = [
            .app(.name("Visual Studio Code")), .app(.path("~/Applications/Ünï.app")), .app(.path("/Applications/A: B, #c.app")),
            .app(.name("yes")), .site("null"), .site("0"), .window(.leftHalf), .window(.rightHalf), .window(.maximize),
            .url(URL(string: "slack://channel?team=T1&id=C2")!), .url(URL(string: "https://example.com/?q=a#b")!),
            .url(URL(string: "mailto:kim@example.com")!), .url(URL(string: "zoommtg://join?confno=1")!),
        ]
        let keys = KeyNames.all.enumerated().map { index, key in KeyBinding(key: key, action: actions[index % actions.count]) }
        return Config(sites: sites, keys: keys)
    }()

    @Test func writesTheLayoutTheReadmeShows() {
        let config = Config(
            sites: [
                Site(name: "github", account: "alex@acme.dev", profile: nil, open: URL(string: "https://github.com/")!, match: ["github.com/"]),
                Site(name: "prs", account: "Kim Work", profile: "Profile 26", open: URL(string: "https://github.com/pulls")!, match: ["github.com/pulls", "github.com/"]),
            ],
            keys: [
                KeyBinding(key: "g", action: .site("github")),
                KeyBinding(key: "s", action: .app(.name("Slack"))),
                KeyBinding(key: "left", action: .window(.leftHalf)),
                KeyBinding(key: "w", action: .url(URL(string: "https://example.com")!)),
            ]
        )
        #expect(ConfigWriter.body(of: ConfigWriter.render(config)) == """
        sites:
        - name: github
          account: alex@acme.dev
          open: https://github.com/
        - name: prs
          account: Kim Work
          profile: Profile 26
          open: https://github.com/pulls
          match: [github.com/pulls, github.com/]

        keys:
          g: {site: github}
          s: {app: Slack}
          left: {window: left-half}
          w: {url: 'https://example.com'}

        """)
    }

    @Test func emptyConfigIsAWholeFile() throws {
        let text = ConfigWriter.render(Config(sites: []))
        #expect(ConfigWriter.body(of: text) == "sites: []\n\nkeys: {}\n")
        #expect(try ConfigParser.parse(text) == Config(sites: []))
    }

    @Test(arguments: goodFiles)
    func readsBackWhatItWrites(file: String) throws {
        try roundTrip(ConfigParser.parse(file))
    }

    @Test func readsBackAwkwardValues() throws {
        try roundTrip(Self.awkward)
    }

    @Test func quotesValuesYAMLWouldReadAsSomethingElse() {
        let text = ConfigWriter.render(Self.awkward)
        for line in ["- name: 'yes'", "- name: 'null'", "- name: '0'", "- name: '1e3'", "- name: 'on'", "account: '~'", "  d: {app: 'yes'}", "  e: {site: 'null'}"] {
            #expect(text.contains(line + "\n"), "\(line)")
        }
        // Key names stay as people write them, and `y` and `n` are no booleans to Yams.
        for line in ["- name: y\n", "  y: ", "  0: ", "  n: "] {
            #expect(text.contains(line), "\(line)")
        }
    }

    private func roundTrip(_ config: Config) throws {
        let text = ConfigWriter.render(config)
        #expect(try ConfigParser.parse(text) == config, "\(text)")
        #expect(try ConfigWriter.render(ConfigParser.parse(text)) == text)
        #expect(ConfigWriter.isCanonical(text))
    }

    @Test func aDefaultMatchIsLeftOutAndAWrittenOneKept() throws {
        let text = ConfigWriter.render(try ConfigParser.parse(Self.goodFiles[0]))
        #expect(text.contains("match: [github.com/stigmer/stigmer/pulls, github.com/]"))
        #expect(text.components(separatedBy: "match:").count == 2)
        // Written out, a match equal to the default is the default again.
        let explicit = "sites:\n  - name: a\n    account: x\n    open: https://claude.ai/new\n    match: [claude.ai/]\n"
        #expect(!ConfigWriter.render(try ConfigParser.parse(explicit)).contains("match"))
    }

    @Test func aFileIsCanonicalWhenSavingWouldGiveItBack() throws {
        let config = try ConfigParser.parse(Self.goodFiles[2])
        let text = ConfigWriter.render(config)
        let body = String(ConfigWriter.body(of: text))
        #expect(text.hasPrefix(ConfigWriter.marker + "\n"))
        #expect(ConfigWriter.isCanonical(text))
        // Without the header, or with a later version's wording of it, nothing is lost.
        #expect(ConfigWriter.isCanonical(body))
        #expect(ConfigWriter.isCanonical(ConfigWriter.marker + "\n# Reworded help.\n# Two lines now.\n\n" + body))

        // A comment, a layout of the file's own, a broken file: a save would change each.
        #expect(!ConfigWriter.isCanonical(body + "# mine\n"))
        #expect(!ConfigWriter.isCanonical("# my keys\n" + body))
        #expect(!ConfigWriter.isCanonical(body.replacingOccurrences(of: "  g: {site: github}", with: "  g: {site: github}  # work")))
        #expect(!ConfigWriter.isCanonical(Self.goodFiles[2]))
        #expect(!ConfigWriter.isCanonical(body.replacingOccurrences(of: "{site: github}", with: "{ site: github }")))
        #expect(!ConfigWriter.isCanonical("keys:\n  G: {window: maximize}\n"))
        // A comment inside CapsJump's own header block is CapsJump's to rewrite.
        #expect(ConfigWriter.isCanonical(ConfigWriter.marker + "\n# mine\n\n" + body))
    }

    @Test func theHeaderOpensWithTheMarkerAndSaysCommentsGo() throws {
        let text = ConfigWriter.render(Config(sites: []))
        let header = try #require(text.components(separatedBy: "sites:").first)
        #expect(text.hasPrefix("# Written by CapsJump.\n"))
        #expect(header.contains("capsjump check"))
        #expect(header.contains("comments added here don't survive"))
        #expect(header.hasSuffix("\n\n"))
    }

    @Test func starterNamesTheFolderWhenTheAccountIsShared() throws {
        let catalog = ProfileCatalog(profiles: [
            ChromeProfile(directory: "Profile 9", name: "Work", email: "alex@acme.dev", givenName: "Alex"),
            ChromeProfile(directory: "Profile 1", name: "acme.dev", email: "alex@acme.dev", givenName: "Alex"),
        ])
        let site = try #require(try ConfigParser.parse(StarterConfig.render(catalog: catalog)).sites.first)
        #expect(site.account == "alex@acme.dev")
        #expect(site.profile == "Profile 9")
    }
}
