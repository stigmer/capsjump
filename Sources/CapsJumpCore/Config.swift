// The config file, ~/.capsjump.yaml: one entry per site, naming the link
// (capsjump://<name>), the Chrome account it lives in, the page to open and the URL
// prefixes that count as already open. Parsing walks the YAML tree itself rather than
// decoding with Codable, because Codable ignores unknown keys and a typo such as `acount:`
// must be refused, not dropped. Every problem in the file is reported at once.

import Foundation
import Yams

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

    public init(sites: [Site]) {
        self.sites = sites
    }

    public func site(named name: String) -> Site? {
        sites.first { $0.name == name }
    }
}

public struct ConfigError: Error, Equatable, CustomStringConvertible {
    /// One line per problem, each naming where it is.
    public let problems: [String]

    public var description: String {
        problems.joined(separator: "\n")
    }
}

public enum ConfigParser {
    static let topLevelKeys: Set<String> = ["sites"]
    static let siteKeys: Set<String> = ["name", "account", "profile", "open", "match"]

    /// Parses and validates the whole file, throwing every problem it finds at once.
    public static func parse(_ yaml: String) throws(ConfigError) -> Config {
        let root: Node?
        do {
            root = try Yams.compose(yaml: yaml)
        } catch {
            throw ConfigError(problems: ["not valid YAML: \(error)"])
        }
        guard let root else {
            throw ConfigError(problems: ["the file is empty; it needs a `sites:` list"])
        }
        guard let top = root.mapping else {
            throw ConfigError(problems: ["the file must be a mapping with a `sites:` list"])
        }

        var problems: [String] = []
        problems += unknownKeys(in: top, allowed: topLevelKeys, at: "the file")
        guard let sitesNode = top["sites"] else {
            throw ConfigError(problems: problems + ["the file has no `sites:` list"])
        }
        guard let sequence = sitesNode.sequence else {
            throw ConfigError(problems: problems + ["\(at(sitesNode))`sites` must be a list"])
        }

        var sites: [Site] = []
        var seen: [String: Int] = [:]
        for (index, node) in sequence.enumerated() {
            let (site, siteProblems) = parseSite(node, index: index)
            problems += siteProblems
            guard let site else { continue }
            if let first = seen[site.name] {
                problems.append("\(at(node))sites[\(index)]: name `\(site.name)` is already used by sites[\(first)]")
                continue
            }
            seen[site.name] = index
            sites.append(site)
        }
        guard problems.isEmpty else { throw ConfigError(problems: problems) }
        return Config(sites: sites)
    }

    private static func parseSite(_ node: Node, index: Int) -> (Site?, [String]) {
        guard let mapping = node.mapping else {
            return (nil, ["\(at(node))sites[\(index)] must be a mapping with name, account and open"])
        }
        let name = mapping["name"]?.string
        let label = "sites[\(index)]" + (name.map { " (\($0))" } ?? "")
        var problems = unknownKeys(in: mapping, allowed: siteKeys, at: "\(at(node))\(label)")
        let where_ = "\(at(node))\(label)"

        if let name {
            if let problem = SiteName.problem(with: name) {
                problems.append("\(where_): \(problem)")
            }
        } else {
            problems.append("\(where_): `name` is missing")
        }

        let account = text(mapping, "account", where_, &problems)
        let profile = text(mapping, "profile", where_, &problems)
        if account == nil && profile == nil {
            problems.append("\(where_): give `account` (an email, or the profile's name) or `profile` (a folder such as `Profile 26`)")
        }

        var open: URL?
        if let raw = text(mapping, "open", where_, &problems) {
            open = httpURL(raw)
            if open == nil {
                problems.append("\(where_): `open` must be an http or https URL, not `\(raw)`")
            }
        } else if mapping["open"] == nil {
            problems.append("\(where_): `open` is missing")
        }

        var match: [String] = []
        if let matchNode = mapping["match"] {
            if let items = matchNode.sequence {
                for item in items {
                    guard let prefix = item.string, !prefix.isEmpty, item.scalar != nil else {
                        problems.append("\(where_): every `match` entry must be a non-empty text")
                        continue
                    }
                    if prefix.contains("://") {
                        problems.append("\(where_): `match` entry `\(prefix)` must not carry a scheme; write it as `\(URLPrefix.bare(prefix))`")
                        continue
                    }
                    match.append(prefix)
                }
                if items.isEmpty {
                    problems.append("\(where_): `match` is empty; leave it out to match the open URL's host")
                }
            } else {
                problems.append("\(where_): `match` must be a list")
            }
        } else if let open {
            match = [URLPrefix.defaultMatch(for: open)]
        }

        guard problems.isEmpty, let name, let open else { return (nil, problems) }
        return (Site(name: name, account: account, profile: profile, open: open, match: match), [])
    }

    /// A text value, or nil when absent; a non-text value is a problem.
    private static func text(_ mapping: Node.Mapping, _ key: String, _ where_: String, _ problems: inout [String]) -> String? {
        guard let node = mapping[key] else { return nil }
        guard node.scalar != nil, let value = node.string, !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            problems.append("\(where_): `\(key)` must be a non-empty text")
            return nil
        }
        return value
    }

    private static func unknownKeys(in mapping: Node.Mapping, allowed: Set<String>, at place: String) -> [String] {
        mapping.keys.compactMap { key in
            let name = key.string ?? "\(key)"
            guard !allowed.contains(name) else { return nil }
            let known = allowed.sorted().map { "`\($0)`" }.joined(separator: ", ")
            return "\(place): unknown key `\(name)` (known keys: \(known))"
        }
    }

    private static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    private static func at(_ node: Node) -> String {
        node.mark.map { "line \($0.line): " } ?? ""
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
