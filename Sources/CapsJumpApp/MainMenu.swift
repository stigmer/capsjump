// While one of CapsJump's windows is open, CapsJump is an ordinary app: a Dock icon, a
// place in ⌘-Tab, and a small menu bar whose Edit menu is what makes ⌘C, ⌘V, ⌘Z and ⌘A
// work in a text field. File, Delete, Find and View are the config window's (new, save,
// remove, search, Sites and Keys); like every item here they go to the first responder, so
// the config window answers them and they grey out while another window is in front. After
// the last window closes CapsJump goes back to living in the menu bar alone.

import AppKit

@MainActor
enum MainMenu {
    /// `quit` on `quitTarget` is CapsJump's own Quit, which asks about unsaved edits.
    static func install(quitTarget: AnyObject, quit: Selector) {
        // CapsJump's windows are never tabs, so View has no tab items.
        NSWindow.allowsAutomaticWindowTabbing = false
        let quitItem = item("Quit CapsJump", quit, "q")
        quitItem.target = quitTarget
        let bar = NSMenu()
        bar.addItem(submenu("CapsJump", [
            item("Hide CapsJump", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            quitItem,
        ]))
        bar.addItem(submenu("File", [
            item("New", #selector(Editor.newConfigItem(_:)), "n"),
            item("Save", #selector(Editor.saveConfig(_:)), "s"),
            .separator(),
            item("Open Config File", #selector(AppDelegate.openConfigFile(_:)), ""),
        ]))
        let delete = item("Delete", #selector(Editor.deleteConfigItem(_:)), String(UnicodeScalar(NSBackspaceCharacter)!))
        delete.keyEquivalentModifierMask = []
        bar.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            delete,
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find", #selector(Editor.findConfigItem(_:)), "f"),
        ]))
        bar.addItem(submenu("View", [
            item("Sites", #selector(Editor.showConfigSites(_:)), "1"),
            item("Keys", #selector(Editor.showConfigKeys(_:)), "2"),
            item("Windows", #selector(Editor.showConfigWindows(_:)), "3"),
        ]))
        let window = submenu("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ])
        bar.addItem(window)
        NSApp.mainMenu = bar
        NSApp.windowsMenu = window.submenu
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// An item sent to the first responder, so it reaches whatever field has focus.
    private static func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}

/// CapsJump's open windows, and the app's place in the Dock that follows them.
@MainActor
enum AppWindows {
    private static var open: Set<ObjectIdentifier> = []

    static func show(_ window: NSWindow) {
        open.insert(ObjectIdentifier(window))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Called from each window's `windowWillClose`.
    static func closed(_ window: NSWindow) {
        open.remove(ObjectIdentifier(window))
        if open.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
