// The config while a window edits it: the sites and keys as written, each row with an id
// that survives edits, its problems pinned to a row and a field by the same rules the file
// is judged by, and the edits that touch more than one row. Renaming a site carries its
// keys along; removing one says which keys used it; binding a key that's taken says what it
// does now instead of overwriting it. Links to a site name the file had and the draft no
// longer has stop working, which only the window can tell the user, so the draft lists them.
// `checked()` judges the whole draft once and hands back every problem by row, so a window
// that shows them field by field asks the rules once per edit, not once per field.

import Foundation

public struct ConfigDraft: Sendable, Equatable {
    public struct SiteRow: Sendable, Equatable, Identifiable {
        public let id: Int
        public var site: SiteSource
    }

    public struct KeyRow: Sendable, Equatable, Identifiable {
        public let id: Int
        public var key: KeySource
        /// The site row a site key jumps to, so it follows that row through renames.
        public fileprivate(set) var siteRow: Int?
    }

    /// Where a problem shows: beside a field of a row, or above the rows.
    public enum Spot: Sendable, Equatable {
        case file
        case site(id: Int, field: SiteSource.Field)
        case key(id: Int, field: KeySource.Field)
    }

    public struct Issue: Sendable, Equatable {
        public let spot: Spot
        public let message: String
    }

    public enum BindOutcome: Sendable, Equatable {
        case bound(row: Int)
        /// Nothing changed: another row holds the key, doing this.
        case taken(row: Int, action: ActionSource?)
    }

    public private(set) var sites: [SiteRow] = []
    public private(set) var keys: [KeyRow] = []
    private var nextID = 0
    /// The site names in the file as last read or saved, whose links work today.
    private var startingNames: [String]

    /// From a source read without problems; positions become the places problems name.
    public init(_ source: ConfigSource) {
        startingNames = source.sites.compactMap(\.name)
        for site in source.sites { addSite(site) }
        for key in source.keys {
            keys.append(KeyRow(id: takeID(), key: key, siteRow: siteRow(for: key.action)))
        }
    }

    public var source: ConfigSource {
        ConfigSource(
            sites: sites.enumerated().map { index, row in
                var site = row.site
                site.index = index
                site.line = nil
                // A field cleared in the window is a field not given.
                site.name = Self.given(site.name)
                site.account = Self.given(site.account)
                site.profile = Self.given(site.profile)
                site.open = Self.given(site.open)
                return site
            },
            keys: keys.enumerated().map { index, row in
                var key = row.key
                key.index = index
                key.line = nil
                return key
            }
        )
    }

    /// One judgement of the draft by the rules.
    public struct Check: Sendable, Equatable {
        /// The config to save, or nil while any problem remains.
        public let config: Config?
        /// Every problem, in the order the rules found them.
        public let issues: [Issue]
        /// The problems above the rows.
        public let file: [Issue]
        public let bySite: [Int: [Issue]]
        public let byKey: [Int: [Issue]]

        init(config: Config?, issues: [Issue]) {
            self.config = config
            self.issues = issues
            var file: [Issue] = []
            var bySite: [Int: [Issue]] = [:]
            var byKey: [Int: [Issue]] = [:]
            for issue in issues {
                switch issue.spot {
                case .file: file.append(issue)
                case let .site(id, _): bySite[id, default: []].append(issue)
                case let .key(id, _): byKey[id, default: []].append(issue)
                }
            }
            self.file = file
            self.bySite = bySite
            self.byKey = byKey
        }

        /// The site row's problems on these fields, all of them when none is named.
        public func site(_ id: Int, _ fields: [SiteSource.Field] = []) -> [Issue] {
            (bySite[id] ?? []).filter { issue in
                guard case let .site(_, field) = issue.spot else { return false }
                return fields.isEmpty || fields.contains(field)
            }
        }

        public func key(_ id: Int) -> [Issue] {
            byKey[id] ?? []
        }
    }

    public func checked() -> Check {
        switch ConfigRules.validate(source) {
        case let .success(config):
            return Check(config: config, issues: [])
        case let .failure(error):
            return Check(config: nil, issues: error.found.map { problem in
                let spot: Spot = switch problem.place {
                case .file, .keys: .file
                case let .site(index, _, field): .site(id: sites[index].id, field: field)
                case let .key(index, _, field): .key(id: keys[index].id, field: field)
                }
                return Issue(spot: spot, message: problem.message)
            })
        }
    }

    /// The config to save, or nil while any problem remains.
    public var config: Config? {
        checked().config
    }

    public var issues: [Issue] {
        checked().issues
    }

