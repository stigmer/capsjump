// The keys a shortcut can name and what the event tap sees for each. A name is a key's
// place on a US keyboard, held as its macOS virtual key code; f1–f12 also carry what
// Apple's top row sends without fn (brightness, Mission Control, media and volume), as
// measured on a Magic Keyboard, so `f1` works with and without fn. Every trigger belongs
// to one name, so a pressed key reads back as its name. Caps Lock itself reaches the tap
// as F18, through the HID mapping in `CapsLock`.

import Foundation

/// One thing the event tap can see a key as.
public enum KeyTrigger: Hashable, Sendable {
    /// A key-down or key-up carrying this virtual key code.
    case key(Int64)
    /// A system-defined media event (subtype 8) carrying this NX key type.
    case media(Int)
}

public enum KeyNames {
    /// Every key name, in the order a reader expects: letters, digits, function keys, arrows.
    public static let all: [String] = letters.map(\.0) + digits.map(\.0) + functionKeys.map(\.0) + arrows.map(\.0)

    /// How a picker shows a key: `G`, `5`, `F1`, `←`.
    public static func symbol(for name: String) -> String {
        ["left": "←", "right": "→", "up": "↑", "down": "↓"][name] ?? name.uppercased()
    }

    /// The triggers a name stands for, or nil for an unknown name.
    public static func triggers(for name: String) -> [KeyTrigger]? {
        table[name]
    }

    /// The name a trigger stands for, or nil for a key no name covers.
    public static func name(for trigger: KeyTrigger) -> String? {
        names[trigger]
    }

    private static let names: [KeyTrigger: String] = Dictionary(
        table.flatMap { name, triggers in triggers.map { ($0, name) } },
        uniquingKeysWith: { first, _ in first }
    )

    private static let table: [String: [KeyTrigger]] = {
        var table: [String: [KeyTrigger]] = [:]
        for (name, code) in letters + digits + arrows {
            table[name] = [.key(code)]
        }
        for (name, triggers) in functionKeys {
            table[name] = triggers
        }
        return table
    }()

    private static let letters: [(String, Int64)] = [
        ("a", 0x00), ("b", 0x0B), ("c", 0x08), ("d", 0x02), ("e", 0x0E), ("f", 0x03), ("g", 0x05),
        ("h", 0x04), ("i", 0x22), ("j", 0x26), ("k", 0x28), ("l", 0x25), ("m", 0x2E), ("n", 0x2D),
        ("o", 0x1F), ("p", 0x23), ("q", 0x0C), ("r", 0x0F), ("s", 0x01), ("t", 0x11), ("u", 0x20),
        ("v", 0x09), ("w", 0x0D), ("x", 0x07), ("y", 0x10), ("z", 0x06),
    ]

    private static let digits: [(String, Int64)] = [
        ("0", 0x1D), ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15),
        ("5", 0x17), ("6", 0x16), ("7", 0x1A), ("8", 0x1C), ("9", 0x19),
    ]

    private static let arrows: [(String, Int64)] = [
        ("left", 0x7B), ("right", 0x7C), ("down", 0x7D), ("up", 0x7E),
    ]

    /// The plain function key, then the top row's own event.
    private static let functionKeys: [(String, [KeyTrigger])] = [
        ("f1", [.key(0x7A), .key(145)]),   // brightness down
        ("f2", [.key(0x78), .key(144)]),   // brightness up
        ("f3", [.key(0x63), .key(160)]),   // Mission Control
        ("f4", [.key(0x76), .key(177)]),   // Spotlight
        ("f5", [.key(0x60), .key(176)]),   // Dictation
        ("f6", [.key(0x61), .key(178)]),   // Do Not Disturb
        ("f7", [.key(0x62), .media(20)]),  // rewind
        ("f8", [.key(0x64), .media(16)]),  // play or pause
        ("f9", [.key(0x65), .media(19)]),  // fast-forward
        ("f10", [.key(0x6D), .media(7)]),  // mute
        ("f11", [.key(0x67), .media(1)]),  // volume down
        ("f12", [.key(0x6F), .media(0)]),  // volume up
    ]
}

/// Caps Lock, which the mapping turns into F18: Caps Lock only toggles, so whether it is
/// held can't be known, while F18 is a plain key with a press and a release. The usages
/// are on the HID keyboard page (0x07).
public enum CapsLock {
    public static let usage: UInt64 = 0x7_0000_0039
    public static let targetUsage: UInt64 = 0x7_0000_006D
    /// kVK_F18: what Caps Lock arrives as once mapped.
    public static let keyCode: Int64 = 0x4F

    /// Whether a mapping entry is the one that turns Caps Lock into F18.
    public static func isMapping(source: UInt64, destination: UInt64) -> Bool {
        source == usage && destination == targetUsage
    }
}
