// Chrome's Local State parsing, window labels, account lookup and site resolution, on
// the shapes measured on a real Mac: profiles signed out with the email only in the name,
// and two profiles sharing a name. Profile pictures by Chrome's own rule, on the shapes
// measured: signed in on the default avatar, asking for the Google picture, no account.

import Foundation
import Testing
@testable import CapsJumpCore

let localState = """
{"profile": {
  "profiles_order": ["Profile 1", "Profile 15", "Profile 17", "Profile 26"],
  "info_cache": {
    "Profile 26": {"name": "kim@initech.com", "user_name": "", "gaia_given_name": ""},
    "Profile 17": {"name": "globex.io", "user_name": "sam@globex.io", "gaia_given_name": "Sam"},
    "Profile 15": {"name": "globex.io", "user_name": "alex@globex.io", "gaia_given_name": "Alex"},
    "Profile 1":  {"name": "acme.dev", "user_name": "alex@acme.dev", "gaia_given_name": "Alex"},
    "Profile 9":  {"name": "Work", "user_name": "alex@acme.dev", "gaia_given_name": "Alex"}
  }
}, "other": 1}
"""

func catalog() throws -> ProfileCatalog {
    try ProfileCatalog.parse(localState: Data(localState.utf8))
}

func site(_ name: String = "s", account: String? = nil, profile: String? = nil, open: String = "https://x.com/", match: [String] = ["x.com/"]) -> Site {
    Site(name: name, account: account, profile: profile, open: URL(string: open)!, match: match)
}

@Suite struct ProfileTests {
    @Test func parsesInChromeOrderThenByFolder() throws {
        let c = try catalog()
        #expect(c.profiles.map(\.directory) == ["Profile 1", "Profile 15", "Profile 17", "Profile 26", "Profile 9"])
    }

    @Test func windowLabels() throws {
        let c = try catalog()
        #expect(c.profile(directory: "Profile 1")?.windowLabel == "Alex (acme.dev)")
        #expect(c.profile(directory: "Profile 15")?.windowLabel == "Alex (globex.io)")
        #expect(c.profile(directory: "Profile 17")?.windowLabel == "Sam (globex.io)")
        #expect(c.profile(directory: "Profile 26")?.windowLabel == "kim@initech.com")
    }

