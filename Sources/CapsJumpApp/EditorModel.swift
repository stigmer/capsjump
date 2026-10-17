// The editing window's state, wiring a ConfigDraft to the views and nothing more: every
// rule and every edit that reaches across rows is the draft's. It knows what the file held
// when it was read or last saved, so it can tell unsaved edits, its own save arriving
// through the watcher, and a change made somewhere else. A file it can't read as a
// config is shown as its problems; with no file it starts from the starter, unsaved.
// The draft is judged once per edit and every view reads that one check; what a key does on
// this Mac is asked of the disk once per key and action. Which section is shown, the row
// picked in each and the search text live here too, and a reload keeps the picked rows by
// what they are (a key's name, a site's name, a move), because row ids follow the file's
// order. Windows lists the moves rather than rows, so a move's key is set, changed or turned
// off by the draft's own bind and remove.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import CapsJumpSystem
import SwiftUI

@MainActor
final class EditorModel: ObservableObject {
    enum State: Equatable {
        case editing
        /// The file's problems, which only an edit by hand can fix.
        case unreadable([String])
    }

    enum Section: String, CaseIterable {
        case sites
        case keys
        case windows
    }

    @Published private(set) var draft = ConfigDraft(ConfigSource()) {
        didSet {
            check = draft.checked()
            onChange?()
        }
    }
    /// The rules' one judgement of `draft`.
    @Published private(set) var check = ConfigDraft(ConfigSource()).checked()
    @Published private(set) var state = State.editing {
        didSet { onChange?() }
    }
    /// The file changed elsewhere while this window had edits of its own.
    @Published private(set) var changedOutside = false {
        didSet { onChange?() }
    }
    @Published var section: Section {
        didSet {
            guard section != oldValue else { return }
            Timings.untilIdle("switch")
            UserDefaults.standard.set(section.rawValue, forKey: Self.sectionDefault)
            onChange?()
        }
    }
    @Published var selectedSite: Int? {
        didSet { if selectedSite != oldValue { Timings.untilIdle("select") } }
    }
    @Published var selectedKey: Int? {
        didSet { if selectedKey != oldValue { Timings.untilIdle("select") } }
    }
    @Published var selectedMove: WindowPosition? = WindowPosition.allCases.first {
        didSet { if selectedMove != oldValue { Timings.untilIdle("select") } }
    }
    @Published var query = "" {
        didSet { onChange?() }
    }
    /// Apps found where an app named by name is looked for; nil until the scan is done.
    @Published private(set) var apps: [InstalledApp]?
    /// Called on every change the window's own chrome shows: the status line, the section,
    /// the search text.
    var onChange: (@MainActor () -> Void)?

    let file = ConfigFile()
    let catalog = try? Inputs.profiles()
    let lookup = Lookup.thisMac
    /// What the file held when read or last saved; nil when there was no file.
    private(set) var expected: String?
    private var savedSource = ConfigSource() {
        didSet { onChange?() }
    }
    private var watcher: ConfigWatcher?
    /// What each key does on this Mac, by key and action.
    private var findings: [String: Finding] = [:]
    /// Where each app a key names is, by the name or path written.
    private var appPaths: [String: String?] = [:]
    private static let sectionDefault = "editorSection"

    init() {
        // Keys the first time: keys are the app's job, and Add Current Tab is the quick way to sites.
        // A section this version doesn't have, saved by a later one, opens Keys too.
        section = UserDefaults.standard.string(forKey: Self.sectionDefault).flatMap(Section.init) ?? .keys
        load()
        watch()
        let home = lookup.home
        Task { [weak self] in
            let apps = await Task.detached(priority: .userInitiated) { InstalledApp.scan(home: home) }.value
            self?.apps = apps
        }
    }

    /// Stops watching the file while the window is closed.
    func close() {
        watcher?.stop()
        watcher = nil
    }

    /// For the window opened again: the file as it is now, watched again, nothing searched,
    /// and site icons and account pictures read afresh.
    func reopen() {
        query = ""
        SiteIcons.forget()
        ProfilePictures.forget()
        load()
        watch()
    }

    private func watch() {
        guard watcher == nil else { return }
        let watcher = ConfigWatcher(file: file.url) { [weak self] in self?.fileChanged() }
        watcher.start()
        self.watcher = watcher
    }

    var hasChanges: Bool {
        state == .editing && draft.source != savedSource
    }

    /// The window's status line.
    var status: String {
        let count = check.issues.count
        if count > 0 { return "\(count) \(count == 1 ? "thing" : "things") to fix before saving" }
        if expected == nil { return "No config file yet; Save writes one" }
        return hasChanges ? "Unsaved changes" : "Saved"
    }

