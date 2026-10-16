// What the editing window stands on: the draft's problems pinned to rows, its edits that
// reach across rows (rename, remove, bind), which account and app text a pick writes, and
// each site's and key's own checkup line.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct ConfigDraftTests {
    private func draft(_ yaml: String) -> ConfigDraft {
        ConfigDraft(ConfigReader.read(yaml))
    }

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

    @Test func aGoodDraftIsItsConfig() throws {
        let draft = draft(Self.file)
        #expect(draft.issues.isEmpty)
        #expect(draft.config == (try ConfigParser.parse(Self.file)))
        #expect(draft.matchIsDefault(draft.sites[0].id))
        #expect(!draft.matchIsDefault(draft.sites[1].id))
    }

    @Test func problemsArePinnedToRowsThatSurviveEdits() throws {
        var draft = draft(Self.file)
        let prs = draft.sites[1].id
        draft.updateSite(prs) { $0.open = "ftp://x" }
        draft.removeSite(draft.sites[0].id, removingKeys: true)
        #expect(draft.issues == [ConfigDraft.Issue(spot: .site(id: prs, field: .open), message: "`open` must be an http or https URL, not `ftp://x`")])
        #expect(draft.config == nil)
        draft.updateSite(prs) { $0.open = "https://github.com/pulls" }
        #expect(draft.issues.isEmpty)
        #expect(draft.config?.sites.map(\.name) == ["prs"])
    }

    @Test func aClearedFieldIsAFieldNotGiven() {
        var draft = draft(Self.file)
        let github = draft.sites[0].id
        draft.updateSite(github) { $0.account = "" }
        draft.renameSite(github, to: "")
        #expect(draft.issues.map(\.message) == [
            "`name` is missing",
            "give `account` (an email, or the profile's name) or `profile` (a folder such as `Profile 26`)",
            "`site` must be a non-empty text",
            "`site` must be a non-empty text",
        ])
        #expect(draft.issues.map(\.spot) == [
            .site(id: github, field: .name),
            .site(id: github, field: .accountOrProfile),
            .key(id: draft.keys[0].id, field: .action),
            .key(id: draft.keys[1].id, field: .action),
        ])
    }

    @Test func renamingCarriesTheKeysAndListsTheLinkThatStops() {
        var draft = draft(Self.file)
        let github = draft.sites[0].id
        #expect(draft.renameSite(github, to: "gh") == ["g", "h"])
        #expect(draft.keys.map(\.key.action) == [ActionSource(.site, "gh"), ActionSource(.site, "gh"), ActionSource(.site, "prs"), ActionSource(.window, "maximize")])
        #expect(draft.brokenLinks == ["github"])
        #expect(draft.issues.isEmpty)
        // Saved, the new name's link is the one that works.
        var saved = draft
        saved.markSaved()
        #expect(saved.brokenLinks.isEmpty)
        // Typed back, the link works again.
        draft.renameSite(github, to: "github")
        #expect(draft.brokenLinks.isEmpty)
        // Other fields never rename.
        draft.updateSite(github) { $0.name = "other"; $0.open = "https://github.com/x" }
        #expect(draft.site(github)?.site.name == "github")
        #expect(draft.site(github)?.site.open == "https://github.com/x")
    }

    @Test func aNewNameTypedThroughAnotherSitesNameLeavesItsKeysAlone() {
        var draft = draft(Self.file)
        let added = draft.addSite(SiteSource(index: 2, name: "", open: "https://github.com/x"))
        for typed in ["p", "pr", "prs", "prsx", "prs", "pr", "p", ""] {
            draft.renameSite(added, to: typed)
        }
        #expect(draft.key(draft.keys[2].id)?.key.action == ActionSource(.site, "prs"))
        // Cleared and retyped, a site keeps its keys.
        let github = draft.sites[0].id
        draft.renameSite(github, to: "")
        draft.renameSite(github, to: "hub")
        #expect(draft.keysUsing(github) == ["g", "h"])
        #expect(draft.keys[0].key.action == ActionSource(.site, "hub"))
        // The site the keys point to still carries them along.
        #expect(draft.renameSite(draft.sites[1].id, to: "pulls") == ["p"])
        #expect(draft.keys[2].key.action == ActionSource(.site, "pulls"))
    }

    @Test func removingASiteSaysWhichKeysUsedIt() {
        var kept = draft(Self.file)
        #expect(kept.keysUsing(kept.sites[0].id) == ["g", "h"])
        #expect(kept.removeSite(kept.sites[0].id, removingKeys: false) == ["g", "h"])
        #expect(kept.keys.count == 4)
        #expect(kept.issues.map(\.message) == ["no site named `github` in `sites:`", "no site named `github` in `sites:`"])
        #expect(kept.brokenLinks == ["github"])

        var removed = draft(Self.file)
        #expect(removed.removeSite(removed.sites[0].id, removingKeys: true) == ["g", "h"])
        #expect(removed.keys.map(\.key.key) == ["p", "f"])
        #expect(removed.issues.isEmpty)
    }

    @Test func bindingATakenKeySaysWhatItDoesNow() {
        var draft = draft(Self.file)
        let f = draft.keys[3].id
        #expect(draft.bind("g", to: ActionSource(.app, "Slack")) == .taken(row: draft.keys[0].id, action: ActionSource(.site, "github")))
        #expect(draft.keys.count == 4)
        #expect(draft.bind("g", to: ActionSource(.window, "maximize"), row: f) == .taken(row: draft.keys[0].id, action: ActionSource(.site, "github")))
        #expect(draft.key(f)?.key.key == "f")

        // Its own key is never taken from itself.
        #expect(draft.bind("f", to: ActionSource(.window, "left-half"), row: f) == .bound(row: f))
        #expect(draft.key(f)?.key.action == ActionSource(.window, "left-half"))

        // Replacing removes the other row.
        #expect(draft.bind("g", to: ActionSource(.window, "maximize"), row: f, replacing: true) == .bound(row: f))
        #expect(draft.keys.map(\.key.key) == ["h", "p", "g"])

        guard case let .bound(added) = draft.bind("s", to: ActionSource(.app, "Slack")) else {
            Issue.record("a free key was refused")
            return
        }
        #expect(draft.key(added)?.key == KeySource(index: 3, key: "s", action: ActionSource(.app, "Slack")))
        draft.setAction(added, ActionSource(.url, "slack://open"))
        draft.removeKey(draft.keys[0].id)
        #expect(draft.config?.keys.map(\.key) == ["p", "g", "s"])
    }

    @Test func freeKeysFollowTheKeyTableAndIncludeTheRowsOwn() {
        let draft = draft(Self.file)
        let free = draft.freeKeys()
        #expect(free.count == KeyNames.all.count - 4)
        #expect(free.prefix(5) == ["a", "b", "c", "d", "e"])
        #expect(!free.contains("g"))
        #expect(draft.freeKeys(for: draft.keys[0].id).prefix(7) == ["a", "b", "c", "d", "e", "g", "i"])
        #expect(free.suffix(4) == ["left", "right", "down", "up"])
    }
}

