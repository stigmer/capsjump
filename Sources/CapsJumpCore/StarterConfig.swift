// The file `capsjump init` writes, and the editing window starts from when there is none:
// one example site in this Mac's first Chrome account and the three window keys, written
// as CapsJump writes every file, so a first save from the window loses nothing.

import Foundation

public enum StarterConfig {
    public static func config(catalog: ProfileCatalog?) -> Config {
        let first = catalog.flatMap { catalog in catalog.profiles.first.map { SiteAccount.fields(for: $0, in: catalog) } }
        let (account, profile) = first ?? ("you@example.com", nil)
        let open = URL(string: "https://github.com/")!
        return Config(
            sites: [Site(name: "github", account: account, profile: profile, open: open, match: [URLPrefix.defaultMatch(for: open)])],
            keys: [
                KeyBinding(key: "left", action: .window(.leftHalf)),
                KeyBinding(key: "right", action: .window(.rightHalf)),
                KeyBinding(key: "f", action: .window(.maximize)),
            ]
        )
    }

    public static func render(catalog: ProfileCatalog?) -> String {
        ConfigWriter.render(config(catalog: catalog))
    }
}
