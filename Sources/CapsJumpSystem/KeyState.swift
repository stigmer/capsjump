// What the app and the CLI both read about the keys on this Mac: whether they are paused
// (kept in the app's preferences, so a pause outlives a restart and `capsjump check` can
// tell paused from broken), what `check` reports about the running app and the mapping,
// and the live lookup the checkup uses for apps and link handlers.

import AppKit
import CapsJumpCore
import Foundation

public enum Pause {
    private static let key = "paused"

    /// The app's own preferences: the standard domain inside the app, its suite outside it.
    private static var defaults: UserDefaults {
        if Bundle.main.bundleIdentifier == Identity.bundleID { return .standard }
        return UserDefaults(suiteName: Identity.bundleID) ?? .standard
    }

    public static var isOn: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

public enum KeyState {
    /// Whether the app runs and Caps Lock is mapped, when the config binds keys.
    public static func findings(config: Config?, running: Bool) -> [Finding] {
        let mapped = KeyMapping.isInPlace()
        guard config?.takesCapsLock == true else {
            return mapped ? [Finding(.note, "Caps Lock is still mapped though no key is bound; CapsJump gives it back when it next reads the config")] : []
        }
        let app = running
            ? Finding(.ok, "CapsJump.app is running")
            : Finding(.problem, "CapsJump.app is not running, so the keys do nothing; open it, or run `capsjump setup`")
        guard !Pause.isOn else {
            return [app, Finding(.note, "the keys are paused; resume them from the menu bar, or run `capsjump resume`")]
        }
        return [
            app,
            mapped
                ? Finding(.ok, "Caps Lock is mapped for the keys")
                : Finding(.problem, "Caps Lock isn't mapped, so the keys do nothing; CapsJump needs Accessibility (`capsjump setup`)"),
        ]
    }

    public static var appIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Identity.bundleID).isEmpty
    }
}

extension Lookup {
    /// This Mac's disk and link handlers.
    public static var thisMac: Lookup {
        Lookup(
            home: FileManager.default.homeDirectoryForCurrentUser.path,
            exists: { FileManager.default.fileExists(atPath: $0) },
            linkHandler: { url in
                NSWorkspace.shared.urlForApplication(toOpen: url).map { $0.deletingPathExtension().lastPathComponent }
            }
        )
    }
}
