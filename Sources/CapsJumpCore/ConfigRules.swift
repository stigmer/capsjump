// Every rule a config must meet beyond being readable YAML, applied to a `ConfigSource`:
// each field's (site names, the open URL, `match` and its default, key names, apps, window
// positions, links) and those across entries (an account or profile, a site name used
// twice, a key bound twice, a key naming no site). The file and the editing window both
// come here, so they refuse the same things with the same words. A problem holds its place
// and its bare message; `description` adds the place the way `capsjump check` prints it.

import Foundation

public struct Problem: Sendable, Equatable, CustomStringConvertible {
    public enum Place: Sendable, Equatable {
        /// The file as a whole; its messages carry their own wording of where.
        case file
        case site(index: Int, name: String?, field: SiteSource.Field)
        /// The `keys:` mapping as a whole.
        case keys
        case key(index: Int, name: String, field: KeySource.Field)
    }

    public let place: Place
    public let line: Int?
    public let message: String

    public init(_ place: Place, line: Int? = nil, _ message: String) {
        self.place = place
        self.line = line
        self.message = message
    }

    public var description: String {
        let at = line.map { "line \($0): " } ?? ""
        switch place {
        case .file, .keys:
            return at + message
        case let .site(index, name, field):
            let label = "sites[\(index)]" + (name.map { " (\($0))" } ?? "")
            return at + label + (field == .entry ? " " : ": ") + message
        case let .key(_, name, field):
            return at + "keys.\(name)" + (field == .entry ? " " : ": ") + message
        }
    }

    /// File order: the file, then each site, then `keys:`, then each key; within an entry,
    /// by field.
    fileprivate var order: (Int, Int, Int) {
        switch place {
        case .file: (0, 0, 0)
        case let .site(index, _, field): (1, index, field.rawValue)
        case .keys: (2, 0, 0)
        case let .key(index, _, field): (3, index, field.rawValue)
        }
    }
}

public enum ConfigRules {
    /// The config the source describes, or every problem in it, reading's included, in file order.
    public static func validate(_ source: ConfigSource) -> Result<Config, ConfigError> {
        var problems = source.problems
        var sites: [Site] = []
        var seen: [String: Int] = [:]
        for entry in source.sites {
            let (site, found) = validate(entry, readProblems: source.problems)
            problems += found
            guard let site, !hasProblem(source.problems, site: entry.index) else { continue }
            if let first = seen[site.name] {
                problems.append(Problem(.site(index: entry.index, name: nil, field: .name), line: entry.line, "name `\(site.name)` is already used by sites[\(first)]"))
                continue
            }
            seen[site.name] = entry.index
            sites.append(site)
        }

        // Every name the source gives a site, valid or not, so a key naming a site with its
        // own problem isn't reported a second time as naming no site.
        let siteNames = Set(source.sites.compactMap(\.name))
        var keys: [KeyBinding] = []
        var bound: Set<String> = []
        for entry in source.keys {
            let (binding, found) = validate(entry, siteNames: siteNames, readProblems: source.problems)
            problems += found
            if !bound.insert(entry.key).inserted {
                problems.append(Problem(.key(index: entry.index, name: entry.key, field: .key), line: entry.line, "`\(entry.key)` is bound twice"))
                continue
            }
            if let binding, !hasProblem(source.problems, key: entry.index) {
                keys.append(binding)
            }
        }

        guard problems.isEmpty else {
            let ordered = problems.enumerated().sorted { a, b in
                a.element.order != b.element.order ? a.element.order < b.element.order : a.offset < b.offset
            }
            return .failure(ConfigError(found: ordered.map(\.element)))
        }
        return .success(Config(sites: sites, keys: keys))
    }

