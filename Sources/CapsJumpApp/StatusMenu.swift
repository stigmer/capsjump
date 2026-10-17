// The menu-bar icon: CapsJump's own mark (packaging/menubar.svg) as a template image,
// so macOS colours it for the menu bar; dimmed while CapsJump doesn't have Caps Lock, and
// with a small dot while something waits on the person (not set up yet, Accessibility
// missing, a broken config), so a pause, which is a choice, never looks like a problem.
// Its menu opens with the version and what the keys are doing, then the one step that
// would move things on (Finish Setting Up…, Resume Keys, Fix the Config…); Pause shows
// only while there are keys to pause. Below: turn the tab in front of Chrome into a site
// with a key (while Chrome runs), the config's own window, the file itself in an editor
// (writing the starter file first when there is none), what `capsjump check` would show,
// the Welcome window, starting at login, About and Quit.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import CapsJumpSystem
import ServiceManagement

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let keys: Keys
    private let actions: Actions

    /// What the menu's items ask of the app.
    struct Actions {
        let addCurrentTab: @MainActor () -> Void
        /// Opens the config window; true picks the first row with a problem.
        let editConfig: @MainActor (_ showingProblems: Bool) -> Void
        let openWelcome: @MainActor () -> Void
        let quit: @MainActor () -> Void
    }

    init(keys: Keys, actions: Actions) {
        self.keys = keys
        self.actions = actions
        super.init()
        let menu = NSMenu()
        // Items are enabled by `menuNeedsUpdate`, not by whether their action has a target.
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    /// The mark from the bundle; Apple's Caps Lock symbol when run unbundled, in development.
    static let mark: NSImage? = {
        let image = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "capslock", accessibilityDescription: nil)
        image?.isTemplate = true
        image?.accessibilityDescription = "CapsJump"
        return image
    }()

    /// The mark with a dot at its lower right, cut free of the mark by a clear ring so it
    /// reads at 18 points; a template too, so it takes the menu bar's colour.
    private static let markWithDot: NSImage? = mark.map { mark in
        let image = NSImage(size: mark.size, flipped: false) { rect in
            mark.draw(in: rect)
            let radius = rect.width * 0.17
            let dot = NSRect(x: rect.maxX - radius * 2, y: rect.minY, width: radius * 2, height: radius * 2)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "CapsJump, needs you"
        return image
    }

    func refresh() {
        let status = keys.status
        item.button?.image = status.needsYou ? Self.markWithDot : Self.mark
        item.button?.appearsDisabled = !status.active
        item.button?.toolTip = "CapsJump \(AppVersion.current): \(status.title)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = keys.status
        menu.addItem(label("CapsJump \(AppVersion.current)"))
        menu.addItem(label(status.title))
        if let problem = status.problem {
            menu.addItem(label(problem))
        }
        menu.addItem(.separator())
        switch status.nextStep {
        case .allowAccessibility, .chooseKeys:
            menu.addItem(action("Finish Setting Up…", #selector(openWelcome)))
        case .fixConfig:
            menu.addItem(action("Fix the Config…", #selector(showProblems)))
        case .resume:
            menu.addItem(action("Resume Keys", #selector(resume)))
        case nil:
            break
        }
        if status.active {
            menu.addItem(action("Pause Keys", #selector(pause)))
        }
        if status.nextStep != nil || status.active {
            menu.addItem(.separator())
        }
        let addTab = action("Add Current Tab…", #selector(addTab))
        addTab.isEnabled = ChromeLauncher.runningChrome != nil
        menu.addItem(addTab)
        menu.addItem(action("Edit Config…", #selector(editConfig)))
        menu.addItem(action("Open Config File", #selector(openConfigFile)))
        menu.addItem(action("Check Config", #selector(checkConfig)))
        if !status.needsSetup {
            menu.addItem(action("Getting Started…", #selector(openWelcome)))
        }
        menu.addItem(.separator())
        let login = action("Start at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(action("About CapsJump", #selector(about)))
        menu.addItem(action("Quit CapsJump", #selector(quit), key: "q"))
    }

    private func label(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func pause() { keys.pause() }

    @objc private func resume() { keys.resume() }

    @objc private func toggleLogin() {
        LoginItem.set(SMAppService.mainApp.status != .enabled)
    }

    @objc private func quit() { actions.quit() }

    @objc private func addTab() { actions.addCurrentTab() }

    @objc private func editConfig() { actions.editConfig(false) }

    @objc private func showProblems() { actions.editConfig(true) }

    @objc private func openWelcome() { actions.openWelcome() }

    @objc private func about() { AboutPanel.show() }

    @objc private func openConfigFile() { ConfigFileOpener.open() }

    @objc private func checkConfig() {
        let configPath = Paths.config()
        let statePath = Paths.chromeLocalState()
        let findings = Checkup.run(
            configText: try? String(contentsOf: configPath, encoding: .utf8),
            configPath: configPath.path,
            localState: FileManager.default.contents(atPath: statePath.path),
            localStatePath: statePath.path,
            lookup: Lookup.thisMac
        ) + KeyState.findings(config: try? Inputs.config(), running: true)

        let alert = NSAlert()
        let problems = findings.filter { $0.level == .problem }.count
        alert.messageText = problems == 0 ? "The config is fine" : "The config has \(problems) \(problems == 1 ? "problem" : "problems")"
        alert.informativeText = findings.map { finding in
            switch finding.level {
            case .ok: "✓ \(finding.text)"
            case .note: "• \(finding.text)"
            case .problem: "✗ \(finding.text)"
            }
        }.joined(separator: "\n")
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Edit Config…")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            actions.editConfig(problems > 0)
        }
    }
}

/// The config in the editor that opens .yaml files, written as the starter first when there
/// is none.
@MainActor
enum ConfigFileOpener {
    static func open() {
        let url = Paths.config()
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = try? ConfigFile(url: url).write(StarterConfig.config(catalog: try? Inputs.profiles()), replacing: nil)
        }
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil, NSWorkspace.shared.open(url) { return }
        // No app claims .yaml files: plain text in TextEdit.
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Starting at login, as a login item of the app itself.
@MainActor
enum LoginItem {
    static func set(_ on: Bool) {
        let service = SMAppService.mainApp
        if on, service.status != .enabled {
            try? service.register()
        } else if !on, service.status == .enabled {
            try? service.unregister()
        }
    }
}
