// The key table, Caps Lock's HID usages, the `keys:` config, and where
// an app named by name is found.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct KeyNameTests {
    @Test func everyNameHasTriggersAndNoTwoShareOne() {
        #expect(KeyNames.all.count == 26 + 10 + 12 + 4)
        var owner: [KeyTrigger: String] = [:]
        for name in KeyNames.all {
            let triggers = KeyNames.triggers(for: name) ?? []
            #expect(!triggers.isEmpty, "\(name)")
            for trigger in triggers {
                #expect(owner[trigger] == nil, "\(name) and \(owner[trigger] ?? "") share \(trigger)")
                owner[trigger] = name
            }
        }
        #expect(owner[.key(CapsLock.keyCode)] == nil)
    }

    @Test(arguments: [
        ("a", [KeyTrigger.key(0)]), ("s", [.key(1)]), ("g", [.key(5)]), ("w", [.key(13)]), ("t", [.key(17)]),
        ("0", [.key(29)]), ("1", [.key(18)]), ("9", [.key(25)]),
        ("left", [.key(123)]), ("right", [.key(124)]), ("down", [.key(125)]), ("up", [.key(126)]),
        ("f1", [.key(122), .key(145)]), ("f2", [.key(120), .key(144)]), ("f3", [.key(99), .key(160)]),
        ("f4", [.key(118), .key(177)]), ("f5", [.key(96), .key(176)]), ("f6", [.key(97), .key(178)]),
        ("f7", [.key(98), .media(20)]), ("f8", [.key(100), .media(16)]), ("f9", [.key(101), .media(19)]),
        ("f10", [.key(109), .media(7)]), ("f11", [.key(103), .media(1)]), ("f12", [.key(111), .media(0)]),
    ])
    func knownKeys(name: String, triggers: [KeyTrigger]) {
        #expect(KeyNames.triggers(for: name) == triggers)
    }

    @Test(arguments: ["F1", "G", "f13", "space", "caps_lock", ""])
    func unknownNames(name: String) {
        #expect(KeyNames.triggers(for: name) == nil)
    }

    @Test func capsLockBecomesF18() {
        #expect(CapsLock.usage == 0x7_0000_0039)
        #expect(CapsLock.targetUsage == 0x7_0000_006D)
        #expect(CapsLock.keyCode == 0x4F)
        #expect(CapsLock.isMapping(source: 0x7_0000_0039, destination: 0x7_0000_006D))
        #expect(!CapsLock.isMapping(source: 0x7_0000_0039, destination: 0x7_0000_00E0))
        #expect(!CapsLock.isMapping(source: 0x7_0000_00E6, destination: 0x7_0000_006D))
    }
}