    /// Reads the file afresh, dropping any edits, and keeps the picked rows by what they are.
    func load() {
        changedOutside = false
        findings = [:]
        appPaths = [:]
        let siteName = selectedSite.flatMap { draft.site($0)?.site.name }
        let keyName = selectedKey.flatMap { draft.key($0)?.key.key }
        let contents: ConfigFile.Contents?
        do {
            contents = try file.read()
        } catch {
            expected = nil
            state = .unreadable([error.description])
            return
        }
        if let contents {
            expected = contents.text
            let source = ConfigReader.read(contents.text)
            guard source.problems.isEmpty else {
                if case let .failure(error) = contents.result {
                    state = .unreadable(error.problems)
                }
                return
            }
            draft = ConfigDraft(source)
            savedSource = draft.source
        } else {
            expected = nil
            draft = ConfigDraft(ConfigReader.read(StarterConfig.render(catalog: catalog)))
            savedSource = ConfigSource()
        }
        state = .editing
        selectedSite = draft.sites.first { $0.site.name == siteName }?.id ?? siteLines.first?.id
        selectedKey = keyLines.first { $0.key == keyName }?.id ?? keyLines.first?.id
    }

    private func fileChanged() {
        let now = try? file.read()?.text
        // Its own save, arriving through the watcher.
        guard now != expected else { return }
        if hasChanges {
            changedOutside = true
        } else {
            load()
        }
    }

    enum SaveOutcome {
        case saved
        case notSaved
    }

    /// Saves after the warnings a save needs; says whether the file now holds the draft.
    @discardableResult
    func save(in window: NSWindow?) -> SaveOutcome {
        guard let config = check.config else {
            Alerts.show("Not saved yet", "Fix the problems shown in red first; the file keeps working as it is until then.", in: window)
            return .notSaved
        }
        if let expected, !ConfigWriter.isCanonical(expected) {
            switch Alerts.ask(
                "Rewrite your config?",
                "Saving rewrites \(file.url.path) in CapsJump's own layout, so its comments and formatting won't survive. What each key does stays the same.",
                buttons: ["Save", "Cancel", "Open Config File"],
                in: window
            ) {
            case .alertFirstButtonReturn: break
            case .alertThirdButtonReturn:
                ConfigFileOpener.open()
                return .notSaved
            default: return .notSaved
            }
        }
        do {
            expected = try file.write(config, replacing: expected)
            draft.markSaved()
            savedSource = draft.source
            changedOutside = false
            return .saved
        } catch {
            if case .changedOnDisk = error {
                changedOutside = true
                Alerts.show("The file changed outside this window", "Nothing was saved. Reload to start from the file as it is now, or keep editing and copy your changes over after.", in: window)
            } else {
                Alerts.show("Nothing was saved", error.description, in: window)
            }
            return .notSaved
        }
    }

    /// Applies an edit, and publishes it only when it changed something: a text field sets
    /// its text more than once per keystroke, and each publish redraws the window.
    private func edit(_ change: (inout ConfigDraft) -> Void) {
        var next = draft
        change(&next)
        if next != draft { draft = next }
    }

    /// The lists' selections: set after the update that reports them, and only when they
    /// differ, because a list also writes its selection back while SwiftUI updates it.
    var siteSelection: Binding<Int?> {
        Binding(get: { self.selectedSite }, set: { id in
            afterUpdate { [weak self] in if let self, self.selectedSite != id { self.selectedSite = id } }
        })
    }

    var keySelection: Binding<Int?> {
        Binding(get: { self.selectedKey }, set: { id in
            afterUpdate { [weak self] in if let self, self.selectedKey != id { self.selectedKey = id } }
        })
    }

    var moveSelection: Binding<WindowPosition?> {
        Binding(get: { self.selectedMove }, set: { move in
            afterUpdate { [weak self] in if let self, self.selectedMove != move { self.selectedMove = move } }
        })
    }

    // MARK: Lists

    var siteLines: [EditorRows.SiteLine] {
        EditorRows.sites(draft, matching: query)
    }

    var keyLines: [EditorRows.KeyLine] {
        EditorRows.keys(draft, matching: query)
    }

    var windowLines: [EditorRows.WindowLine] {
        EditorRows.windows(draft, matching: query)
    }

    /// Whether a key with a problem is listed in Windows (`moves`) or in Keys.
    func keyProblems(moves: Bool) -> Bool {
        draft.keys.contains { check.byKey[$0.id] != nil && (EditorRows.move(of: $0.key) != nil) == moves }
    }

