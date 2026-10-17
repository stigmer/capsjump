// What a key pressed into a key field means, decided once for every field (Keys, Windows,
// Add Current Tab) and for both ways a key arrives: pressed alone in the window, or with
// Caps Lock and handed over by the event tap. Escape cancels; Delete clears where a key can
// be turned off; a key held with Command, Control, Option or Shift, a key CapsJump has no
// name for, and a key another row holds are refused with a sentence that says why, and the
// field goes on listening. The row's own key changes nothing. Each outcome carries the
// words VoiceOver announces.

import Foundation

public enum PressedKey {
    /// The modifiers held with a key pressed in the window; Caps Lock and fn are not among
    /// them, since Caps Lock is CapsJump's own and fn only reaches the top row.
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public enum Outcome: Sendable, Equatable {
        /// Set the key with this name.
        case use(String)
        /// The row's own key: nothing changes.
        case same
        case cancel
        /// Turn the key off.
        case clear
        /// Not set, and why.
        case refused(String)

        /// What VoiceOver says when the field hears the key.
        public var spoken: String {
            switch self {
            case let .use(name): "Caps Lock plus \(EditorRows.spokenKey(name)), set"
            case .same: "Unchanged"
            case .cancel: "Cancelled"
            case .clear: "Turned off"
            case let .refused(why): why
            }
        }
    }

    public static let escape: Int64 = 0x35
    public static let delete: Int64 = 0x33
    public static let forwardDelete: Int64 = 0x75
    public static let tab: Int64 = 0x30

    /// What the pressed key means for the field on `row` (nil for a key not set yet).
    /// `typed` is the character the key types, which names a key CapsJump has no name for;
    /// `clears` says whether Delete may turn the key off.
    public static func decide(_ trigger: KeyTrigger, modifiers: Modifiers, typed: String?, row: Int?, clears: Bool, in draft: ConfigDraft) -> Outcome {
        if trigger == .key(escape) { return .cancel }
        if trigger == .key(delete) || trigger == .key(forwardDelete) {
            return clears ? .clear : .refused("Delete doesn't clear a key here. Press another key, or Escape.")
        }
        if !modifiers.isEmpty {
            return .refused("Press the key alone; Caps Lock is CapsJump's only modifier.")
        }
        guard let name = KeyNames.name(for: trigger) else {
            return .refused("CapsJump can't use \(unusable(trigger, typed: typed)). It uses the letters, digits, F1–F12 and the arrows.")
        }
        if let row, draft.key(row)?.key.key == name { return .same }
        if let holder = draft.keys.first(where: { $0.key.key == name && $0.id != row }) {
            return .refused("\(KeyNames.symbol(for: name)) already \(EditorRows.key(holder, in: draft).doing).")
        }
        return .use(name)
    }

    /// How a refusal names a key CapsJump can't use: its own name when it types no
    /// character (or types one that would read as a usable key), else the character.
    static func unusable(_ trigger: KeyTrigger, typed: String?) -> String {
        if case let .key(code) = trigger, let name = unnamed[code] { return name }
        let character = typed?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)) ?? ""
        return character.isEmpty ? "that key" : "“\(character.uppercased())”"
    }

    private static let unnamed: [Int64: String] = {
        var table: [Int64: String] = [
            0x31: "Space", 0x24: "Return", 0x4C: "Enter", 0x30: "Tab", 0x73: "Home", 0x77: "End",
            0x74: "Page Up", 0x79: "Page Down", 0x72: "Help", 0x47: "Clear",
            0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17", 0x50: "F19", 0x5A: "F20",
            0x41: "the keypad's .", 0x43: "the keypad's *", 0x45: "the keypad's +", 0x4B: "the keypad's /",
            0x4E: "the keypad's -", 0x51: "the keypad's =",
        ]
        for (digit, code) in zip(0...9, [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C] as [Int64]) {
            table[code] = "the keypad's \(digit)"
        }
        return table
    }()
}