    /// Whether the site matches the default prefix, which follows its open URL.
    public func matchIsDefault(_ id: Int) -> Bool {
        site(id)?.site.match == nil
    }

    /// `capsjump://` links that worked when the draft started and won't after it is saved.
    public var brokenLinks: [String] {
        let names = Set(sites.compactMap(\.site.name))
        return startingNames.filter { !names.contains($0) }
    }

    /// After a save: the names as they are now are the ones whose links work.
    public mutating func markSaved() {
        startingNames = sites.compactMap(\.site.name)
    }

    // MARK: Sites

    @discardableResult
    public mutating func addSite(_ site: SiteSource) -> Int {
        let id = takeID()
        sites.append(SiteRow(id: id, site: site))
        return id
    }

    /// Changes anything but the name, which `renameSite` changes.
    public mutating func updateSite(_ id: Int, _ change: (inout SiteSource) -> Void) {
        guard let index = sites.firstIndex(where: { $0.id == id }) else { return }
        let name = sites[index].site.name
        change(&sites[index].site)
        sites[index].site.name = name
    }

    /// Renames the site and the keys that jump to it, so keys follow a name as it is
    /// typed, cleared and retyped included; returns those keys. A key follows the site row
    /// it was bound to, never a name, so a site whose name passes through another's while
    /// typed never takes that site's keys.
    @discardableResult
    public mutating func renameSite(_ id: Int, to name: String) -> [String] {
        guard let index = sites.firstIndex(where: { $0.id == id }) else { return [] }
        let old = sites[index].site.name
        sites[index].site.name = name
        guard old != name else { return [] }
        var moved: [String] = []
        for row in keys.indices where keys[row].siteRow == id {
            keys[row].key.action = ActionSource(.site, name)
            moved.append(keys[row].key.key)
        }
        return moved
    }

    /// The keys that jump to the site.
    public func keysUsing(_ id: Int) -> [String] {
        keys.filter { $0.siteRow == id }.map(\.key.key)
    }

    /// Removes the site, and its keys only when asked; returns the keys that used it.
    /// Keys kept name a site that is gone, which the rules then report.
    @discardableResult
    public mutating func removeSite(_ id: Int, removingKeys: Bool) -> [String] {
        let using = keysUsing(id)
        if removingKeys {
            keys.removeAll { $0.siteRow == id }
        }
        for row in keys.indices where keys[row].siteRow == id {
            keys[row].siteRow = nil
        }
        sites.removeAll { $0.id == id }
        return using
    }

    // MARK: Keys

    /// Binds `key` on the row, or on a new row when `row` is nil. A key another row holds
    /// is left alone unless `replacing`, which removes that row.
    public mutating func bind(_ key: String, to action: ActionSource?, row: Int? = nil, replacing: Bool = false) -> BindOutcome {
        if let holder = keys.first(where: { $0.key.key == key && $0.id != row }) {
            guard replacing else { return .taken(row: holder.id, action: holder.key.action) }
            keys.removeAll { $0.id == holder.id }
        }
        if let row, let index = keys.firstIndex(where: { $0.id == row }) {
            keys[index].key.key = key
            if keys[index].key.action != action {
                keys[index].key.action = action
                keys[index].siteRow = siteRow(for: action)
            }
            return .bound(row: row)
        }
        let id = takeID()
        keys.append(KeyRow(id: id, key: KeySource(index: keys.count, key: key, action: action), siteRow: siteRow(for: action)))
        return .bound(row: id)
    }

    public mutating func setAction(_ row: Int, _ action: ActionSource?) {
        guard let index = keys.firstIndex(where: { $0.id == row }), keys[index].key.action != action else { return }
        keys[index].key.action = action
        keys[index].siteRow = siteRow(for: action)
    }

    /// The row a site action names: the first site of that name, as the rules resolve it.
    private func siteRow(for action: ActionSource?) -> Int? {
        guard let action, action.kind == .site else { return nil }
        return sites.first { $0.site.name == action.value }?.id
    }

    public mutating func removeKey(_ row: Int) {
        keys.removeAll { $0.id == row }
    }

    /// The keys no row holds, plus the row's own, in `KeyNames.all` order.
    public func freeKeys(for row: Int? = nil) -> [String] {
        let taken = Set(keys.filter { $0.id != row }.map(\.key.key))
        return KeyNames.all.filter { !taken.contains($0) }
    }

    // MARK: -

    public func site(_ id: Int) -> SiteRow? {
        sites.first { $0.id == id }
    }

    public func key(_ id: Int) -> KeyRow? {
        keys.first { $0.id == id }
    }

    private static func given(_ text: String?) -> String? {
        text.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    private mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}