    /// Picks the first row with a problem: sites, then keys, then moves; false when there is none.
    @discardableResult
    func selectFirstProblem() -> Bool {
        query = ""
        if let site = draft.sites.first(where: { check.bySite[$0.id] != nil }) {
            section = .sites
            selectedSite = site.id
            return true
        }
        if let key = keyLines.first(where: { check.byKey[$0.id] != nil }) {
            section = .keys
            selectedKey = key.id
            return true
        }
        if let line = windowLines.first(where: { $0.keys.contains { check.byKey[$0.row] != nil } }) {
            section = .windows
            selectedMove = line.move
            return true
        }
        return false
    }

    /// Adds a site or a key to the section shown, and picks it; the moves are fixed.
    func addItem() {
        switch section {
        case .sites: addSite()
        case .keys: addKey()
        case .windows: break
        }
    }

    var canAdd: Bool {
        switch section {
        case .sites: true
        case .keys: !draft.freeKeys().isEmpty
        case .windows: false
        }
    }

    /// Removes the picked row, or turns the picked move's keys off; a site that keys jump to asks first.
    func removeSelected(in window: NSWindow?) {
        switch section {
        case .sites: if let selectedSite { remove(site: selectedSite, in: window) }
        case .keys: if let selectedKey { remove(key: selectedKey) }
        case .windows: if let selectedMove { turnOff(selectedMove) }
        }
    }

    var canRemove: Bool {
        guard state == .editing else { return false }
        return switch section {
        case .sites: selectedSite != nil
        case .keys: selectedKey != nil
        case .windows: selectedMove.map { !EditorRows.window($0, in: draft).keys.isEmpty } ?? false
        }
    }

    /// The row after `id` in `ids`, or the one before it when it is last.
    private static func neighbour(of id: Int, in ids: [Int]) -> Int? {
        guard let index = ids.firstIndex(of: id) else { return ids.first }
        let rest = ids.filter { $0 != id }
        return rest.isEmpty ? nil : rest[min(index, rest.count - 1)]
    }

    // MARK: Sites

    func addSite() {
        query = ""
        let id = draft.addSite(SiteSource(index: draft.sites.count, name: "", open: ""))
        section = .sites
        selectedSite = id
    }

    func rename(_ id: Int, _ name: String) {
        Timings.untilIdle("keystroke")
        edit { $0.renameSite(id, to: name) }
    }

    func update(_ id: Int, _ change: (inout SiteSource) -> Void) {
        Timings.untilIdle("keystroke")
        edit { $0.updateSite(id, change) }
    }

    func profile(of id: Int) -> String? {
        guard let catalog, let site = draft.site(id)?.site else { return nil }
        if let directory = site.profile { return directory }
        return site.account.flatMap { try? catalog.profile(account: $0) }?.directory
    }

    /// What the site's icon is read by: the profile it jumps into and its pages; nil while
    /// either is unknown, which shows the globe.
    func iconKey(site id: Int) -> SiteIconKey? {
        guard let site = draft.site(id)?.site, let profile = profile(of: id),
              let lookup = SiteIcon.lookup(open: site.open ?? "", match: site.match) else { return nil }
        return SiteIconKey(profile: profile, lookup: lookup)
    }

    /// What the site's account picture is drawn from: the profile it jumps into, resolved
    /// as "Lands in" is; nil when no profile matches, which shows the account's text alone.
    func pictureKey(site id: Int) -> ProfilePictureKey? {
        guard let catalog, let directory = profile(of: id), let profile = catalog.profile(directory: directory) else { return nil }
        return ProfilePictureKey(profile)
    }

    func setProfile(_ id: Int, _ directory: String?) {
        guard let catalog, let directory, let profile = catalog.profile(directory: directory) else { return }
        let fields = SiteAccount.fields(for: profile, in: catalog)
        edit {
            $0.updateSite(id) {
                $0.account = fields.account
                $0.profile = fields.profile
            }
        }
    }

    /// The prefixes as one line, "" while the default is used.
    func matchText(_ id: Int) -> String {
        (draft.site(id)?.site.match ?? []).joined(separator: ", ")
    }

    func setMatch(_ id: Int, _ text: String) {
        Timings.untilIdle("keystroke")
        let prefixes = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        edit { $0.updateSite(id) { $0.match = prefixes.isEmpty ? nil : prefixes } }
    }

    /// The default prefix a site matches while `match` is left out.
    func defaultMatch(_ id: Int) -> String? {
        draft.site(id)?.site.open.flatMap(ConfigRules.httpURL).map(URLPrefix.defaultMatch(for:))
    }

