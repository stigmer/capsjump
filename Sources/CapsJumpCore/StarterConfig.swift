// The file `capsjump init` writes: one commented example site, and this Mac's Chrome
// accounts listed as comments so the account to type is in front of the reader.

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
            "# This file is read on every jump; `capsjump check` validates it.",
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
        ]
        return lines.joined(separator: "\n")
    }
}
