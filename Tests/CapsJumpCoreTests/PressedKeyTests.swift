// What a key pressed into a key field means: Escape cancels, Delete clears only where a
// key can be turned off, a key held with a modifier or one without a name is refused with
// its reason, the row's own key changes nothing, another row's key is refused with what it
// does, and any other key is used, the top row and the arrows included.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct PressedKeyTests {
    private static let file = """
    sites:
      - name: github
        account: you@work.com
        open: https://github.com/
    keys:
      g: { site: github }
      a: { app: Slack }
      left: { window: left-half }
    """

    private let draft = ConfigDraft(ConfigReader.read(Self.file))

    /// The row holding `key`.
    private func row(_ key: String) throws -> Int {
        try #require(draft.keys.first { $0.key.key == key }).id
    }

    private func decide(_ trigger: KeyTrigger, _ modifiers: PressedKey.Modifiers = [], typed: String? = nil, row: Int?, clears: Bool = false) -> PressedKey.Outcome {
        PressedKey.decide(trigger, modifiers: modifiers, typed: typed, row: row, clears: clears, in: draft)
    }

    @Test func escapeCancels() throws {
        #expect(decide(.key(PressedKey.escape), row: try row("g")) == .cancel)
        #expect(decide(.key(PressedKey.escape), [.command], row: nil) == .cancel)
    }

    @Test func deleteClearsOnlyWhereAKeyCanBeTurnedOff() throws {
        let left = try row("left")
        #expect(decide(.key(PressedKey.delete), row: left, clears: true) == .clear)
        #expect(decide(.key(PressedKey.forwardDelete), row: left, clears: true) == .clear)
        #expect(decide(.key(PressedKey.delete), row: try row("g")) == .refused("Delete doesn't clear a key here. Press another key, or Escape."))
    }

    @Test(arguments: [PressedKey.Modifiers.command, .control, .option, .shift, [.command, .shift]])
    func aKeyWithAModifierIsRefused(modifiers: PressedKey.Modifiers) {
        #expect(decide(.key(0x0E), modifiers, typed: "e", row: nil) == .refused("Press the key alone; Caps Lock is CapsJump's only modifier."))
    }

    @Test(arguments: [
        (KeyTrigger.key(0x31), " " as String?, "Space"),
        (.key(0x24), "\r", "Return"),
        (.key(0x52), "0", "the keypad's 0"),
        (.key(0x69), nil, "F13"),
        (.key(0x2B), ",", "“,”"),
        (.key(0x0A), "§", "“§”"),
        (.media(99), nil, "that key"),
    ])
    func aKeyWithoutANameIsRefusedByName(trigger: KeyTrigger, typed: String?, named: String) {
        #expect(decide(trigger, typed: typed, row: nil) == .refused("CapsJump can't use \(named). It uses the letters, digits, F1–F12 and the arrows."))
    }

    @Test func theRowsOwnKeyChangesNothing() throws {
        #expect(decide(.key(0x05), row: try row("g")) == .same)
    }

    @Test func anotherRowsKeyIsRefusedWithWhatItDoes() throws {
        let slack = try row("a")
        #expect(decide(.key(0x05), row: slack) == .refused("G already jumps to github, you@work.com."))
        #expect(decide(.key(0x7B), row: slack) == .refused("← already moves the front window to the left half."))
        #expect(decide(.key(0x00), row: nil) == .refused("A already brings Slack forward."))
    }

    @Test func aFreeKeyIsUsed() throws {
        #expect(decide(.key(0x05), row: nil) == .refused("G already jumps to github, you@work.com."))
        #expect(decide(.key(0x0B), row: try row("g")) == .use("b"))
        #expect(decide(.key(0x7E), row: try row("left")) == .use("up"))
        // The top row without fn arrives from the tap as a media event.
        #expect(decide(.media(1), row: nil) == .use("f11"))
        #expect(decide(.key(0x67), row: nil) == .use("f11"))
    }

    @Test func eachOutcomeSaysWhatHappened() {
        #expect(PressedKey.Outcome.use("up").spoken == "Caps Lock plus Up Arrow, set")
        #expect(PressedKey.Outcome.use("g").spoken == "Caps Lock plus G, set")
        #expect(PressedKey.Outcome.cancel.spoken == "Cancelled")
        #expect(PressedKey.Outcome.refused("No.").spoken == "No.")
    }
}
