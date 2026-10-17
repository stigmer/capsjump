// The file `capsjump init` writes, the Welcome window turns on, and the editing window
// starts from when there is none: a key for each window move and, when Chrome's accounts can
// be read, one example site in this Mac's first account (never a made-up one, which would
// be the new file's first problem), written as CapsJump writes every file, so a first save
// from the window loses nothing.

import Foundation

public enum StarterConfig {
    public static func config(catalog: ProfileCatalog?) -> Config {
        let keys = WindowPosition.allCases.map { KeyBinding(key: $0.suggestedKey, action: .window($0)) }
        guard let catalog, let first = catalog.profiles.first else { return Config(sites: [], keys: keys) }
        let (account, profile) = SiteAccount.fields(for: first, in: catalog)
        let open = URL(string: "https://github.com/")!
        return Config(
            sites: [Site(name: "github", account: account, profile: profile, open: open, match: [URLPrefix.defaultMatch(for: open)])],
            keys: keys
        )
    }

    public static func render(catalog: ProfileCatalog?) -> String {
        ConfigWriter.render(config(catalog: catalog))
    }
}
