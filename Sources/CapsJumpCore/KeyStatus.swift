// What the app says about the keys, decided from its state in one place: the menu's first
// line, whether the menu-bar icon is filled (Caps Lock taken) and whether it carries the dot
// that asks for attention, and the one step that would move things on. The Welcome window,
// the menu and the answer to the app being opened again all read it. Not set up yet (no
// config), waiting for Accessibility, and a broken config ask for attention; a pause or a
// file with no keys is a choice and doesn't. A config whose last edit is broken adds a
// line, since the keys from the last good file keep working.

import Foundation

public struct KeyStatus: Sendable, Equatable {
    /// What would move things on, when something would.
    public enum NextStep: Sendable, Equatable {
        case allowAccessibility
        case chooseKeys
        case fixConfig
        case resume
    }

    /// The menu's first line.
    public let title: String
    /// Whether Caps Lock is taken, which the menu-bar icon shows filled.
    public let active: Bool
    /// Whether the icon carries the dot: something only the person can do is waiting.
    public let needsYou: Bool
    public let nextStep: NextStep?
    /// A second line when the last edit of the config is broken.
    public let problem: String?

    public init(title: String, active: Bool, needsYou: Bool = false, nextStep: NextStep? = nil, problem: String? = nil) {
        self.title = title
        self.active = active
        self.needsYou = needsYou
        self.nextStep = nextStep
        self.problem = problem
    }

    /// Whether CapsJump still has to be set up: no config yet, or keys waiting for
    /// Accessibility. The Welcome window opens by itself only then.
    public var needsSetup: Bool {
        nextStep == .allowAccessibility || nextStep == .chooseKeys
    }

    /// `config` is the last good config, nil when none was ever read.
    public static func of(paused: Bool, config: Config?, configBroken: Bool, tapRunning: Bool, accessibility: Bool) -> KeyStatus {
        guard let config else {
            if configBroken {
                return KeyStatus(title: "The config has a problem", active: false, needsYou: true, nextStep: .fixConfig)
            }
            return KeyStatus(title: "Not set up yet", active: false, needsYou: true, nextStep: accessibility ? .chooseKeys : .allowAccessibility)
        }
        let status = running(paused: paused, config: config, tapRunning: tapRunning)
        guard configBroken else { return status }
        return KeyStatus(
            title: status.title,
            active: status.active,
            needsYou: true,
            nextStep: .fixConfig,
            problem: "The config has a problem; Check Config lists it"
        )
    }

    /// What the last good config does on its own.
    private static func running(paused: Bool, config: Config, tapRunning: Bool) -> KeyStatus {
        guard config.takesCapsLock else {
            return KeyStatus(title: "No keys; Caps Lock works as usual", active: false)
        }
        if paused {
            return KeyStatus(title: "Paused; Caps Lock works as usual", active: false, nextStep: .resume)
        }
        guard tapRunning else {
            return KeyStatus(title: "Needs Accessibility; keys are off", active: false, needsYou: true, nextStep: .allowAccessibility)
        }
        let count = config.keys.count
        return KeyStatus(title: "On: \(count) \(count == 1 ? "key" : "keys") on Caps Lock", active: true)
    }
}
