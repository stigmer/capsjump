// What the Welcome window's "Try it" step says for a key heard in the window and for each
// kind of key that ran.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct WelcomeWordingTests {
    @Test func aHeardKeyIsNamedAsItIsPressed() {
        #expect(WelcomeWording.heard(.key(0x7B)) == "Heard Caps Lock + ←. Now click another window and press it again.")
        #expect(WelcomeWording.heard(.key(0x05)) == "Heard Caps Lock + G. Now click another window and press it again.")
        #expect(WelcomeWording.heard(.key(0x31)) == "Heard Caps Lock. Now click another window and press it again.")
    }

    @Test func eachKindOfKeySaysWhatItDid() {
        #expect(WelcomeWording.worked(.window(.leftHalf), frontApp: "Safari") == "Safari's window moved to the left half.")
        #expect(WelcomeWording.worked(.window(.maximize), frontApp: nil) == "The window moved to the whole screen.")
        #expect(WelcomeWording.worked(.app(.name("Terminal")), frontApp: nil) == "Terminal came forward.")
        #expect(WelcomeWording.worked(.app(.path("~/Applications/Obsidian.app")), frontApp: nil) == "Obsidian came forward.")
        #expect(WelcomeWording.worked(.site("github"), frontApp: nil) == "github is in front, in its Chrome account.")
        #expect(WelcomeWording.worked(.url(URL(string: "slack://open")!), frontApp: nil) == "The link opened.")
    }
}
