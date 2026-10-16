// The file `capsjump init` writes: one example site, this Mac's Chrome accounts listed
// as comments so the account to type is in front of the reader, the three window keys,
// and a commented example of each other kind of key.

import Foundation

public enum StarterConfig {
    public static func render(catalog: ProfileCatalog?) -> String {
        var lines = [
            "# CapsJump: each site is a link, capsjump://<name>, that brings forward the",
            "# site's tab in its Chrome account or opens the site there.",
            "#",
            "#   name     the link's name: lower-case letters, digits and hyphens",
            "#   account  the account's email, or the profile's name when no account is signed in",
            "#   profile  instead of account, a profile folder such as `Profile 26`",
            "#   open     the page to open when no tab matches",
            "#   match    optional: URL prefixes without the scheme, most specific first;",
            "#            defaults to the open URL's host, e.g. github.com/",
            "#",
            "# Under `keys:`, hold Caps Lock and press a key: a-z, 0-9, f1-f12, left, right,",
            "# up or down. Each key does one thing:",
            "#   app      an app's name, or a path to an .app",
            "#   site     one of the sites below",
            "#   window   left-half, right-half or maximize",
            "#   url      any link: a web page, or a deep link such as slack://",
            "#",
            "# Edits apply as soon as the file is saved; `capsjump check` validates it.",
        ]
        if let catalog {
            lines.append("#")
            lines.append("# Chrome accounts on this Mac (account, then profile folder):")
            for profile in catalog.profiles {
                let account = profile.email.isEmpty ? profile.name : profile.email
                lines.append("#   \(account)  (\(profile.directory))")
            }
        }
        let account = catalog?.profiles.first.map { $0.email.isEmpty ? $0.name : $0.email } ?? "you@example.com"
        lines += [
            "",
            "sites:",
            "  - name: github",
            "    account: \(account)",
            "    open: https://github.com/",
            "",
            "keys:",
            "  left: { window: left-half }",
            "  right: { window: right-half }",
            "  f: { window: maximize }",
            "  # g: { site: github }",
            "  # t: { app: Terminal }",
            "  # w: { url: \"https://example.com\" }",
            "",
        ]
        return lines.joined(separator: "\n")
    }
}
