// Edit Config…: one window, reused, laid out as the Mac's own apps are: Sites and Keys in a
// sidebar, the section's rows in a searchable list, and the picked row's editor beside it.
// The toolbar is AppKit's (add, search, Save), because a SwiftUI toolbar reaches a window it
// doesn't own only from macOS 14; the window's subtitle says whether there is anything to
// save. The menu bar's File, Edit and View items reach the window through the responder
// chain, so they grey out while another window is in front. Save (⌘S) writes through
// ConfigFile, so the keys change at once, as saving the file does. Closing the window or
// CapsJump's own Quit asks about unsaved edits; a quit from outside (`capsjump quit`,
// Homebrew, logout) never waits on that question, because quitting is what gives Caps Lock
// back, and the edits are lost. A file changed elsewhere reloads quietly when there are no
// edits, and otherwise says so with Reload. A file CapsJump can't read opens on its problems.

import AppKit
import CapsJumpCore
import SwiftUI

@MainActor
final class Editor: NSObject, NSWindowDelegate, NSToolbarDelegate, NSSearchFieldDelegate, NSMenuItemValidation, NSToolbarItemValidation {
    private var window: NSWindow?
    private var model: EditorModel?
    private var searchItem: NSSearchToolbarItem?

    private static let addItem = NSToolbarItem.Identifier("add")
    private static let searchItem = NSToolbarItem.Identifier("search")
    private static let saveItem = NSToolbarItem.Identifier("save")