@Suite struct PickTests {
    @Test func anAccountWritesTheFolderOnlyWhenItMustSayWhichProfile() throws {
        let c = try catalog()
        func fields(_ directory: String) throws -> SiteAccountFields {
            let (account, profile) = SiteAccount.fields(for: try #require(c.profile(directory: directory)), in: c)
            return SiteAccountFields(account: account, profile: profile)
        }
        #expect(try fields("Profile 15") == SiteAccountFields(account: "alex@globex.io", profile: nil))
        #expect(try fields("Profile 26") == SiteAccountFields(account: "kim@initech.com", profile: nil))
        // alex@acme.dev is signed in to two profiles.
        #expect(try fields("Profile 1") == SiteAccountFields(account: "alex@acme.dev", profile: "Profile 1"))
        #expect(try fields("Profile 9") == SiteAccountFields(account: "alex@acme.dev", profile: "Profile 9"))
        // Whatever is written lands on the profile picked.
        for profile in c.profiles {
            let (account, folder) = SiteAccount.fields(for: profile, in: c)
            let target = try Resolver.resolve(site(account: account, profile: folder), in: c)
            #expect(target.profile == profile)
        }
    }

    struct SiteAccountFields: Equatable {
        let account: String
        let profile: String?
    }

    @Test func anAppPickedByPathIsWrittenByNameWhenTheNameFindsIt() {
        let disk: Set<String> = ["/Applications/Slack.app", "/Users/kim/Applications/Slack.app", "/System/Applications/Notes.app", "/Users/kim/Applications/Tool.app"]
        func preferred(_ path: String) -> AppTarget {
            AppTarget.preferred(forPath: path, home: "/Users/kim", exists: disk.contains)
        }
        #expect(preferred("/Applications/Slack.app") == .name("Slack"))
        #expect(preferred("/Applications/Slack.app/") == .name("Slack"))
        #expect(preferred("/System/Applications/Notes.app") == .name("Notes"))
        #expect(preferred("/Users/kim/Applications/Tool.app") == .name("Tool"))
        // The name would find /Applications/Slack.app first, so this one keeps its path.
        #expect(preferred("/Users/kim/Applications/Slack.app") == .path("~/Applications/Slack.app"))
        #expect(preferred("/Volumes/Apps/Zed.app") == .path("/Volumes/Apps/Zed.app"))
        #expect(preferred("/Users/kimberly/Zed.app") == .path("/Users/kimberly/Zed.app"))
        for path in disk {
            #expect(preferred(path).resolve(home: "/Users/kim", exists: disk.contains) == path)
        }
    }

    @Test func eachRowHasItsOwnCheckupLine() throws {
        let lookup = Lookup(home: "/Users/kim", exists: { $0 == "/Applications/iTerm.app" }, linkHandler: { $0.scheme == "slack" ? "Slack" : nil })
        #expect(Checkup.key(KeyBinding(key: "s", action: .app(.name("iTerm"))), lookup: lookup) == Finding(.ok, "`s` → app /Applications/iTerm.app"))
        #expect(Checkup.key(KeyBinding(key: "w", action: .url(URL(string: "slack://open")!)), lookup: lookup) == Finding(.ok, "`w` → url slack://open (opens in Slack)"))
        #expect(Checkup.site(site("github", account: "alex@globex.io"), catalog: try catalog()) == Finding(.ok, "github → Profile 15, windows labelled “Alex (globex.io)”"))
        #expect(Checkup.site(site("x", account: "nobody@x.com"), catalog: try catalog()).level == .problem)
    }
}
