// Every rule of the event tap: Caps Lock is swallowed, a bound key runs once, an unbound
// key does nothing while Caps Lock is held, a swallowed press swallows its key-up and
// repeats, and nothing is touched when no key is bound.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct KeyRulesTests {
    private let caps = KeyTrigger.key(CapsLock.keyCode)
    private let g = KeyTrigger.key(5)
    private let x = KeyTrigger.key(7)
    private let volumeUp = KeyTrigger.media(0)
    private let site = KeyAction.site("github")
    private let window = KeyAction.window(.maximize)

    private func rules() throws -> KeyRules {
        let config = try ConfigParser.parse("""
        sites:
          - name: github
            account: alex@acme.dev
            open: https://github.com/
        keys:
          g: { site: github }
          f12: { window: maximize }
        """)
        return KeyRules(bindings: KeyRules.bindings(for: config))
    }

    @Test func bindingsCoverEveryTriggerOfAName() throws {
        let bindings = try rules().bindings
        #expect(bindings == [g: site, .key(111): window, volumeUp: window])
    }

    @Test func capsLockItselfIsAlwaysSwallowed() throws {
        var rules = try rules()
        #expect(rules.decide(KeyEvent(caps, .down, capsHeld: true)) == .swallow)
        #expect(rules.decide(KeyEvent(caps, .down, isRepeat: true, capsHeld: true)) == .swallow)
        #expect(rules.decide(KeyEvent(caps, .up, capsHeld: false)) == .swallow)
    }

    @Test func aBoundKeyRunsOnceAndIsSwallowed() throws {
        var rules = try rules()
        #expect(rules.decide(KeyEvent(g, .down, capsHeld: true)) == .run(site))
        #expect(rules.decide(KeyEvent(g, .down, isRepeat: true, capsHeld: true)) == .swallow)
        #expect(rules.decide(KeyEvent(g, .down, isRepeat: true, capsHeld: true)) == .swallow)
        #expect(rules.decide(KeyEvent(g, .up, capsHeld: true)) == .swallow)
        #expect(rules.swallowed.isEmpty)
    }

    @Test func theTopRowRunsItsBinding() throws {
        var rules = try rules()
        #expect(rules.decide(KeyEvent(volumeUp, .down, capsHeld: true)) == .run(window))
        #expect(rules.decide(KeyEvent(volumeUp, .up, capsHeld: true)) == .swallow)
        #expect(rules.decide(KeyEvent(.key(111), .down, capsHeld: true)) == .run(window))
    }

    @Test func anUnboundKeyDoesNothingWhileCapsLockIsHeld() throws {
        var rules = try rules()
        #expect(rules.decide(KeyEvent(x, .down, capsHeld: true)) == .swallow)
        #expect(rules.decide(KeyEvent(x, .up, capsHeld: true)) == .swallow)
        #expect(rules.decide(KeyEvent(.media(7), .down, capsHeld: true)) == .swallow)
    }

    @Test func withoutCapsLockEverythingPasses() throws {
        var rules = try rules()
        #expect(rules.decide(KeyEvent(g, .down, capsHeld: false)) == .pass)
        #expect(rules.decide(KeyEvent(g, .down, isRepeat: true, capsHeld: false)) == .pass)
        #expect(rules.decide(KeyEvent(g, .up, capsHeld: false)) == .pass)
        #expect(rules.decide(KeyEvent(volumeUp, .down, capsHeld: false)) == .pass)
    }

    @Test func capsLockLetGoFirstStillSwallowsTheKeyUpAndRepeats() throws {
        var rules = try rules()
        #expect(rules.decide(KeyEvent(g, .down, capsHeld: true)) == .run(site))
        #expect(rules.decide(KeyEvent(caps, .up, capsHeld: false)) == .swallow)
        #expect(rules.decide(KeyEvent(g, .down, isRepeat: true, capsHeld: false)) == .swallow)
        #expect(rules.decide(KeyEvent(g, .up, capsHeld: false)) == .swallow)
        #expect(rules.decide(KeyEvent(g, .down, capsHeld: false)) == .pass)
    }

    /// A key-up missed (a password field held secure input) can't keep the key swallowed.
    @Test func aMissedKeyUpCannotStickAKey() throws {
        var rules = try rules()
        #expect(rules.decide(KeyEvent(g, .down, capsHeld: true)) == .run(site))
        #expect(rules.decide(KeyEvent(g, .down, capsHeld: false)) == .pass)
        #expect(rules.decide(KeyEvent(g, .up, capsHeld: false)) == .pass)
        #expect(rules.swallowed.isEmpty)
    }

    @Test func noBindingsTouchNothing() {
        var rules = KeyRules()
        #expect(rules.decide(KeyEvent(caps, .down, capsHeld: true)) == .pass)
        #expect(rules.decide(KeyEvent(g, .down, capsHeld: true)) == .pass)
        #expect(rules.decide(KeyEvent(g, .up, capsHeld: false)) == .pass)
    }

    @Test func aPressHeldAcrossAReloadThatDropsEveryKeyStillEndsSwallowed() throws {
        var rules = try rules()
        #expect(rules.decide(KeyEvent(g, .down, capsHeld: true)) == .run(site))
        rules.bindings = [:]
        #expect(rules.decide(KeyEvent(g, .up, capsHeld: false)) == .swallow)
        #expect(rules.decide(KeyEvent(g, .down, capsHeld: true)) == .pass)
    }
}