    /// Removes the site, asking first what to do with the keys that jump to it.
    func remove(site id: Int, in window: NSWindow?) {
        let keys = draft.keysUsing(id)
        var removingKeys = false
        if !keys.isEmpty {
            let name = draft.site(id)?.site.name.flatMap { $0.isEmpty ? nil : $0 } ?? "this site"
            let symbols = keys.map { "Caps Lock + \(KeyNames.symbol(for: $0))" }.joined(separator: " and ")
            switch Alerts.ask(
                "Remove \(name)?",
                "\(symbols) \(keys.count == 1 ? "jumps" : "jump") to it.",
                buttons: ["Remove Site and Keys", "Cancel", "Remove Site Only"],
                in: window
            ) {
            case .alertFirstButtonReturn: removingKeys = true
            case .alertThirdButtonReturn: removingKeys = false
            default: return
            }
        }
        let next = Self.neighbour(of: id, in: siteLines.map(\.id))
        draft.removeSite(id, removingKeys: removingKeys)
        if selectedSite == id { selectedSite = next }
        if let selectedKey, draft.key(selectedKey) == nil { self.selectedKey = keyLines.first?.id }
    }

    /// A site key for the site on the first free key, picked in Keys.
    func addKey(forSite id: Int) {
        guard let name = draft.site(id)?.site.name, let key = draft.freeKeys().first,
              case let .bound(row) = draft.bind(key, to: ActionSource(.site, name)) else { return }
        query = ""
        section = .keys
        selectedKey = row
    }

    // MARK: Keys

    func addKey() {
        guard let key = draft.freeKeys().first, case let .bound(row) = draft.bind(key, to: nil) else { return }
        query = ""
        section = .keys
        selectedKey = row
    }

    func setKey(_ row: Int, _ key: String) {
        edit { _ = $0.bind(key, to: $0.key(row)?.key.action, row: row) }
    }

    func setKind(_ row: Int, _ kind: ActionSource.Kind?) {
        guard let kind else {
            edit { $0.setAction(row, nil) }
            return
        }
        guard draft.key(row)?.key.action?.kind != kind else { return }
        // Keys offers no window kind: a move's key is set in Windows.
        let value = switch kind {
        case .site: draft.sites.compactMap(\.site.name).first ?? ""
        case .app, .url, .window: ""
        }
        draft.setAction(row, ActionSource(kind, value))
    }

    func setValue(_ row: Int, _ value: String) {
        Timings.untilIdle("keystroke")
        guard let kind = draft.key(row)?.key.action?.kind else { return }
        edit { $0.setAction(row, ActionSource(kind, value)) }
    }

    func remove(key row: Int) {
        let next = Self.neighbour(of: row, in: keyLines.map(\.id))
        draft.removeKey(row)
        if selectedKey == row { selectedKey = next }
    }

    /// Stores the app at `path` by name when the name finds that same app, else by path.
    func setApp(_ row: Int, path: String) {
        let target = AppTarget.preferred(forPath: path, home: lookup.home, exists: lookup.exists)
        setValue(row, target.description)
    }

    /// Asks for any .app, as the chooser's Other… does.
    func chooseOtherApp(_ row: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setApp(row, path: url.path)
    }

    // MARK: Windows

    /// Binds `key` to the move on the row, or on a new row when `row` is nil; nil removes the row.
    func setKey(_ move: WindowPosition, row: Int?, _ key: String?) {
        edit { draft in
            if let key {
                _ = draft.bind(key, to: ActionSource(.window, move.rawValue), row: row)
            } else if let row {
                draft.removeKey(row)
            }
        }
    }

    /// Removes every key that makes the move.
    func turnOff(_ move: WindowPosition) {
        let rows = EditorRows.window(move, in: draft).keys.map(\.row)
        edit { draft in rows.forEach { draft.removeKey($0) } }
    }

    // MARK: What each editor shows

    /// Everything the key editor shows, as values, so an editor whose key didn't change is
    /// left alone by an edit elsewhere.
    struct KeyForm: Equatable, Sendable {
        struct SiteChoice: Equatable, Sendable {
            let name: String
            let label: String
        }

        let row: Int
        let key: KeySource
        let free: [String]
        let sites: [SiteChoice]
        let appPath: String?
        let note: String?
        let problems: [String]
    }

