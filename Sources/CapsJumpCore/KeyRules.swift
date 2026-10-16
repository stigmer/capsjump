// What the event tap does with each key event, decided here so every rule is tested.
// Caps Lock arrives as F18 and is always swallowed. While it is held, every key press is
// swallowed and a bound key's action runs once, however long the key is held; a key-up is
// swallowed when its key-down was, even after Caps Lock is let go, and so are that key's
// repeats while it stays down, so no app sees half a key. Everything else passes
// untouched. Whether Caps Lock is held comes with each event, asked of the system, never
// remembered here, so a missed key-up can't leave keys swallowed.

import Foundation

public struct KeyEvent: Sendable, Equatable {
    public enum Phase: Sendable {
        case down
        case up
    }

    public let trigger: KeyTrigger
    public let phase: Phase
    /// An auto-repeated key-down.
    public let isRepeat: Bool
    /// Whether the system reports Caps Lock (as F18) down as this event arrives.
    public let capsHeld: Bool

    public init(_ trigger: KeyTrigger, _ phase: Phase, isRepeat: Bool = false, capsHeld: Bool) {
        self.trigger = trigger
        self.phase = phase
        self.isRepeat = isRepeat
        self.capsHeld = capsHeld
    }
}

public enum KeyDecision: Sendable, Equatable {
    case pass
    case swallow
    case run(KeyAction)
}

public struct KeyRules: Sendable {
    /// What each trigger runs; replaced whole when the config changes.
    public var bindings: [KeyTrigger: KeyAction]
    /// Keys whose key-down was swallowed and whose key-up hasn't come yet.
    public private(set) var swallowed: Set<KeyTrigger> = []

    public init(bindings: [KeyTrigger: KeyAction] = [:]) {
        self.bindings = bindings
    }

    /// Each bound key's triggers, all running its action.
    public static func bindings(for config: Config) -> [KeyTrigger: KeyAction] {
        var table: [KeyTrigger: KeyAction] = [:]
        for binding in config.keys {
            for trigger in KeyNames.triggers(for: binding.key) ?? [] {
                table[trigger] = binding.action
            }
        }
        return table
    }

    public mutating func decide(_ event: KeyEvent) -> KeyDecision {
        // No keys bound means Caps Lock isn't taken: a real F18 and everything else pass.
        if bindings.isEmpty && swallowed.isEmpty { return .pass }
        if event.trigger == .key(CapsLock.keyCode) { return .swallow }

        switch event.phase {
        case .up:
            return swallowed.remove(event.trigger) == nil ? .pass : .swallow
        case .down:
            // A key still held from a swallowed press keeps being swallowed as it repeats. A
            // fresh press of it means its key-up was missed, and starts over.
            if swallowed.contains(event.trigger) {
                if event.isRepeat { return .swallow }
                swallowed.remove(event.trigger)
            }
            guard event.capsHeld else { return .pass }
            swallowed.insert(event.trigger)
            guard !event.isRepeat, let action = bindings[event.trigger] else { return .swallow }
            return .run(action)
        }
    }
}