    /// One site, or the problems with its fields; the rules across sites are `validate`'s.
    static func validate(_ entry: SiteSource, readProblems: [Problem]) -> (Site?, [Problem]) {
        var problems: [Problem] = []
        func problem(_ field: SiteSource.Field, _ message: String) {
            problems.append(Problem(.site(index: entry.index, name: entry.name, field: field), line: entry.line, message))
        }
        let unreadable = Set(readProblems.compactMap { problem -> SiteSource.Field? in
            guard case let .site(index, _, field) = problem.place, index == entry.index else { return nil }
            return field
        })

        if let name = entry.name {
            if let message = SiteName.problem(with: name) {
                problem(.name, message)
            }
        } else {
            problem(.name, "`name` is missing")
        }

        let account = text(entry.account, "account") { problem(.account, $0) }
        let profile = text(entry.profile, "profile") { problem(.profile, $0) }
        if account == nil && profile == nil {
            problem(.accountOrProfile, "give `account` (an email, or the profile's name) or `profile` (a folder such as `Profile 26`)")
        }

        var open: URL?
        if let raw = text(entry.open, "open", { problem(.open, $0) }) {
            open = httpURL(raw)
            if open == nil {
                problem(.open, "`open` must be an http or https URL, not `\(raw)`")
            }
        } else if entry.open == nil, !unreadable.contains(.open) {
            problem(.open, "`open` is missing")
        }

        var match: [String] = []
        if let given = entry.match {
            for prefix in given {
                if prefix.isEmpty {
                    problem(.match, "every `match` entry must be a non-empty text")
                } else if prefix.contains("://") {
                    problem(.match, "`match` entry `\(prefix)` must not carry a scheme; write it as `\(URLPrefix.bare(prefix))`")
                } else {
                    match.append(prefix)
                }
            }
            if given.isEmpty, !unreadable.contains(.match) {
                problem(.match, "`match` is empty; leave it out to match the open URL's host")
            }
        } else if let open {
            match = [URLPrefix.defaultMatch(for: open)]
        }

        guard problems.isEmpty, let name = entry.name, let open else { return (nil, problems) }
        return (Site(name: name, account: account, profile: profile, open: open, match: match), [])
    }

    /// One key, or the problems with it; a key bound twice is `validate`'s.
    static func validate(_ entry: KeySource, siteNames: Set<String>, readProblems: [Problem]) -> (KeyBinding?, [Problem]) {
        var problems: [Problem] = []
        func problem(_ field: KeySource.Field, _ message: String) {
            problems.append(Problem(.key(index: entry.index, name: entry.key, field: field), line: entry.line, message))
        }
        if KeyNames.triggers(for: entry.key) == nil {
            problem(.key, "unknown key name `\(entry.key)` (key names: a–z, 0–9, f1–f12, left, right, up, down)")
        }
        guard let given = entry.action else {
            let unreadable = readProblems.contains { problem in
                guard case let .key(index, _, field) = problem.place else { return false }
                return index == entry.index && (field == .entry || field == .action)
            }
            if !unreadable {
                problem(.action, "give one of `app`, `site`, `window` or `url`")
            }
            return (nil, problems)
        }
        guard let raw = text(given.value, given.kind.rawValue, { problem(.action, $0) }) else { return (nil, problems) }

        var action: KeyAction?
        switch given.kind {
        case .app:
            if let target = AppTarget.parse(raw) {
                action = .app(target)
            } else {
                problem(.action, "`app` must be an app's name, such as `Safari`, or a path to an .app that starts with `/` or `~/`, not `\(raw)`")
            }
        case .site:
            if siteNames.contains(raw) {
                action = .site(raw)
            } else {
                problem(.action, "no site named `\(raw)` in `sites:`")
            }
        case .window:
            if let position = WindowPosition(rawValue: raw) {
                action = .window(position)
            } else {
                let known = WindowPosition.allCases.map { "`\($0.rawValue)`" }.joined(separator: ", ")
                problem(.action, "`window` must be one of \(known), not `\(raw)`")
            }
        case .url:
            if let url = linkURL(raw) {
                action = .url(url)
            } else {
                problem(.action, "`url` must be a link with a scheme, such as `https://example.com` or `slack://open`, not `\(raw)`")
            }
        }
        guard problems.isEmpty, let action else { return (nil, problems) }
        return (KeyBinding(key: entry.key, action: action), [])
    }

    /// A value that is given and not blank, or nil; a blank one is a problem.
    private static func text(_ value: String?, _ key: String, _ problem: (String) -> Void) -> String? {
        guard let value else { return nil }
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            problem("`\(key)` must be a non-empty text")
            return nil
        }
        return value
    }

    private static func hasProblem(_ problems: [Problem], site index: Int) -> Bool {
        problems.contains { if case .site(index, _, _) = $0.place { true } else { false } }
    }

    private static func hasProblem(_ problems: [Problem], key index: Int) -> Bool {
        problems.contains { if case .key(index, _, _) = $0.place { true } else { false } }
    }

    /// Any link with a scheme: a web page, or a deep link such as `slack://channel?…`.
    public static func linkURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty,
              raw.hasPrefix(scheme + ":"), raw.count > scheme.count + 1
        else { return nil }
        return url
    }

    public static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
