// The menu-bar icon: a Caps Lock symbol, filled while CapsJump has Caps Lock and outlined
// when it doesn't. Its menu says what the keys are doing, pauses and resumes them, opens
// the config in an editor (writing the starter file first when there is none), shows what
// `capsjump check` would, switches starting at login, and quits.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import CapsJumpSystem
import ServiceManagement

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let keys: Keys

    init(keys: Keys) {
        self.keys = keys
        super.init()
        let menu = NSMenu()
        // Items are enabled by `menuNeedsUpdate`, not by whether their action has a target.
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    func refresh() {
        let active = keys.status.active
        let image = NSImage(systemSymbolName: active ? "capslock.fill" : "capslock", accessibilityDescription: "CapsJump")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "CapsJump: \(keys.status.title)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = keys.status
        menu.addItem(label(status.title))
        if let problem = status.problem {
            menu.addItem(label(problem))
        }
        menu.addItem(.separator())
        if Pause.isOn {
            menu.addItem(action("Resume Keys", #selector(resume)))
        } else {
            let pause = action("Pause Keys", #selector(pause))
            pause.isEnabled = status.active
            menu.addItem(pause)
        }
        menu.addItem(action("Edit Config…", #selector(editConfig)))
        menu.addItem(action("Check Config", #selector(checkConfig)))
        menu.addItem(.separator())
        let login = action("Start at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
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

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func editConfig() {
        let url = Paths.config()
        if !FileManager.default.fileExists(atPath: url.path) {
            try? StarterConfig.render(catalog: try? Inputs.profiles()).write(to: url, atomically: true, encoding: .utf8)
        }
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil, NSWorkspace.shared.open(url) { return }
        // No app claims .yaml files: plain text in TextEdit.
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

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
            editConfig()
        }
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
