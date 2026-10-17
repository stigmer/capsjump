// What the config window's list stands on: one check of the draft that agrees with its
// `issues` and `config`, each key and site as one line of text, the search that keeps
// lines, and keys listed in the keyboard's order while the file keeps its own.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct DraftCheckTests {
    private static let file = """
    sites:
      - name: github
        account: alex@acme.dev
        open: https://github.com/
      - name: prs
        account: alex@acme.dev
        open: https://github.com/pulls
        match: [github.com/pulls]
    keys:
      g: { site: github }
      h: { site: github }
      p: { site: prs }
      f: { window: maximize }
    """

    @Test func aGoodDraftChecksToItsConfig() throws {
        let draft = ConfigDraft(ConfigReader.read(Self.file))
        let check = draft.checked()
        #expect(check.config == (try ConfigParser.parse(Self.file)))
        #expect(check.issues.isEmpty && check.file.isEmpty && check.bySite.isEmpty && check.byKey.isEmpty)
        #expect(check.config == draft.config)
    }

    @Test func eachProblemIsFiledUnderItsRow() {
        var draft = ConfigDraft(ConfigReader.read(Self.file))
        let github = draft.sites[0].id
        let prs = draft.sites[1].id
        draft.updateSite(github) { $0.account = "" }
        draft.renameSite(prs, to: "")
        draft.setAction(draft.keys[3].id, ActionSource(.window, "sideways"))
        let check = draft.checked()
        #expect(check.issues == draft.issues)
        #expect(check.config == nil)
        #expect(check.site(github).map(\.message) == ["give `account` (an email, or the profile's name) or `profile` (a folder such as `Profile 26`)"])
        #expect(check.site(github, [.name, .open]).isEmpty)
        #expect(check.site(prs, [.name]).map(\.message) == ["`name` is missing"])
        #expect(check.key(draft.keys[2].id).map(\.message) == ["`site` must be a non-empty text"])
        #expect(check.key(draft.keys[3].id).count == 1)
        #expect(check.key(draft.keys[0].id).isEmpty)
        let filed = check.file.count + check.bySite.values.map(\.count).reduce(0, +) + check.byKey.values.map(\.count).reduce(0, +)
        #expect(filed == check.issues.count)
    }

    @Test func aProblemWithTheKeysAsAWholeIsAboveTheRows() {
        let draft = ConfigDraft(ConfigReader.read("sites: []\nkeys:\n  g: {}\n"))
        let check = draft.checked()
        #expect(check.issues == draft.issues)
        #expect(check.file.map(\.spot) == check.issues.filter { $0.spot == .file }.map(\.spot))
    }
}

@Suite struct EditorRowsTests {
    private static let file = """
    sites:
      - name: gmail-work
        account: alex@acme.dev
        open: https://mail.google.com/mail/u/0/#inbox
      - name: gmail-home
        profile: Profile 2
        open: https://mail.google.com/mail/u/1/#inbox
      - name: café
        account: alex@acme.dev
        open: https://cafe.example/
    keys:
      a: { app: Slack }
      left: { window: left-half }
      f1: { site: gmail-home }
      '1': { url: 'https://docs.example.com/start' }
      b: { site: gmail-work }
      z: { app: ~/Applications/Tools/Big Editor.app }
      m: { url: 'slack://open' }
      g: { site: gmail-work }
      f: { window: maximize }
    """

    private let draft = ConfigDraft(ConfigReader.read(Self.file))

    private func line(_ key: String) -> EditorRows.KeyLine {
        EditorRows.keys(draft).first { $0.key == key }!
    }

    @Test func keysAreListedInTheKeyboardsOrderAndTheFileKeepsItsOwn() {
        #expect(EditorRows.keys(draft).map(\.key) == ["a", "b", "f", "g", "m", "z", "1", "f1", "left"])
        #expect(draft.source.keys.map(\.key) == ["a", "left", "f1", "1", "b", "z", "m", "g", "f"])
        var moved = draft
        _ = moved.bind("c", to: ActionSource(.window, "maximize"), row: moved.keys.first { $0.key.key == "f" }!.id)
        #expect(EditorRows.keys(moved).map(\.key) == ["a", "b", "c", "g", "m", "z", "1", "f1", "left"])
    }

