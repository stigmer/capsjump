// The keyboard side of the app, from launch to quit. It reads the config once, then again
// on every change the watcher reports; a good file swaps the bindings and takes or gives
// back Caps Lock to match, and a broken one keeps the last good bindings and says so once.
// Caps Lock is mapped only while the tap runs, so it never becomes a key that nothing
// handles, and `stop` gives it back. Without Accessibility the tap is refused; the keys
// then start by themselves within two seconds of it being granted.

import CapsJumpChrome
import CapsJumpCore
import CapsJumpSystem
import ApplicationServices
import Foundation
import os

@MainActor
final class Keys {
    private let logger = Logger(subsystem: Identity.bundleID, category: "keys")
    private let notifier: Notifier
    private let layer: KeyLayer
    private var watcher: ConfigWatcher?
    private var config: Config?
    private var lastNotice: String?
    private var permissionNoticeShown = false
    private var waitingForAccess: Task<Void, Never>?

    init(notifier: Notifier, onAction: @escaping @MainActor (KeyAction) -> Void) {
        self.notifier = notifier
        layer = KeyLayer(onAction: onAction)
    }

    /// Reads the config, starts watching it, and starts the tap when a key is bound. Safe
    /// to call again, as setup does once a permission is granted.
    func start() {
        if watcher == nil {
            let watcher = ConfigWatcher(file: Paths.config()) { [weak self] in self?.reload(quietWhenMissing: false) }
            watcher.start()
            self.watcher = watcher
        }
        reload(quietWhenMissing: true)
    }

    /// Gives Caps Lock back and stops the tap.
    func stop() {
        KeyMapping.apply(false)
        layer.stop()
    }

    private func reload(quietWhenMissing: Bool) {
        do {
            let config = try Inputs.config()
            self.config = config
            lastNotice = nil
            logger.notice("config read: \(config.keys.count, privacy: .public) keys")
        } catch {
            if case .noConfig = error, quietWhenMissing || config == nil {
                apply()
                return
            }
            let message = config == nil ? error.description : "\(error.description)\nThe keys stay as they were."
            logger.error("\(message, privacy: .public)")
            if message != lastNotice {
                lastNotice = message
                notifier.post(message)
            }
            return
        }
        apply()
    }

    private func apply() {
        let bindings = config.map(KeyRules.bindings(for:)) ?? [:]
        layer.update(bindings)
        guard config?.takesCapsLock == true else {
            KeyMapping.apply(false)
            return
        }
        guard layer.start() else {
            KeyMapping.apply(false)
            logger.error("the event tap was refused; Accessibility is missing")
            if !permissionNoticeShown {
                permissionNoticeShown = true
                notifier.post("CapsJump needs Accessibility for its keys; run `capsjump setup`")
            }
            waitForAccessibility()
            return
        }
        if !KeyMapping.apply(true) {
            logger.error("the system refused the Caps Lock mapping")
            notifier.post("macOS refused to let CapsJump take Caps Lock, so the keys do nothing")
        }
    }

    private func waitForAccessibility() {
        guard waitingForAccess == nil else { return }
        waitingForAccess = Task { [weak self] in
            while !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(2))
            }
            self?.waitingForAccess = nil
            self?.logger.notice("Accessibility granted; starting the keys")
            self?.apply()
        }
    }
}
