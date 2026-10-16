// The config file, ~/.capsjump.yaml. `sites:` holds one entry per site, naming the link
// (capsjump://<name>), the Chrome account it lives in, the page to open and the URL
// prefixes that count as already open. `keys:` binds Caps Lock + a key to one action.
// Parsing walks the YAML tree itself rather than decoding with Codable, because Codable
// ignores unknown keys and a typo such as `acount:` must be refused, not dropped. Every
// problem in the file is reported at once.

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
    /// One line per problem, each naming where it is.
    public let problems: [String]

    public var description: String {
        problems.joined(separator: "\n")
    }
}

public enum ConfigParser {
    static let topLevelKeys: Set<String> = ["sites", "keys"]
    static let siteKeys: Set<String> = ["name", "account", "profile", "open", "match"]
    static let actionKeys: Set<String> = ["app", "site", "window", "url"]

    /// Parses and validates the whole file, throwing every problem it finds at once.
    public static func parse(_ yaml: String) throws(ConfigError) -> Config {
        let root: Node?
        do {
            root = try Yams.compose(yaml: yaml)
        } catch {
            throw ConfigError(problems: ["not valid YAML: \(error)"])
        }
        guard let root else {
            throw ConfigError(problems: ["the file is empty; it needs a `sites:` list or a `keys:` mapping"])
        }
        guard let top = root.mapping else {
            throw ConfigError(problems: ["the file must be a mapping with a `sites:` list or a `keys:` mapping"])
        }

        var problems: [String] = []
        problems += unknownKeys(in: top, allowed: topLevelKeys, at: "the file")
        let sitesNode = top["sites"]
        guard sitesNode != nil || top["keys"] != nil else {
            throw ConfigError(problems: problems + ["the file has no `sites:` list and no `keys:` mapping"])
        }
        let sequence: [Node]
        if let sitesNode, sitesNode.null == nil {
            guard let items = sitesNode.sequence else {
                throw ConfigError(problems: problems + ["\(at(sitesNode))`sites` must be a list"])
            }
            sequence = Array(items)
        } else {
            sequence = []
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

        // Every name the file gives a site, valid or not, so a key naming a site with its own
        // problem isn't reported a second time as naming no site.
        let siteNames = Set(sequence.compactMap { $0.mapping?["name"]?.string })
        var keys: [KeyBinding] = []
        if let keysNode = top["keys"], keysNode.null == nil {
            if let mapping = keysNode.mapping {
                for (keyNode, valueNode) in mapping {
                    let (binding, keyProblems) = parseKey(keyNode, valueNode, siteNames: siteNames)
                    problems += keyProblems
                    if let binding { keys.append(binding) }
                }
            } else {
                problems.append("\(at(keysNode))`keys` must be a mapping of key names to actions, such as `g: { site: github }`")
            }
        }

        guard problems.isEmpty else { throw ConfigError(problems: problems) }
        return Config(sites: sites, keys: keys)
    }

    private static func parseKey(_ keyNode: Node, _ valueNode: Node, siteNames: Set<String>) -> (KeyBinding?, [String]) {
        let name = keyNode.string ?? "\(keyNode)"
        let where_ = "\(at(keyNode))keys.\(name)"
        var problems: [String] = []
        if KeyNames.triggers(for: name) == nil {
            problems.append("\(where_): unknown key name `\(name)` (key names: a–z, 0–9, f1–f12, left, right, up, down)")
        }
        guard let mapping = valueNode.mapping else {
            return (nil, problems + ["\(where_) must be a mapping with one of app, site, window or url, such as `{ app: Safari }`"])
        }
        problems += unknownKeys(in: mapping, allowed: actionKeys, at: where_)
        let given = mapping.keys.compactMap(\.string).filter(actionKeys.contains)
        guard given.count == 1, let kind = given.first else {
            if given.isEmpty {
                problems.append("\(where_): give one of `app`, `site`, `window` or `url`")
            } else {
                problems.append("\(where_): give one action, not \(given.map { "`\($0)`" }.joined(separator: " and "))")
            }
            return (nil, problems)
        }
        guard let raw = text(mapping, kind, where_, &problems) else { return (nil, problems) }

        var action: KeyAction?
        switch kind {
        case "app":
            if let target = AppTarget.parse(raw) {
                action = .app(target)
            } else {
                problems.append("\(where_): `app` must be an app's name, such as `Safari`, or a path to an .app that starts with `/` or `~/`, not `\(raw)`")
            }
        case "site":
            if siteNames.contains(raw) {
                action = .site(raw)
            } else {
                problems.append("\(where_): no site named `\(raw)` in `sites:`")
            }
        case "window":
            if let position = WindowPosition(rawValue: raw) {
                action = .window(position)
            } else {
                let known = WindowPosition.allCases.map { "`\($0.rawValue)`" }.joined(separator: ", ")
                problems.append("\(where_): `window` must be one of \(known), not `\(raw)`")
            }
        default:
            if let url = linkURL(raw) {
                action = .url(url)
            } else {
                problems.append("\(where_): `url` must be a link with a scheme, such as `https://example.com` or `slack://open`, not `\(raw)`")
            }
        }
        guard problems.isEmpty, let action else { return (nil, problems) }
        return (KeyBinding(key: name, action: action), [])
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

    /// Any link with a scheme: a web page, or a deep link such as `slack://channel?…`.
    private static func linkURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty,
              raw.hasPrefix(scheme + ":"), raw.count > scheme.count + 1
        else { return nil }
        return url
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
