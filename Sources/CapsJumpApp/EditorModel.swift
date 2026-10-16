// The editing window's state, wiring a ConfigDraft to the views and nothing more: every
// rule and every edit that reaches across rows is the draft's. It knows what the file held
// when it was read or last saved, so it can tell unsaved edits, its own save arriving
// through the watcher, and a change made somewhere else. A file it can't read as a
// config is shown as its problems; with no file it starts from the starter, unsaved.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import CapsJumpSystem

@MainActor
final class EditorModel: ObservableObject {
    enum State: Equatable {
        case editing
        /// The file's problems, which only an edit by hand can fix.
        case unreadable([String])
    }

    @Published private(set) var draft = ConfigDraft(ConfigSource())
    @Published private(set) var state = State.editing
    /// The file changed elsewhere while this window had edits of its own.
    @Published private(set) var changedOutside = false
    @Published var tab = 0

    let file = ConfigFile()
    let catalog = try? Inputs.profiles()
    let lookup = Lookup.thisMac
    /// Apps found where an app named by name is looked for, by name.
    let apps = EditorModel.installedApps()
    /// What the file held when read or last saved; nil when there was no file.
    private(set) var expected: String?
    private var savedSource = ConfigSource()
    private var watcher: ConfigWatcher?

    init() {
        load()
        let watcher = ConfigWatcher(file: file.url) { [weak self] in self?.fileChanged() }
        watcher.start()
        self.watcher = watcher
    }

    func close() {
        watcher?.stop()
        watcher = nil
    }

    var hasChanges: Bool {
        state == .editing && draft.source != savedSource
    }

    /// Reads the file afresh, dropping any edits.
    func load() {
        changedOutside = false
        let contents: ConfigFile.Contents?
        do {
            contents = try file.read()
        } catch {
            expected = nil
            state = .unreadable([error.description])
            return
        }
        guard let contents else {
            expected = nil
            draft = ConfigDraft(ConfigReader.read(StarterConfig.render(catalog: catalog)))
            savedSource = ConfigSource()
            state = .editing
            return
        }
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
        state = .editing
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
        guard let config = draft.config else {
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

    // MARK: Sites

    @discardableResult
    func addSite() -> Int {
        tab = 0
        return draft.addSite(SiteSource(index: draft.sites.count, name: "", open: ""))
    }

    func rename(_ id: Int, _ name: String) {
        draft.renameSite(id, to: name)
    }

    func update(_ id: Int, _ change: (inout SiteSource) -> Void) {
        draft.updateSite(id, change)
    }

    func profile(of id: Int) -> String? {
        guard let catalog, let site = draft.site(id)?.site else { return nil }
        if let directory = site.profile { return directory }
        return site.account.flatMap { try? catalog.profile(account: $0) }?.directory
    }

    func setProfile(_ id: Int, _ directory: String?) {
        guard let catalog, let directory, let profile = catalog.profile(directory: directory) else { return }
        let fields = SiteAccount.fields(for: profile, in: catalog)
        draft.updateSite(id) {
            $0.account = fields.account
            $0.profile = fields.profile
        }
    }

    /// The prefixes as one line, "" while the default is used.
    func matchText(_ id: Int) -> String {
        (draft.site(id)?.site.match ?? []).joined(separator: ", ")
    }

    func setMatch(_ id: Int, _ text: String) {
        let prefixes = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        draft.updateSite(id) { $0.match = prefixes.isEmpty ? nil : prefixes }
    }

    /// The default prefix a site matches while `match` is left out.
    func defaultMatch(_ id: Int) -> String? {
        draft.site(id)?.site.open.flatMap(ConfigRules.httpURL).map(URLPrefix.defaultMatch(for:))
    }

    func remove(site id: Int, keys: Bool) {
        draft.removeSite(id, removingKeys: keys)
    }

    // MARK: Keys

    func addKey() {
        tab = 1
        guard let key = draft.freeKeys().first else { return }
        _ = draft.bind(key, to: nil)
    }

    func setKey(_ row: Int, _ key: String) {
        _ = draft.bind(key, to: draft.key(row)?.key.action, row: row)
    }

    func setKind(_ row: Int, _ kind: ActionSource.Kind?) {
        guard let kind else {
            draft.setAction(row, nil)
            return
        }
        guard draft.key(row)?.key.action?.kind != kind else { return }
        let value = switch kind {
        case .site: draft.sites.compactMap(\.site.name).first ?? ""
        case .window: WindowPosition.leftHalf.rawValue
        case .app, .url: ""
        }
        draft.setAction(row, ActionSource(kind, value))
    }

    func setValue(_ row: Int, _ value: String) {
        guard let kind = draft.key(row)?.key.action?.kind else { return }
        draft.setAction(row, ActionSource(kind, value))
    }

    func remove(key row: Int) {
        draft.removeKey(row)
    }

    /// Asks for an .app, and stores its name when the name finds that same app.
    func chooseApp(_ row: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target = AppTarget.preferred(forPath: url.path, home: lookup.home, exists: lookup.exists)
        setValue(row, target.description)
    }

    // MARK: Problems and findings

    func problems(site id: Int, _ fields: SiteSource.Field...) -> [String] {
        draft.issues.compactMap { issue in
            guard case let .site(row, field) = issue.spot, row == id, fields.contains(field) else { return nil }
            return FormWording.text(issue.message)
        }
    }

    func problems(key row: Int) -> [String] {
        draft.issues.compactMap { issue in
            guard case let .key(id, _) = issue.spot, id == row else { return nil }
            return FormWording.text(issue.message)
        }
    }

    var fileProblems: [String] {
        draft.issues.compactMap { $0.spot == .file ? FormWording.text($0.message) : nil }
    }

    /// Where a site lands, once the whole config is valid.
    func landing(site id: Int) -> String? {
        guard let catalog, let name = draft.site(id)?.site.name, let site = draft.config?.site(named: name) else { return nil }
        return Checkup.site(site, catalog: catalog).text.components(separatedBy: " → ").dropFirst().joined(separator: " → ")
    }

    /// What a key does on this Mac, once the whole config is valid.
    func finding(key row: Int) -> Finding? {
        guard let key = draft.key(row)?.key.key, let binding = draft.config?.keys.first(where: { $0.key == key }) else { return nil }
        return Checkup.key(binding, lookup: lookup)
    }

    private static func installedApps() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var names = Set<String>()
        for folder in AppTarget.searchFolders {
            let path = folder.hasPrefix("~/") ? home + folder.dropFirst() : folder
            for file in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] where file.hasSuffix(".app") {
                names.insert(String(file.dropLast(4)))
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
