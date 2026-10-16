// What the menu bar says about the keys, decided from the app's state: on (and how many),
// paused, nothing bound, no config yet, or waiting for Accessibility. A config whose last
// edit is broken adds a line, since the keys from the last good file keep working.

import Foundation

public struct KeyStatus: Sendable, Equatable {
    /// The menu's first line.
    public let title: String
    /// Whether Caps Lock is taken, which the menu-bar icon shows filled.
    public let active: Bool
    /// A second line when the last edit of the config is broken.
    public let problem: String?

    public init(title: String, active: Bool, problem: String? = nil) {
        self.title = title
        self.active = active
        self.problem = problem
    }

    /// `config` is the last good config, nil when none was ever read.
    public static func of(paused: Bool, config: Config?, configBroken: Bool, tapRunning: Bool) -> KeyStatus {
        let problem = configBroken ? "The config has a problem; Check Config lists it" : nil
        guard let config else {
            return KeyStatus(title: configBroken ? "The config has a problem" : "No config yet", active: false, problem: problem)
        }
        guard config.takesCapsLock else {
            return KeyStatus(title: "No keys yet; Caps Lock works as usual", active: false, problem: problem)
        }
        if paused {
            return KeyStatus(title: "Paused; Caps Lock works as usual", active: false, problem: problem)
        }
        guard tapRunning else {
            return KeyStatus(title: "Needs Accessibility; keys are off", active: false, problem: problem)
        }
        let count = config.keys.count
        return KeyStatus(title: "On: \(count) \(count == 1 ? "key" : "keys") on Caps Lock", active: true, problem: problem)
    }
}
