// Runs the keys from launch to quit, and receives every capsjump:// link. Key actions and
// links run one at a time, in arrival order: a site jumps, an app comes forward, a window
// snaps, a link opens, `_setup` asks for the permissions, and Add Current Tab reads Chrome
// before its window opens. Setup also runs by itself,
// once per launch, so the prompts come up without anyone typing `capsjump setup`: when the
// app is opened directly (not by a link) with a permission missing, and when a jump fails
// for want of one (or Add Current Tab does). A launch by a link never adds a second round
// to the setup it asked for.
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
    private var setupShown = false
    private var signalSources: [DispatchSourceSignal] = []
    private lazy var keys = Keys(notifier: notifier) { [weak self] action in
        self?.enqueue { [weak self] in await self?.run(action) }
    }
    private var menu: StatusMenu?
    private let addTab = AddTab()
    private let editor = Editor()

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
            editConfig: { [weak self] in self?.editor.open() },
            quit: { [weak self] in self?.quitAsked(nil) }
        ))
        keys.onChange = { [weak menu] in menu?.refresh() }
        self.menu = menu
        keys.start()
        guard notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true else { return }
        enqueue { [self] in
            if await Setup.somethingMissing(notifier: notifier) {
                logger.notice("launch: a permission is missing; running setup")
                await setup()
            }
        }
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
            await setup()
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
        do {
            switch action {
            case let .site(name):
                await jump(to: name)
            case let .app(target):
                try await Launcher.open(target)
            case let .url(url):
                try Launcher.open(url)
            case let .window(position):
                try WindowMover.move(position)
            }
        } catch let error as LaunchError {
            fail(error.description)
        } catch let error as WindowError {
            fail(error.description)
        } catch {
            fail("\(error)")
        }
    }

    private func jump(to name: String) async {
        let started = ContinuousClock.now
        do {
            let outcome = try await jumper.jump(to: name)
            let elapsed = ContinuousClock.now - started
            logger.notice("jump \(outcome.description, privacy: .public) in \(elapsed.milliseconds, privacy: .public) ms")
        } catch {
            fail(error.description)
            if error.isMissingPermission && !setupShown {
                await setup()
            }
        }
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
                fail(error.description)
                if error.isMissingPermission && !setupShown {
                    await setup()
                }
            }
        }
    }

    private func setup() async {
        setupShown = true
        await Setup.run(notifier: notifier)
        keys.start()
    }

    private func fail(_ message: String) {
        logger.error("\(message, privacy: .public)")
        notifier.post(message)
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
}

extension ChromeError {
    var isMissingPermission: Bool {
        self == .accessibilityDenied || self == .automationDenied
    }
}

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