    @Test func aNameTheKeyboardDoesNotKnowSortsLast() {
        #expect(EditorRows.rank("up") < EditorRows.rank("hyper"))
        #expect(EditorRows.rank("a") < EditorRows.rank("0"))
    }

    @Test func eachKeyReadsLikeTheKeyAndWhatItDoes() {
        #expect([line("a").symbol, line("a").title] == ["A", "Slack"])
        #expect(line("a").subtitle == nil && line("a").app == "Slack" && line("a").kind == .app)
        #expect([line("z").title, line("z").subtitle] == ["Big Editor", "~/Applications/Tools/Big Editor.app"])
        #expect([line("b").title, line("b").subtitle] == ["gmail-work", "alex@acme.dev"])
        #expect([line("f1").title, line("f1").subtitle] == ["gmail-home", "Profile 2"])
        #expect([line("left").symbol, line("left").title] == ["←", "Left half"])
        #expect(line("f").title == "Whole screen")
        #expect([line("1").title, line("1").subtitle] == ["docs.example.com", "https://docs.example.com/start"])
        #expect([line("m").title, line("m").subtitle] == ["slack://open", nil])
    }

    @Test func aKeyStillBeingFilledInSaysWhatIsMissing() {
        var draft = draft
        guard case let .bound(row) = draft.bind("q", to: nil) else { Issue.record("not bound"); return }
        #expect(EditorRows.key(draft.key(row)!, in: draft).title == "Does nothing yet")
        draft.setAction(row, ActionSource(.app, ""))
        #expect(EditorRows.key(draft.key(row)!, in: draft).title == "Choose an app")
        #expect(EditorRows.key(draft.key(row)!, in: draft).spoken == "Caps Lock plus Q, has no app yet")
        draft.setAction(row, ActionSource(.site, ""))
        #expect(EditorRows.key(draft.key(row)!, in: draft).title == "Choose a site")
        draft.setAction(row, ActionSource(.url, ""))
        #expect(EditorRows.key(draft.key(row)!, in: draft).title == "Give the link")
    }

    @Test func voiceOverReadsALineAsOneSentence() {
        #expect(line("b").spoken == "Caps Lock plus B, jumps to gmail-work, alex@acme.dev")
        #expect(line("left").spoken == "Caps Lock plus Left Arrow, moves the front window to the left half")
        #expect(line("a").spoken == "Caps Lock plus A, brings Slack forward")
        #expect(line("1").spoken == "Caps Lock plus 1, opens docs.example.com")
        let site = EditorRows.sites(draft)[0]
        #expect(site.spoken == "gmail-work, alex@acme.dev, mail.google.com, Caps Lock plus B or G")
    }

    @Test func aSiteListsItsAccountHostAndKeys() {
        let sites = EditorRows.sites(draft)
        #expect(sites.map(\.name) == ["gmail-work", "gmail-home", "café"])
        #expect(sites[0].keys == ["b", "g"] && sites[1].keys == ["f1"] && sites[2].keys.isEmpty)
        #expect([sites[0].account, sites[0].host] == ["alex@acme.dev", "mail.google.com"])
        #expect(sites[1].account == "Profile 2")
    }

    @Test func searchKeepsLinesWithEveryWordIgnoringCaseAndAccents() {
        #expect(EditorRows.sites(draft, matching: "GMAIL").map(\.name) == ["gmail-work", "gmail-home"])
        #expect(EditorRows.keys(draft, matching: "gmail").map(\.key) == ["b", "g", "f1"])
        #expect(EditorRows.keys(draft, matching: "slack").map(\.key) == ["a", "m"])
        #expect(EditorRows.sites(draft, matching: "cafe").map(\.name) == ["café"])
        #expect(EditorRows.sites(draft, matching: "gmail profile").map(\.name) == ["gmail-home"])
        #expect(EditorRows.sites(draft, matching: "acme.dev").count == 2)
        #expect(EditorRows.keys(draft, matching: "←").map(\.key) == ["left"])
        #expect(EditorRows.keys(draft, matching: "  ").count == draft.keys.count)
        #expect(EditorRows.keys(draft, matching: "nothing-like-this").isEmpty)
    }
}
