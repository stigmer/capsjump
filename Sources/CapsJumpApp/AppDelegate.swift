// Receives every capsjump:// link and runs them one at a time, in arrival order: a
// site link jumps, `_setup` asks for the permissions. Setup also runs by itself, once per
// launch, so the prompts come up without anyone typing `capsjump setup`: when the app
// is opened directly (not by a link) with a permission missing, and when a jump fails for
// want of one. A launch by a link never adds a second round to the setup it asked for.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Identity.bundleID, category: "jump")
    private let jumper = Jumper()
    private let notifier = Notifier()
    private var tail: Task<Void, Never>?
    private var setupShown = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        notifier.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true else { return }
        enqueue { [self] in
            if await Setup.somethingMissing(notifier: notifier) {
                logger.notice("launch: a permission is missing; running setup")
                await setup()
            }
        }
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
        case let .site(name):
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
    }

    private func setup() async {
        setupShown = true
        await Setup.run(notifier: notifier)
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
        switch self {
        case .chrome(_, .accessibilityDenied), .chrome(_, .automationDenied): true
        default: false
        }
    }
}

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
