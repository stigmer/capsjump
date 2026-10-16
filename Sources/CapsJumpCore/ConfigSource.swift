// The config as written, before any rule is applied: each site's and key's text fields,
// with the line and the place in the file each came from. Reading reports only what YAML
// alone can get wrong (the file's shape, unknown keys, a value that isn't text, a key
// given two actions) and never stops at one, so every problem in the file is found at
// once. Every other rule lives in `ConfigRules`, which the editing window uses on the
// same source.

import Foundation
import Yams

public struct SiteSource: Sendable, Equatable {
    public enum Field: Int, Sendable {
        /// The entry as a whole, such as a list item that isn't a mapping.
        case entry
        case unknownKey
        case name
        case account
        case profile
        /// The rule that one of `account` and `profile` is given.
        case accountOrProfile
        case open
        case match
    }

    /// The entry's place in `sites:`.
    public var index: Int
    public var line: Int?
    public var name: String?
    public var account: String?
    public var profile: String?
    public var open: String?
    /// The prefixes as written, or nil when the file gives none, so the default follows `open`.
    public var match: [String]?

    public init(index: Int, line: Int? = nil, name: String?, account: String? = nil, profile: String? = nil, open: String?, match: [String]? = nil) {
        self.index = index
        self.line = line
        self.name = name
        self.account = account
        self.profile = profile
        self.open = open
        self.match = match
    }
}

