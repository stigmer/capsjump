// What `capsjump check` reports for a missing file, a bad config, good sites, and each key.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct CheckupTests {
    private static let disk: Set<String> = ["/Applications/iTerm.app", "/Users/kim/Applications/Notes Plus.app"]
    private static let lookup = Lookup(
        home: "/Users/kim",
        exists: { disk.contains($0) },
        linkHandler: { ["https": "Safari", "slack": "Slack"][$0.scheme ?? ""] }
    )

    private func run(_ config: String?, _ state: String? = localState) -> [Finding] {
        Checkup.run(configText: config, configPath: "~/.capsjump.yaml", localState: state.map { Data($0.utf8) }, localStatePath: "Local State", lookup: Self.lookup)
    }

    private static let oneSite = "sites:\n  - name: github\n    account: alex@globex.io\n    open: https://github.com\n"

    @Test func missingFilesAreProblems() {
        #expect(run(nil).map(\.level) == [.problem])
        #expect(run(nil).first?.text.contains("capsjump init") == true)
        #expect(run(Self.oneSite, nil).first?.text.contains("has Chrome been opened") == true)
        #expect(run(Self.oneSite, "{}").first?.level == .problem)
        #expect(run("sites: []").map(\.level) == [.note])
    }

    @Test func keysNeedNoChrome() {
        #expect(run("keys:\n  f: { window: maximize }\n", nil) == [
            Finding(.ok, "`f` → window maximize"),
        ])
    }

    @Test func noKeysLeavesCapsLockAlone() {
        #expect(run(Self.oneSite).last == Finding(.ok, "no keys, so Caps Lock is left alone"))
    }

    @Test func eachKeySaysWhatItDoes() {
        let findings = run(Self.oneSite + """
        keys:
          s: { app: iTerm }
          n: { app: Notes Plus }
          z: { app: Zed }
          o: { app: ~/Apps/Obsidian.app }
          g: { site: github }
          left: { window: left-half }
          w: { url: "slack://channel?id=C1" }
          e: { url: https://example.com }
          m: { url: "zoommtg://join" }
        """)
        #expect(Array(findings.dropFirst()) == [
            Finding(.ok, "`s` → app /Applications/iTerm.app"),
            Finding(.ok, "`n` → app /Users/kim/Applications/Notes Plus.app"),
            Finding(.problem, "`z` → app Zed: no Zed.app in /Applications, /Applications/Utilities, /System/Applications, /System/Applications/Utilities, ~/Applications, /System/Library/CoreServices; give its path instead"),
            Finding(.problem, "`o` → app ~/Apps/Obsidian.app: nothing at /Users/kim/Apps/Obsidian.app"),
            Finding(.ok, "`g` → site github"),
            Finding(.ok, "`left` → window left-half"),
            Finding(.ok, "`w` → url slack://channel?id=C1 (opens in Slack)"),
            Finding(.ok, "`e` → url https://example.com (opens in Safari)"),
            Finding(.note, "`m` → url zoommtg://join: no installed app opens zoommtg links"),
        ])
    }

    @Test func configProblemsAreListedWithThePath() {
        let findings = run("sites:\n  - name: x\n")
        #expect(findings.allSatisfy { $0.level == .problem && $0.text.hasPrefix("~/.capsjump.yaml: ") })
        #expect(findings.count == 2)
    }

    @Test func eachSiteResolvesOrSaysWhy() {
        let findings = run("""
        sites:
          - name: github
            account: alex@globex.io
            open: https://github.com
          - name: shared
            account: globex.io
            open: https://x.com
        """)
        #expect(findings == [
            Finding(.ok, "github → Profile 15, windows labelled “Alex (globex.io)”"),
            Finding(.problem, "shared: `globex.io` matches the profiles `Profile 15` and `Profile 17`; name one with `profile:`"),
            Finding(.ok, "no keys, so Caps Lock is left alone"),
        ])
    }

    @Test func sharedLabelIsANote() {
        let state = #"{"profile": {"info_cache": {"A": {"name": "Work"}, "B": {"name": "Work"}}}}"#
        let findings = run("sites:\n  - name: a\n    profile: A\n    open: https://x.com\n", state)
        #expect(findings.map(\.level) == [.note, .ok])
        #expect(findings.first?.text.contains("always opens a new tab, because B carries the same label") == true)
    }
}
