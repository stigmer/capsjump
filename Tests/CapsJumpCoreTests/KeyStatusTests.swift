// What the menu bar's first line and icon say in each state of the app.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct KeyStatusTests {
    private let twoKeys = Config(sites: [], keys: [
        KeyBinding(key: "f", action: .window(.maximize)),
        KeyBinding(key: "t", action: .app(.name("Terminal"))),
    ])
    private let noKeys = Config(sites: [])

    @Test func onCountsTheKeys() {
        #expect(KeyStatus.of(paused: false, config: twoKeys, configBroken: false, tapRunning: true)
            == KeyStatus(title: "On: 2 keys on Caps Lock", active: true))
        let one = Config(sites: [], keys: [KeyBinding(key: "f", action: .window(.maximize))])
        #expect(KeyStatus.of(paused: false, config: one, configBroken: false, tapRunning: true).title == "On: 1 key on Caps Lock")
    }

    @Test func pausedGivesCapsLockBack() {
        #expect(KeyStatus.of(paused: true, config: twoKeys, configBroken: false, tapRunning: true)
            == KeyStatus(title: "Paused; Caps Lock works as usual", active: false))
    }

    @Test func noKeysAndNoConfigTakeNothing() {
        #expect(KeyStatus.of(paused: false, config: noKeys, configBroken: false, tapRunning: false).title == "No keys yet; Caps Lock works as usual")
        #expect(KeyStatus.of(paused: false, config: nil, configBroken: false, tapRunning: false) == KeyStatus(title: "No config yet", active: false))
    }

    @Test func withoutTheTapTheKeysAreOff() {
        #expect(KeyStatus.of(paused: false, config: twoKeys, configBroken: false, tapRunning: false)
            == KeyStatus(title: "Needs Accessibility; keys are off", active: false))
    }

    @Test func aBrokenEditAddsALineAndKeepsTheKeys() {
        let status = KeyStatus.of(paused: false, config: twoKeys, configBroken: true, tapRunning: true)
        #expect(status.active)
        #expect(status.problem == "The config has a problem; Check Config lists it")
        #expect(KeyStatus.of(paused: false, config: nil, configBroken: true, tapRunning: false).title == "The config has a problem")
    }
}
