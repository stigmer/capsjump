// Runs the keys from launch to quit, and receives every capsjump:// link. Key actions and
// links run one at a time, in arrival order: a site jumps, an app comes forward, a window
// snaps, a link opens, `_setup` opens the Welcome window, and Add Current Tab reads Chrome
// before its window opens. The Welcome window also opens by itself: on a launch from
// Finder, Spotlight or login while CapsJump isn't set up (until the person has closed it
// once), when the app is opened again while it runs and isn't set up (set up, the config
// window opens instead), and once per launch when a jump or Add Current Tab fails for want
// of a permission. Apart from macOS's own Accessibility box, which macOS raises by itself,
// nothing asks for a permission until the person presses its button there.
// Every key that runs without a failure is reported to the Welcome window, whose last step
// waits for one.
// Quitting (from the menu bar too), logging out, SIGTERM and SIGINT all go through
// `applicationWillTerminate`, which gives Caps Lock back. Only CapsJump's own Quit items
// ask about unsaved edits in the config window first; a quit from outside never waits.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import CapsJumpSystem
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Identity.bundleID, category: "jump")
    private let jumper = Jumper()
    private let notifier = Notifier()
    private var tail: Task<Void, Never>?
    private var welcomeShownForFailure = false
    private var signalSources: [DispatchSourceSignal] = []
    private lazy var keys = Keys(notifier: notifier) { [weak self] action in
        self?.enqueue { [weak self] in await self?.run(action) }
    }
    private var menu: StatusMenu?
    private let addTab = AddTab()
    private let editor = Editor()
    private lazy var welcome = Welcome(keys: keys, notifier: notifier) { [weak self] showingProblems in
        self?.editor.open(showingProblems: showingProblems)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        notifier.install()
        // AppKit ends the process on these signals without terminating the app; route them
        // through terminate so the mapping is removed.
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install(quitTarget: self, quit: #selector(quitAsked(_:)))
        let menu = StatusMenu(keys: keys, actions: StatusMenu.Actions(
            addCurrentTab: { [weak self] in self?.addCurrentTab() },
            editConfig: { [weak self] showingProblems in self?.editor.open(showingProblems: showingProblems) },
            openWelcome: { [weak self] in self?.welcome.open() },
            quit: { [weak self] in self?.quitAsked(nil) }
        ))
        keys.onChange = { [weak self, weak menu] in
            menu?.refresh()
            self?.welcome.keysChanged()
        }
        notifier.openWelcome = { [weak self] in self?.welcome.open() }
        notifier.welcomeIsOpen = { [weak self] in self?.welcome.isOpen ?? false }
        editor.listening = keys.listening
        addTab.listening = keys.listening
        self.menu = menu
        keys.start()
        guard notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true else { return }
        if keys.status.needsSetup && !WelcomeMemory.closedOnce {
            logger.notice("launch: not set up yet; opening the Welcome window")
            welcome.open()
        }
    }

    /// Opened again from Finder or Spotlight while running: a menu-bar app answers with a
    /// window rather than nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if keys.status.needsSetup {
            welcome.open()
        } else {
            editor.open()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        keys.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            enqueue { [self] in await handle(url) }
        }
    }

    private func handle(_ url: URL) async {
        let link: Link
        do {
            link = try Link.parse(url)
        } catch {
            fail("\(error)")
            return
        }
        switch link {
        case .setup:
            logger.notice("setup requested")
            welcome.open()
        case .pause:
            keys.pause()
        case .resume:
            keys.resume()
        case let .site(name):
            await jump(to: name)
        }
    }

    private func run(_ action: KeyAction) async {
        logger.notice("key: \(action.description, privacy: .public)")
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
        do {
            switch action {
            case let .site(name):
                guard await jump(to: name) else { return }
            case let .app(target):
                try await Launcher.open(target)
            case let .url(url):
                try Launcher.open(url)
            case let .window(position):
                try WindowMover.move(position)
            }
            welcome.keyWorked(WelcomeWording.worked(action, frontApp: frontApp))
        } catch let error as LaunchError {
            fail(error.description)
        } catch let error as WindowError {
            fail(error.description, opensWelcome: error == .accessibilityDenied)
            if error == .accessibilityDenied { openWelcomeForFailure("A window key needed Accessibility.") }
        } catch {
            fail("\(error)")
        }
    }

    /// True when the jump landed; a link's jump has no one waiting on it.
    @discardableResult
    private func jump(to name: String) async -> Bool {
        let started = ContinuousClock.now
        do {
            let outcome = try await jumper.jump(to: name)
            let elapsed = ContinuousClock.now - started
            logger.notice("jump \(outcome.description, privacy: .public) in \(elapsed.milliseconds, privacy: .public) ms")
            return true
        } catch {
            fail(error.description, opensWelcome: error.isMissingPermission)
            if error.isMissingPermission {
                openWelcomeForFailure("The site \(name) needed \(error.missingPermission).")
            }
            return false
        }
    }

    /// The main menu's File › Open Config File, whichever window is in front.
    @objc func openConfigFile(_ sender: Any?) {
        ConfigFileOpener.open()
    }

    /// CapsJump's own Quit: settles unsaved edits first.
    @objc func quitAsked(_ sender: Any?) {
        guard editor.mayQuit() else { return }
        NSApp.terminate(nil)
    }

    private func addCurrentTab() {
        enqueue { [self] in
            do throws(ChromeError) {
                addTab.open(try FrontTabReader.read())
            } catch {
                fail(error.description, opensWelcome: error.isMissingPermission)
                if error.isMissingPermission {
                    openWelcomeForFailure("Add Current Tab needed \(error.missingPermission).")
                }
            }
        }
    }

    /// Opens the Welcome window for a key that failed for want of a permission, once per
    /// launch; the notification, clicked, opens it any time.
    private func openWelcomeForFailure(_ notice: String) {
        guard !welcomeShownForFailure else { return }
        welcomeShownForFailure = true
        welcome.open(notice: notice)
    }

    private func fail(_ message: String, opensWelcome: Bool = false) {
        logger.error("\(message, privacy: .public)")
        notifier.post(message, opensWelcome: opensWelcome)
    }

    /// Runs `job` after every job enqueued before it.
    private func enqueue(_ job: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await job()
        }
    }
}

extension JumpError {
    var isMissingPermission: Bool {
        if case let .chrome(_, error) = self { error.isMissingPermission } else { false }
    }

    var missingPermission: String {
        if case let .chrome(_, error) = self { error.missingPermission } else { "a permission" }
    }
}

extension ChromeError {
    var isMissingPermission: Bool {
        self == .accessibilityDenied || self == .automationDenied
    }

    /// The permission, as the Welcome window's rows name it.
    var missingPermission: String {
        self == .automationDenied ? "access to Chrome" : "Accessibility"
    }
}

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