    /// Opens the window; `showingProblems` picks the first row with a problem.
    func open(showingProblems: Bool = false) {
        Timings.untilIdle("open")
        if let window, let model {
            if showingProblems { model.selectFirstProblem() }
            AppWindows.show(window)
            return
        }
        let model = EditorModel()
        if showingProblems { model.selectFirstProblem() }
        let controller = NSHostingController(rootView: EditorView(model: model))
        // The window sets its own size; the content only fills it.
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = "CapsJump Config"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "CapsJumpConfig")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.setContentSize(NSSize(width: 900, height: 600))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("CapsJumpConfig")
        self.window = window
        self.model = model
        model.onChange = { [weak self] in self?.modelChanged() }
        modelChanged()
        AppWindows.show(window)
    }

    /// Whether CapsJump may quit now, asking about unsaved edits first.
    func mayQuit() -> Bool {
        guard let window else { return true }
        return settleEdits(in: window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        settleEdits(in: sender)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        model?.onChange = nil
        model?.close()
        model = nil
        searchItem = nil
        self.window = nil
        AppWindows.closed(window)
    }

    /// Save, Don't Save or Cancel, when there is anything unsaved; true to go ahead.
    private func settleEdits(in window: NSWindow) -> Bool {
        guard let model, model.hasChanges else { return true }
        AppWindows.show(window)
        switch Alerts.ask(
            "Save your changes to the config?",
            "Close without saving and the keys stay as they were.",
            buttons: ["Save", "Cancel", "Don't Save"],
            in: window
        ) {
        case .alertFirstButtonReturn: return model.save(in: window) == .saved
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    /// The chrome follows the model: status in the subtitle, the edited dot, the search text.
    private func modelChanged() {
        guard let window, let model else { return }
        switch model.state {
        case .editing: window.subtitle = model.status
        case .unreadable: window.subtitle = "Can't read the config"
        }
        window.isDocumentEdited = model.hasChanges
        if let field = searchItem?.searchField {
            if field.stringValue != model.query { field.stringValue = model.query }
            field.placeholderString = model.section == .sites ? "Search sites" : "Search keys"
        }
        window.toolbar?.validateVisibleItems()
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.addItem, Self.searchItem, Self.saveItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Self.addItem:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "New"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New")
            item.action = #selector(newConfigItem(_:))
            item.isBordered = true
            return item
        case Self.searchItem:
            let item = NSSearchToolbarItem(itemIdentifier: identifier)
            item.searchField.delegate = self
            item.searchField.sendsSearchStringImmediately = true
            item.preferredWidthForSearchField = 220
            searchItem = item
            return item
        case Self.saveItem:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Save"
            item.title = "Save"
            item.action = #selector(saveConfig(_:))
            item.isBordered = true
            return item
        default:
            return nil
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField, field === searchItem?.searchField else { return }
        model?.query = field.stringValue
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        validate(item.action)
    }

    // MARK: Menu actions, reached through the window's responder chain

    @objc func newConfigItem(_ sender: Any?) {
        model?.addItem()
    }

    @objc func saveConfig(_ sender: Any?) {
        guard let window, let model else { return }
        model.save(in: window)
    }

    @objc func deleteConfigItem(_ sender: Any?) {
        model?.removeSelected(in: window)
    }

    @objc func findConfigItem(_ sender: Any?) {
        searchItem?.beginSearchInteraction()
    }

    @objc func showConfigSites(_ sender: Any?) {
        model?.section = .sites
    }

    @objc func showConfigKeys(_ sender: Any?) {
        model?.section = .keys
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(newConfigItem(_:)):
            item.title = model?.section == .sites ? "New Site" : "New Key"
        case #selector(showConfigSites(_:)):
            item.state = model?.section == .sites ? .on : .off
        case #selector(showConfigKeys(_:)):
            item.state = model?.section == .keys ? .on : .off
        default:
            break
        }
        return validate(item.action)
    }

    private func validate(_ action: Selector?) -> Bool {
        guard let model, model.state == .editing else { return false }
        switch action {
        case #selector(newConfigItem(_:)):
            return model.section == .sites || !model.draft.freeKeys().isEmpty
        case #selector(saveConfig(_:)):
            return model.hasChanges && model.check.config != nil
        case #selector(deleteConfigItem(_:)):
            // While a field is being typed in, ⌫ is the field's.
            return model.canRemove && !(window?.firstResponder is NSText)
        default:
            return true
        }
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        switch model.state {
        case let .unreadable(problems):
            unreadable(problems)
        case .editing:
            NavigationSplitView {
                EditorSidebar(model: model)
                    .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 240)
            } content: {
                VStack(spacing: 0) {
                    banners
                    switch model.section {
                    case .sites: SiteList(model: model)
                    case .keys: KeyList(model: model)
                    }
                }
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 440)
            } detail: {
                switch model.section {
                case .sites:
                    if let id = model.selectedSite, model.draft.site(id) != nil {
                        SiteEditor(model: model, id: id).id(id)
                    } else {
                        EmptyNote(title: "Select a site", text: "Pick one in the list to edit it.")
                    }
                case .keys:
                    if let row = model.selectedKey, model.draft.key(row) != nil {
                        KeyEditor(model: model, row: row).id(row)
                    } else {
                        EmptyNote(title: "Select a key", text: "Pick one in the list to edit it.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if model.changedOutside {
            banner("The file changed outside this window.", button: "Reload") { model.load() }
        }
        let fileProblems = model.fileProblems
        if !fileProblems.isEmpty {
            banner(fileProblems.joined(separator: "\n"), button: nil) {}
        }
    }

    private func banner(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let button { Button(button, action: action) }
        }
        .padding(10)
        .background(Color.orange.opacity(0.15))
    }

    private func unreadable(_ problems: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CapsJump can't read its config").font(.headline)
            Text("Fix these in the file itself, then Reload. Until then the keys stay as they were.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(problems, id: \.self) { Text($0).font(.callout.monospaced()).textSelection(.enabled) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Open Config File") { ConfigFileOpener.open() }
                Button("Reload") { model.load() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .padding(.top, 40)
    }
}

/// Sites and Keys, each with its count (of matches while searching) and a mark when a row in
/// it needs fixing.
private struct EditorSidebar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        List(selection: Binding(get: { model.section }, set: { if let section = $0 { model.section = section } })) {
            row(.sites, "Sites", "globe", count: model.query.isEmpty ? model.draft.sites.count : model.siteLines.count, problem: !model.check.bySite.isEmpty)
            row(.keys, "Keys", "keyboard", count: model.query.isEmpty ? model.draft.keys.count : model.keyLines.count, problem: !model.check.byKey.isEmpty)
        }
        .listStyle(.sidebar)
    }

    private func row(_ section: EditorModel.Section, _ title: String, _ symbol: String, count: Int, problem: Bool) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if problem {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("needs fixing")
            }
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .tag(section)
    }
}

/// A form row: the field with its label, and under it its note or its problems in red.
struct FieldRow: View {
    let label: String
    @Binding var text: String
    let prompt: String
    var note: String?
    let problems: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: $text, prompt: Text(prompt))
            EditorNotes(note: note, problems: problems)
        }
    }
}

struct EditorNotes: View {
    let note: String?
    let problems: [String]

    var body: some View {
        if problems.isEmpty, let note {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(problems, id: \.self) { problem in
            Text(problem)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What a column shows when it has nothing to list or edit.
struct EmptyNote: View {
    let title: String
    let text: String
    var button: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.title3).foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button, action: action).padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