    func keyForm(_ row: Int) -> KeyForm? {
        guard let key = draft.key(row)?.key else { return nil }
        let action = key.action
        let finding = [.app, .url].contains(action?.kind) ? finding(key: row) : nil
        let missing = finding.flatMap { $0.level == .problem ? FormWording.finding($0) : nil }
        let note: String? = switch action?.kind {
        case .site?:
            draft.sites.first { $0.site.name == action?.value }.flatMap { landing(site: $0.id) }.map { "Lands in \($0)" }
        case .app?, .url?:
            finding.flatMap { $0.level == .problem ? nil : FormWording.finding($0) }
        default:
            nil
        }
        return KeyForm(
            row: row,
            key: key,
            free: draft.freeKeys(for: row),
            // Only a site key lists the sites, so renaming one leaves every other key's editor alone.
            sites: action?.kind != .site ? [] : draft.sites.compactMap { row in
                guard let name = row.site.name, !name.isEmpty else { return nil }
                return KeyForm.SiteChoice(name: name, label: [name, row.site.account ?? row.site.profile].compactMap { $0 }.joined(separator: " · "))
            },
            appPath: action?.kind == .app ? action.flatMap { appPath($0.value) } : nil,
            note: note,
            problems: problems(key: row) + (missing.map { [$0] } ?? [])
        )
    }

    /// Everything the move editor shows, as values.
    struct WindowForm: Equatable, Sendable {
        struct KeyChoice: Equatable, Sendable {
            let row: Int
            let key: String
            let free: [String]
            let problems: [String]
        }

        let line: EditorRows.WindowLine
        let keys: [KeyChoice]
        /// The keys no row holds, for a move with none.
        let free: [String]
    }

    func windowForm(_ move: WindowPosition) -> WindowForm {
        let line = EditorRows.window(move, in: draft)
        return WindowForm(
            line: line,
            keys: line.keys.map { WindowForm.KeyChoice(row: $0.row, key: $0.key, free: draft.freeKeys(for: $0.row), problems: problems(key: $0.row)) },
            free: line.keys.isEmpty ? draft.freeKeys() : []
        )
    }

    /// Everything the site editor shows, as values.
    struct SiteForm: Equatable, Sendable {
        let id: Int
        let site: SiteSource
        /// The profile folder the account picks, when Chrome's list could be read.
        let profile: String?
        let profiles: [ChromeProfile]?
        let landing: String?
        let keys: [String]
        let canAddKey: Bool
        let matchText: String
        let defaultMatch: String?
        let matchIsDefault: Bool
        let nameProblems: [String]
        let accountProblems: [String]
        let pageProblems: [String]
        let matchProblems: [String]
    }

    func siteForm(_ id: Int) -> SiteForm? {
        guard let site = draft.site(id)?.site else { return nil }
        return SiteForm(
            id: id,
            site: site,
            profile: profile(of: id),
            profiles: catalog?.profiles,
            landing: landing(site: id),
            keys: draft.keysUsing(id),
            canAddKey: !(site.name ?? "").isEmpty && !draft.freeKeys().isEmpty,
            matchText: matchText(id),
            defaultMatch: defaultMatch(id),
            matchIsDefault: draft.matchIsDefault(id),
            nameProblems: problems(site: id, .entry, .unknownKey, .name),
            accountProblems: problems(site: id, .account, .profile, .accountOrProfile),
            pageProblems: problems(site: id, .open),
            matchProblems: problems(site: id, .match)
        )
    }

    // MARK: Problems and findings

    func problems(site id: Int, _ fields: SiteSource.Field...) -> [String] {
        check.site(id, fields).map { FormWording.text($0.message) }
    }

    func problems(key row: Int) -> [String] {
        check.key(row).map { FormWording.text($0.message) }
    }

    var fileProblems: [String] {
        check.file.map { FormWording.text($0.message) }
    }

    /// Where a site lands, once the whole config is valid.
    func landing(site id: Int) -> String? {
        guard let catalog, let name = draft.site(id)?.site.name, let site = check.config?.site(named: name) else { return nil }
        return Checkup.site(site, catalog: catalog).text.components(separatedBy: " → ").dropFirst().joined(separator: " → ")
    }

    /// Where the app a key names is, as the keys would find it; asked once per app.
    func appPath(_ app: String) -> String? {
        if let known = appPaths[app] { return known }
        let path = AppIcons.path(for: app, lookup: lookup)
        appPaths[app] = path
        return path
    }

    /// What a key does on this Mac, once the whole config is valid; asked once per key and action.
    func finding(key row: Int) -> Finding? {
        guard let key = draft.key(row)?.key.key, let binding = check.config?.keys.first(where: { $0.key == key }) else { return nil }
        let id = "\(binding.key) \(binding.action)"
        if let known = findings[id] { return known }
        let finding = Checkup.key(binding, lookup: lookup)
        findings[id] = finding
        return finding
    }
}
