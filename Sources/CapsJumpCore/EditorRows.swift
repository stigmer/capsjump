// How the config window lists a draft: each key and site as one line of text, which lines a
// search keeps, and the order keys are listed in. A key reads like the key itself: its
// symbol, then what it does in a word or two (the app, the site and its account, "Left
// half", the link's host). Keys are listed in `KeyNames.all` order, which is how one looks
// for a key; sites keep the file's order, which can matter among sites that match the same
// page. The order shown never changes the order written.

import Foundation

public enum EditorRows {
    public struct KeyLine: Sendable, Equatable, Identifiable {
        public let id: Int
        /// The key's name, as `KeyNames` knows it: `g`, `f1`, `left`.
        public let key: String
        public let symbol: String
        public let kind: ActionSource.Kind?
        /// For an app key, the app's name or path as written; the window finds its icon by it.
        public let app: String?
        public let window: WindowPosition?
        public let title: String
        public let subtitle: String?
        /// What VoiceOver reads for the whole line.
        public let spoken: String
        let searched: [String]
    }

    public struct SiteLine: Sendable, Equatable, Identifiable {
        public let id: Int
        public let name: String
        public let account: String?
        public let host: String?
        /// The keys that jump to the site, in `KeyNames.all` order.
        public let keys: [String]
        public let spoken: String
        let searched: [String]
    }

    /// The draft's keys that match `query`, in `KeyNames.all` order.
    public static func keys(_ draft: ConfigDraft, matching query: String = "") -> [KeyLine] {
        let words = words(query)
        return draft.keys
            .map { key($0, in: draft) }
            .filter { matches(words, $0.searched) }
            .sorted { rank($0.key) < rank($1.key) }
    }

    /// The draft's sites that match `query`, in the file's order.
    public static func sites(_ draft: ConfigDraft, matching query: String = "") -> [SiteLine] {
        let words = words(query)
        return draft.sites
            .map { site($0, in: draft) }
            .filter { matches(words, $0.searched) }
    }

    public static func key(_ row: ConfigDraft.KeyRow, in draft: ConfigDraft) -> KeyLine {
        let name = row.key.key
        let symbol = KeyNames.symbol(for: name)
        let action = row.key.action
        var title = "Does nothing yet"
        var subtitle: String?
        var doing = "does nothing yet"
        var app: String?
        var window: WindowPosition?
        if let action {
            let value = action.value.trimmingCharacters(in: .whitespaces)
            switch action.kind {
            case .app:
                app = value
                switch AppTarget.parse(value) {
                case let .name(name)?:
                    title = name
                case let .path(path)?:
                    title = appName(path)
                    subtitle = path
                case nil:
                    title = value.isEmpty ? "Choose an app" : value
                }
                doing = value.isEmpty ? "has no app yet" : "brings \(title) forward"
            case .site:
                title = value.isEmpty ? "Choose a site" : value
                let site = draft.sites.first { $0.site.name == value }?.site
                subtitle = site.flatMap { account(of: $0) }
                doing = value.isEmpty ? "has no site yet" : "jumps to \(title)" + (subtitle.map { ", \($0)" } ?? "")
            case .window:
                let position = WindowPosition(rawValue: value)
                window = position
                title = position.map(positionTitle) ?? (value.isEmpty ? "Choose a position" : value)
                doing = "moves the front window to " + (position.map(positionSpoken) ?? title)
            case .url:
                if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host, !host.isEmpty {
                    title = host
                    subtitle = value
                } else {
                    title = value.isEmpty ? "Give the link" : value
                }
                doing = value.isEmpty ? "has no link yet" : "opens \(title)"
            }
        }
        return KeyLine(
            id: row.id,
            key: name,
            symbol: symbol,
            kind: action?.kind,
            app: app,
            window: window,
            title: title,
            subtitle: subtitle,
            spoken: "Caps Lock plus \(spokenKey(name)), \(doing)",
            searched: [name, symbol, title, subtitle ?? ""]
        )
    }

    public static func site(_ row: ConfigDraft.SiteRow, in draft: ConfigDraft) -> SiteLine {
        let name = row.site.name.flatMap { $0.isEmpty ? nil : $0 }
        let account = account(of: row.site)
        let host = row.site.open.flatMap { URL(string: $0)?.host }
        let keys = draft.keysUsing(row.id).sorted { rank($0) < rank($1) }
        let spokenKeys = keys.isEmpty ? [] : ["Caps Lock plus " + keys.map(spokenKey).joined(separator: " or ")]
        return SiteLine(
            id: row.id,
            name: name ?? "Unnamed site",
            account: account,
            host: host,
            keys: keys,
            spoken: ([name ?? "Unnamed site", account, host].compactMap { $0 } + spokenKeys).joined(separator: ", "),
            searched: [name ?? "", account ?? "", row.site.profile ?? "", host ?? "", row.site.open ?? ""] + keys.map(KeyNames.symbol(for:))
        )
    }

    /// A key's place in `KeyNames.all`; a name it doesn't know sorts after every known one.
    static func rank(_ key: String) -> (Int, String) {
        (order[key] ?? KeyNames.all.count, key)
    }

    private static let order = Dictionary(uniqueKeysWithValues: KeyNames.all.enumerated().map { ($1, $0) })

    /// Every word of the query is found in one field or another, ignoring case and accents.
    static func matches(_ words: [String], _ fields: [String]) -> Bool {
        guard !words.isEmpty else { return true }
        let fields = fields.map(fold)
        return words.allSatisfy { word in fields.contains { $0.contains(word) } }
    }

    private static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func account(of site: SiteSource) -> String? {
        [site.account, site.profile].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    private static func appName(_ path: String) -> String {
        let file = path.split(separator: "/").last.map(String.init) ?? path
        return file.hasSuffix(".app") ? String(file.dropLast(4)) : file
    }

    private static func positionTitle(_ position: WindowPosition) -> String {
        switch position {
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .maximize: "Whole screen"
        }
    }

    private static func positionSpoken(_ position: WindowPosition) -> String {
        switch position {
        case .leftHalf: "the left half"
        case .rightHalf: "the right half"
        case .maximize: "the whole screen"
        }
    }

    private static func spokenKey(_ name: String) -> String {
        ["left": "Left Arrow", "right": "Right Arrow", "up": "Up Arrow", "down": "Down Arrow"][name] ?? KeyNames.symbol(for: name)
    }
}