/// An action as written: which of `app`, `site`, `window` and `url`, and its text.
public struct ActionSource: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case app
        case site
        case window
        case url
    }

    public var kind: Kind
    public var value: String

    public init(_ kind: Kind, _ value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct KeySource: Sendable, Equatable {
    public enum Field: Int, Sendable {
        case key
        /// The entry as a whole: a value that isn't a mapping.
        case entry
        case unknownKey
        case action
    }

    /// The entry's place in `keys:`.
    public var index: Int
    public var line: Int?
    public var key: String
    /// Nil when no action is given, or when the one given couldn't be read.
    public var action: ActionSource?

    public init(index: Int, line: Int? = nil, key: String, action: ActionSource?) {
        self.index = index
        self.line = line
        self.key = key
        self.action = action
    }
}

public struct ConfigSource: Sendable, Equatable {
    public var sites: [SiteSource]
    public var keys: [KeySource]
    /// What reading found wrong; `ConfigRules.validate` reports these with its own.
    public var problems: [Problem]

    public init(sites: [SiteSource] = [], keys: [KeySource] = [], problems: [Problem] = []) {
        self.sites = sites
        self.keys = keys
        self.problems = problems
    }
}

public enum ConfigReader {
    static let topLevelKeys: Set<String> = ["sites", "keys"]
    static let siteKeys: Set<String> = ["name", "account", "profile", "open", "match"]
    static let actionKeys: Set<String> = Set(ActionSource.Kind.allCases.map(\.rawValue))

    public static func read(_ yaml: String) -> ConfigSource {
        let root: Node?
        do {
            root = try Yams.compose(yaml: yaml)
        } catch {
            return ConfigSource(problems: [Problem(.file, "not valid YAML: \(error)")])
        }
        guard let root else {
            return ConfigSource(problems: [Problem(.file, "the file is empty; it needs a `sites:` list or a `keys:` mapping")])
        }
        guard let top = root.mapping else {
            return ConfigSource(problems: [Problem(.file, "the file must be a mapping with a `sites:` list or a `keys:` mapping")])
        }

        var source = ConfigSource()
        source.problems += unknownKeys(in: top, allowed: topLevelKeys).map { Problem(.file, "the file: \($0)") }
        let sitesNode = top["sites"]
        guard sitesNode != nil || top["keys"] != nil else {
            source.problems.append(Problem(.file, "the file has no `sites:` list and no `keys:` mapping"))
            return source
        }
        if let sitesNode, sitesNode.null == nil {
            guard let items = sitesNode.sequence else {
                source.problems.append(Problem(.file, line: line(of: sitesNode), "`sites` must be a list"))
                return source
            }
            for (index, node) in items.enumerated() {
                readSite(node, index: index, into: &source)
            }
        }

        if let keysNode = top["keys"], keysNode.null == nil {
            if let mapping = keysNode.mapping {
                for (index, (keyNode, valueNode)) in mapping.enumerated() {
                    readKey(keyNode, valueNode, index: index, into: &source)
                }
            } else {
                source.problems.append(Problem(.keys, line: line(of: keysNode), "`keys` must be a mapping of key names to actions, such as `g: { site: github }`"))
            }
        }
        return source
    }

    private static func readSite(_ node: Node, index: Int, into source: inout ConfigSource) {
        let line = line(of: node)
        guard let mapping = node.mapping else {
            source.problems.append(Problem(.site(index: index, name: nil, field: .entry), line: line, "must be a mapping with name, account and open"))
            return
        }
        let name = mapping["name"]?.string
        func problem(_ field: SiteSource.Field, _ message: String) {
            source.problems.append(Problem(.site(index: index, name: name, field: field), line: line, message))
        }
        for unknown in unknownKeys(in: mapping, allowed: siteKeys) {
            problem(.unknownKey, unknown)
        }
        func text(_ key: String, _ field: SiteSource.Field) -> String? {
            guard let node = mapping[key] else { return nil }
            guard node.scalar != nil, let value = node.string else {
                problem(field, "`\(key)` must be a non-empty text")
                return nil
            }
            return value
        }
        var site = SiteSource(index: index, line: line, name: name, account: text("account", .account), profile: text("profile", .profile), open: text("open", .open))
        if let matchNode = mapping["match"] {
            if let items = matchNode.sequence {
                site.match = items.compactMap { item in
                    guard item.scalar != nil, let prefix = item.string else {
                        problem(.match, "every `match` entry must be a non-empty text")
                        return nil
                    }
                    return prefix
                }
            } else {
                problem(.match, "`match` must be a list")
            }
        }
        source.sites.append(site)
    }

    private static func readKey(_ keyNode: Node, _ valueNode: Node, index: Int, into source: inout ConfigSource) {
        let key = keyNode.string ?? "\(keyNode)"
        let line = line(of: keyNode)
        func problem(_ field: KeySource.Field, _ message: String) {
            source.problems.append(Problem(.key(index: index, name: key, field: field), line: line, message))
        }
        var entry = KeySource(index: index, line: line, key: key, action: nil)
        defer { source.keys.append(entry) }
        guard let mapping = valueNode.mapping else {
            problem(.entry, "must be a mapping with one of app, site, window or url, such as `{ app: Safari }`")
            return
        }
        for unknown in unknownKeys(in: mapping, allowed: actionKeys) {
            problem(.unknownKey, unknown)
        }
        let given = mapping.keys.compactMap(\.string).filter(actionKeys.contains)
        guard given.count <= 1 else {
            problem(.action, "give one action, not \(given.map { "`\($0)`" }.joined(separator: " and "))")
            return
        }
        guard let name = given.first, let kind = ActionSource.Kind(rawValue: name), let node = mapping[name] else { return }
        guard node.scalar != nil, let value = node.string else {
            problem(.action, "`\(name)` must be a non-empty text")
            return
        }
        entry.action = ActionSource(kind, value)
    }

    private static func unknownKeys(in mapping: Node.Mapping, allowed: Set<String>) -> [String] {
        mapping.keys.compactMap { key in
            let name = key.string ?? "\(key)"
            guard !allowed.contains(name) else { return nil }
            let known = allowed.sorted().map { "`\($0)`" }.joined(separator: ", ")
            return "unknown key `\(name)` (known keys: \(known))"
        }
    }

    private static func line(of node: Node) -> Int? {
        node.mark?.line
    }
}