    @Test func refusesBadLocalState() {
        #expect(throws: ProfileCatalog.ParseError.notJSON) { try ProfileCatalog.parse(localState: Data("nope".utf8)) }
        #expect(throws: ProfileCatalog.ParseError.noProfiles) { try ProfileCatalog.parse(localState: Data("{}".utf8)) }
        #expect(throws: ProfileCatalog.ParseError.noProfiles) {
            try ProfileCatalog.parse(localState: Data(#"{"profile": {"info_cache": {}}}"#.utf8))
        }
    }

    @Test func accountLookupTriesEmailThenName() throws {
        let c = try catalog()
        #expect(try c.profile(account: "Sam@Globex.io").directory == "Profile 17")
        #expect(try c.profile(account: "kim@initech.com").directory == "Profile 26")
        #expect(try c.profile(account: "acme.dev").directory == "Profile 1")
        #expect(throws: ProfileCatalog.LookupError.ambiguous(account: "globex.io", directories: ["Profile 15", "Profile 17"])) {
            try c.profile(account: "globex.io")
        }
        #expect(throws: ProfileCatalog.LookupError.ambiguous(account: "alex@acme.dev", directories: ["Profile 1", "Profile 9"])) {
            try c.profile(account: "alex@acme.dev")
        }
        let error = #expect(throws: ProfileCatalog.LookupError.self) { try c.profile(account: "nobody@x.com") }
        #expect(error?.description.contains("kim@initech.com") == true)
    }

    @Test func resolvesByAccountOrProfile() throws {
        let c = try catalog()
        let byAccount = try Resolver.resolve(site(account: "sam@globex.io"), in: c)
        #expect(byAccount.profile.directory == "Profile 17")
        #expect(byAccount.label == "Sam (globex.io)")
        #expect(byAccount.canFocus)

        let byProfile = try Resolver.resolve(site(account: "alex@acme.dev", profile: "Profile 9"), in: c)
        #expect(byProfile.profile.directory == "Profile 9")

        #expect(throws: ResolveError.accountMismatch(account: "sam@globex.io", directory: "Profile 9")) {
            try Resolver.resolve(site(account: "sam@globex.io", profile: "Profile 9"), in: c)
        }
        #expect(throws: ResolveError.self) { try Resolver.resolve(site(profile: "Profile 99"), in: c) }
        #expect(throws: ResolveError.self) { try Resolver.resolve(site(account: "globex.io"), in: c) }
    }

    @Test func sharedLabelDisablesFocus() throws {
        let c = ProfileCatalog(profiles: [
            ChromeProfile(directory: "A", name: "Work", email: "", givenName: ""),
            ChromeProfile(directory: "B", name: "Work", email: "", givenName: ""),
            ChromeProfile(directory: "C", name: "Home", email: "", givenName: ""),
        ])
        let a = try Resolver.resolve(site(profile: "A"), in: c)
        #expect(!a.canFocus)
        #expect(a.sharedLabelWith.map(\.directory) == ["B"])
        #expect(try Resolver.resolve(site(profile: "C"), in: c).canFocus)
    }

    /// The one profile parsed from an info_cache entry written as JSON.
    private func picture(_ entry: String) throws -> ProfilePicture {
        let json = #"{"profile": {"info_cache": {"Profile 1": "# + entry + "}}}"
        return try #require(ProfileCatalog.parse(localState: Data(json.utf8)).profiles.first).picture
    }

    @Test func picturesByChromesRule() throws {
        let colours = #""default_avatar_fill_color": -14410706, "default_avatar_stroke_color": -3161638"#
        let fill = UInt32(bitPattern: -14410706)
        let outline = UInt32(bitPattern: -3161638)
        // Signed in, on the default avatar: Chrome shows the Google picture.
        #expect(try picture(#"{"name": "a", "gaia_picture_file_name": "Google Profile Picture.png", "is_using_default_avatar": true, "#
            + colours + "}") == ProfilePicture(file: "Google Profile Picture.png", fill: fill, outline: outline))
        // Asked for outright.
        #expect(try picture(#"{"name": "a", "gaia_picture_file_name": "Google Profile Picture.png", "is_using_default_avatar": false, "use_gaia_picture": true}"#)
            == ProfilePicture(file: "Google Profile Picture.png"))
        // Explicitly not asked for, on the default avatar: still shown, as unset is.
        #expect(try picture(#"{"name": "a", "gaia_picture_file_name": "p.png", "is_using_default_avatar": true, "use_gaia_picture": false}"#)
            == ProfilePicture(file: "p.png"))
        // No account: no file, only the colours.
        #expect(try picture(#"{"name": "a", "is_using_default_avatar": true, "# + colours + "}")
            == ProfilePicture(fill: fill, outline: outline))
        // A chosen built-in avatar: Chrome draws it from its own resources, so the outline here.
        #expect(try picture(#"{"name": "a", "gaia_picture_file_name": "p.png", "is_using_default_avatar": false, "use_gaia_picture": false}"#)
            == ProfilePicture())
        // An entry without picture keys is what a profile built by hand has.
        #expect(try picture(#"{"name": "a"}"#) == ProfilePicture())
    }

    @Test(arguments: ["../p.png", "a/p.png", "..", ".", ""])
    func pictureFileIsAPlainName(name: String) throws {
        #expect(try picture(#"{"name": "a", "is_using_default_avatar": true, "gaia_picture_file_name": ""# + name + #""}"#).file == nil)
    }

    @Test func pictureColoursOutsideThirtyTwoBitsAreDropped() throws {
        #expect(try picture(#"{"name": "a", "default_avatar_fill_color": 4294967296, "default_avatar_stroke_color": "red"}"#) == ProfilePicture())
    }

    @Test(arguments: [
        ("https://www.github.com/x", "github.com/x"),
        ("http://claude.ai/new", "claude.ai/new"),
        ("https://", "https://"),
        ("chrome://newtab/", "chrome://newtab/"),
        ("www.", "www."),
    ])
    func bareURLs(url: String, bare: String) {
        #expect(URLPrefix.bare(url) == bare)
    }

    @Test func linkParsing() throws {
        #expect(try Link.parse(URL(string: "capsjump://github")!) == .site("github"))
        #expect(try Link.parse(URL(string: "CAPSJUMP://GitHub/")!) == .site("github"))
        #expect(try Link.parse(Link.setupURL) == .setup)
        #expect(try Link.parse(Link.pauseURL) == .pause)
        #expect(try Link.parse(Link.resumeURL) == .resume)
        #expect(throws: Link.ParseError.unknownAction("_x")) { try Link.parse(URL(string: "capsjump://_x")!) }
        #expect(throws: Link.ParseError.self) { try Link.parse(URL(string: "tabjump://github")!) }
        #expect(throws: Link.ParseError.self) { try Link.parse(URL(string: "capsjump:")!) }
    }
}