@Suite struct KeyConfigTests {
    @Test func parsesEveryActionInFileOrder() throws {
        let config = try ConfigParser.parse("""
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
        """)
        #expect(config.takesCapsLock)
        #expect(config.keys.map(\.key) == ["s", "t", "o", "x", "g", "left", "right", "f", "w", "e", "f1"])
        #expect(config.keys.map(\.action) == [
            .app(.name("iTerm")),
            .app(.name("Finder")),
            .app(.path("~/Applications/Obsidian.app")),
            .app(.path("/Applications/Xcode.app")),
            .site("github"),
            .window(.leftHalf),
            .window(.rightHalf),
            .window(.maximize),
            .url(URL(string: "slack://channel?team=T123&id=C456")!),
            .url(URL(string: "https://example.com/a?b=c")!),
            .site("github"),
        ])
    }

    @Test func keysAloneAreAWholeFile() throws {
        let config = try ConfigParser.parse("keys:\n  t: { app: Terminal }\n")
        #expect(config.sites.isEmpty)
        #expect(config.keys.count == 1)
    }

    @Test func noKeysLeavesCapsLockAlone() throws {
        #expect(try !ConfigParser.parse("sites: []").takesCapsLock)
        #expect(try !ConfigParser.parse("sites: []\nkeys:\n").takesCapsLock)
        #expect(try !ConfigParser.parse("sites: []\nkeys: {}\n").takesCapsLock)
    }

    /// Caps Lock is the one key; there is no setting to pick another.
    @Test func thereIsNoHyperSetting() {
        let error = #expect(throws: ConfigError.self) {
            try ConfigParser.parse("hyper: right_option\nkeys:\n  t: { window: maximize }\n")
        }
        #expect(error?.problems == ["the file: unknown key `hyper` (known keys: `keys`, `sites`)"])
    }

    /// YAML 1.1 reads a bare n, y, no or yes as a boolean; key names are read as written.
    @Test func bareLettersAndDigitsNeedNoQuotes() throws {
        let config = try ConfigParser.parse("keys:\n  n: { window: maximize }\n  y: { window: maximize }\n  1: { window: maximize }\n  0: { window: maximize }\n")
        #expect(config.keys.map(\.key) == ["n", "y", "1", "0"])
    }

    @Test func aKeyBoundTwiceIsRefused() {
        let error = #expect(throws: ConfigError.self) {
            try ConfigParser.parse("keys:\n  g: { window: maximize }\n  g: { window: left-half }\n")
        }
        #expect(error?.description.contains("not valid YAML") == true, "\(error?.description ?? "")")
        #expect(error?.description.contains("duplicated key(s): 'g'") == true, "\(error?.description ?? "")")
    }

    @Test func namesEveryKeyProblemAtOnce() {
        let error = #expect(throws: ConfigError.self) {
            try ConfigParser.parse("""
            sites:
              - name: github
                account: alex@acme.dev
                open: https://github.com/
            keys:
              G: { window: maximize }
              a: { site: gitlab }
              b: { app: Slack, site: github }
              c: {}
              d: { window: top-half }
              e: { url: example.com }
              h: { app: Applications/Slack.app }
              i: { app: ~/Tools/run.sh }
              j: Slack
              k: { app: Slack, color: red }
              l: { url: "" }
            """)
        }
        let problems = error?.problems ?? []
        let expected = [
            "line 6: keys.G: unknown key name `G`",
            "line 7: keys.a: no site named `gitlab` in `sites:`",
            "line 8: keys.b: give one action, not `app` and `site`",
            "line 9: keys.c: give one of `app`, `site`, `window` or `url`",
            "line 10: keys.d: `window` must be one of `left-half`, `right-half`, `maximize`, not `top-half`",
            "line 11: keys.e: `url` must be a link with a scheme",
            "line 12: keys.h: `app` must be an app's name",
            "line 13: keys.i: `app` must be an app's name",
            "line 14: keys.j must be a mapping",
            "line 15: keys.k: unknown key `color`",
            "line 16: keys.l: `url` must be a non-empty text",
        ]
        for fragment in expected {
            #expect(problems.contains { $0.contains(fragment) }, "missing: \(fragment)\nin: \(problems)")
        }
        #expect(problems.count == expected.count, "\(problems)")
    }

    @Test func aKeyNamingABrokenSiteIsNotReportedTwice() {
        let error = #expect(throws: ConfigError.self) {
            try ConfigParser.parse("""
            sites:
              - name: github
                open: https://github.com/
            keys:
              g: { site: github }
            """)
        }
        #expect(error?.problems.count == 1, "\(error?.problems ?? [])")
    }

    @Test func keysMustBeAMapping() {
        let error = #expect(throws: ConfigError.self) { try ConfigParser.parse("keys: [g]") }
        #expect(error?.description.contains("`keys` must be a mapping") == true)
    }
}

@Suite struct AppTargetTests {
    @Test(arguments: [
        ("Slack", AppTarget.name("Slack")),
        ("Slack.app", .name("Slack")),
        ("Visual Studio Code", .name("Visual Studio Code")),
        ("/Applications/Slack.app", .path("/Applications/Slack.app")),
        ("/Applications/Slack.app/", .path("/Applications/Slack.app")),
        ("~/Applications/Slack.app", .path("~/Applications/Slack.app")),
    ] as [(String, AppTarget)])
    func parses(raw: String, target: AppTarget) {
        #expect(AppTarget.parse(raw) == target)
    }

    @Test(arguments: ["", " ", ".app", "Applications/Slack.app", "~/bin/slack", "/usr/bin/open", "/.app", "~x/Slack.app"])
    func refuses(raw: String) {
        #expect(AppTarget.parse(raw) == nil)
    }

    @Test func aNameIsLookedForInOrder() {
        let candidates = AppTarget.name("iTerm").candidates(home: "/Users/kim")
        #expect(candidates == [
            "/Applications/iTerm.app",
            "/Applications/Utilities/iTerm.app",
            "/System/Applications/iTerm.app",
            "/System/Applications/Utilities/iTerm.app",
            "/Users/kim/Applications/iTerm.app",
            "/System/Library/CoreServices/iTerm.app",
        ])
        let disk: Set<String> = ["/System/Library/CoreServices/Finder.app", "/Users/kim/Applications/Finder.app"]
        #expect(AppTarget.name("Finder").resolve(home: "/Users/kim", exists: disk.contains) == "/Users/kim/Applications/Finder.app")
        #expect(AppTarget.name("Nope").resolve(home: "/Users/kim", exists: disk.contains) == nil)
    }

    @Test func aPathIsUsedAsWrittenWithTheHomeExpanded() {
        #expect(AppTarget.path("~/Apps/X.app").candidates(home: "/Users/kim/") == ["/Users/kim/Apps/X.app"])
        #expect(AppTarget.path("/Opt/X.app").candidates(home: "/Users/kim") == ["/Opt/X.app"])
    }
}
