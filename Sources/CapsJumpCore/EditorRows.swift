// How the config window lists a draft: each key and site as one line of text, which lines a
// search keeps, and the order keys are listed in. A key reads like the key itself: its
// symbol, then what it does in a word or two (the app, the site and its account, the link's
// host). Keys are listed in `KeyNames.all` order, which is how one looks for a key; sites
// keep the file's order, which can matter among sites that match the same page. Keys that
// move the window are listed apart, as one line per move CapsJump can make, always all of
// them in `WindowPosition`'s order, each with the keys that do it; every other key, one whose
// move CapsJump doesn't know included, is listed with the keys, so every problem has a line
// it shows on. The order and the list shown never change the order written.

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
        public let title: String
        public let subtitle: String?
        /// What the key does, as a phrase: "brings Slack forward".
        public let doing: String
        /// What VoiceOver reads for the whole line.
        public let spoken: String
        let searched: [String]
    }

    /// One move CapsJump can make, with the keys that do it.
    public struct WindowLine: Sendable, Equatable, Identifiable {
        public struct Bound: Sendable, Equatable {
            public let row: Int
            public let key: String
        }

        public var id: WindowPosition { move }
        public let move: WindowPosition
        public let title: String
        /// The rows that bind a key to the move, in `KeyNames.all` order.
        public let keys: [Bound]
        public let suggested: String
        /// Whether no row holds the suggested key.
        public let suggestedFree: Bool
        /// What the suggested key does now, when the move has no key and another row holds it.
        public let suggestedHeld: String?
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

    /// The move a key makes, when it is one CapsJump knows; such a key is listed under its
    /// move rather than with the keys.
    public static func move(of key: KeySource) -> WindowPosition? {
        guard let action = key.action, action.kind == .window else { return nil }
        return WindowPosition(rawValue: action.value)
    }

    /// The draft's keys that match `query`, in `KeyNames.all` order, but those that make a move.
    public static func keys(_ draft: ConfigDraft, matching query: String = "") -> [KeyLine] {
        let words = words(query)
        return draft.keys
            .filter { move(of: $0.key) == nil }
            .map { key($0, in: draft) }
            .filter { matches(words, $0.searched) }
            .sorted { rank($0.key) < rank($1.key) }
    }

    /// Every move that matches `query`, in `WindowPosition` order, whether a key makes it or not.
    public static func windows(_ draft: ConfigDraft, matching query: String = "") -> [WindowLine] {
        let words = words(query)
        return WindowPosition.allCases
            .map { window($0, in: draft) }
            .filter { matches(words, $0.searched) }
    }

    public static func window(_ move: WindowPosition, in draft: ConfigDraft) -> WindowLine {
        let keys = draft.keys
            .filter { Self.move(of: $0.key) == move }
            .map { WindowLine.Bound(row: $0.id, key: $0.key.key) }
            .sorted { rank($0.key) < rank($1.key) }
        let title = positionTitle(move)
        let suggested = move.suggestedKey
        let holder = draft.keys.first { $0.key.key == suggested }
        let spoken = keys.isEmpty
            ? "\(title), off"
            : "Caps Lock plus \(keys.map { spokenKey($0.key) }.joined(separator: " or ")), moves the front window to \(positionSpoken(move))"
        return WindowLine(
            move: move,
            title: title,
            keys: keys,
            suggested: suggested,
            suggestedFree: holder == nil,
            suggestedHeld: keys.isEmpty ? holder.map { key($0, in: draft).doing } : nil,
            spoken: spoken,
            searched: [title] + keys.flatMap { [$0.key, KeyNames.symbol(for: $0.key)] }
        )
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
            title: title,
            subtitle: subtitle,
            doing: doing,
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

    static func appName(_ path: String) -> String {
        let file = path.split(separator: "/").last.map(String.init) ?? path
        return file.hasSuffix(".app") ? String(file.dropLast(4)) : file
    }

    private static func positionTitle(_ position: WindowPosition) -> String {
        switch position {
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .topHalf: "Top half"
        case .bottomHalf: "Bottom half"
        case .maximize: "Whole screen"
        }
    }

    static func positionSpoken(_ position: WindowPosition) -> String {
        switch position {
        case .leftHalf: "the left half"
        case .rightHalf: "the right half"
        case .topHalf: "the top half"
        case .bottomHalf: "the bottom half"
        case .maximize: "the whole screen"
        }
    }

    /// A key name as VoiceOver should say it: `G`, `F1`, `Up Arrow`.
    public static func spokenKey(_ name: String) -> String {
        ["left": "Left Arrow", "right": "Right Arrow", "up": "Up Arrow", "down": "Down Arrow"][name] ?? KeyNames.symbol(for: name)
    }
}
