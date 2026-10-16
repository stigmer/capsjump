// The config file, ~/.capsjump.yaml. `sites:` holds one entry per site, naming the link
// (capsjump://<name>), the Chrome account it lives in, the page to open and the URL
// prefixes that count as already open. `keys:` binds Caps Lock + a key to one action.
// Parsing reads the YAML tree itself (`ConfigReader`) rather than decoding with Codable,
// because Codable ignores unknown keys and a typo such as `acount:` must be refused, not
// dropped; then `ConfigRules` applies every other rule. Every problem in the file is
// reported at once.

import Foundation

public struct Site: Sendable, Equatable {
    /// The link's host: `capsjump://<name>`.
    public let name: String
    /// An account email, or a profile's name when it has no signed-in account.
    public let account: String?
    /// A profile folder (`Profile 26`), for an account two profiles share.
    public let profile: String?
    /// The http(s) page opened when no matching tab exists.
    public let open: URL
    /// Scheme-less URL prefixes, most specific first, that count as the site being open.
    public let match: [String]

    public init(name: String, account: String?, profile: String?, open: URL, match: [String]) {
        self.name = name
        self.account = account
        self.profile = profile
        self.open = open
        self.match = match
    }
}

public struct Config: Sendable, Equatable {
    public let sites: [Site]
    /// In file order.
    public let keys: [KeyBinding]

    public init(sites: [Site], keys: [KeyBinding] = []) {
        self.sites = sites
        self.keys = keys
    }

    public func site(named name: String) -> Site? {
        sites.first { $0.name == name }
    }

    /// Whether CapsJump takes Caps Lock: only when a key is bound, so a file without
    /// `keys:` leaves Caps Lock as it was.
    public var takesCapsLock: Bool {
        !keys.isEmpty
    }
}

public struct ConfigError: Error, Equatable, CustomStringConvertible {
    /// Every problem, in file order, each with its place.
    public let found: [Problem]

    public init(found: [Problem]) {
        self.found = found
    }

    /// One line per problem, each naming where it is.
    public var problems: [String] {
        found.map(\.description)
    }

    public var description: String {
        problems.joined(separator: "\n")
    }
}

public enum ConfigParser {
    /// Reads and validates the whole file, throwing every problem it finds at once.
    public static func parse(_ yaml: String) throws(ConfigError) -> Config {
        try ConfigRules.validate(ConfigReader.read(yaml)).get()
    }
}

public enum SiteName {
    /// Why a name can't be a site's, or nil when it can. Names are link hosts, so they
    /// keep to lower-case letters, digits and inner hyphens; `_` is reserved for the
    /// app's own actions (`capsjump://_setup`).
    public static func problem(with name: String) -> String? {
        if name.hasPrefix("_") {
            return "name `\(name)` starts with `_`, which is reserved for CapsJump's own actions"
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !name.isEmpty, name.allSatisfy(allowed.contains), name.first != "-", name.last != "-" else {
            return "name `\(name)` may use only lower-case letters, digits and inner hyphens"
        }
        return nil
    }
}