@Suite struct WindowLayoutTests {
    // A 1728x1117 primary screen with a 25pt menu bar and a 70pt Dock at the bottom, and a
    // 1920x1080 screen to its right, top-aligned.
    private let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let primaryVisible = CGRect(x: 0, y: 70, width: 1728, height: 1022)
    private let second = CGRect(x: 1728, y: 37, width: 1920, height: 1080)
    private let secondVisible = CGRect(x: 1728, y: 37, width: 1920, height: 1055)

    @Test func halvesAndMaximizeOnThePrimaryScreen() {
        #expect(WindowLayout.frame(.leftHalf, visible: primaryVisible, primaryHeight: 1117) == CGRect(x: 0, y: 25, width: 864, height: 1022))
        #expect(WindowLayout.frame(.rightHalf, visible: primaryVisible, primaryHeight: 1117) == CGRect(x: 864, y: 25, width: 864, height: 1022))
        #expect(WindowLayout.frame(.maximize, visible: primaryVisible, primaryHeight: 1117) == CGRect(x: 0, y: 25, width: 1728, height: 1022))
    }

    @Test func anOddWidthGivesTheExtraPointToTheRight() {
        let visible = CGRect(x: 0, y: 0, width: 1001, height: 500)
        #expect(WindowLayout.frame(.leftHalf, visible: visible, primaryHeight: 500).width == 500)
        #expect(WindowLayout.frame(.rightHalf, visible: visible, primaryHeight: 500) == CGRect(x: 500, y: 0, width: 501, height: 500))
    }

    @Test func aSecondScreenUsesItsOwnFrame() {
        #expect(WindowLayout.frame(.leftHalf, visible: secondVisible, primaryHeight: 1117) == CGRect(x: 1728, y: 25, width: 960, height: 1055))
    }

    @Test func theWindowStaysOnTheScreenHoldingMostOfIt() {
        let screens = [primary, second]
        // Accessibility frames: top-left origin.
        #expect(WindowLayout.screen(holding: CGRect(x: 100, y: 100, width: 800, height: 600), screens: screens, primaryHeight: 1117) == 0)
        #expect(WindowLayout.screen(holding: CGRect(x: 1600, y: 100, width: 800, height: 600), screens: screens, primaryHeight: 1117) == 1)
        #expect(WindowLayout.screen(holding: CGRect(x: 1300, y: 100, width: 800, height: 600), screens: screens, primaryHeight: 1117) == 0)
        #expect(WindowLayout.screen(holding: CGRect(x: 9000, y: 9000, width: 10, height: 10), screens: screens, primaryHeight: 1117) == 0)
    }

    @Test func flippingTwiceIsTheSameRect() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 400)
        #expect(WindowLayout.flip(WindowLayout.flip(rect, primaryHeight: 1117), primaryHeight: 1117) == rect)
    }
}
