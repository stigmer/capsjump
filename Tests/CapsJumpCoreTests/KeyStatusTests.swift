// What the menu bar's first line and icon say in each state of the app, and the step each
// state asks for.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct KeyStatusTests {
    private let twoKeys = Config(sites: [], keys: [
        KeyBinding(key: "f", action: .window(.maximize)),
        KeyBinding(key: "t", action: .app(.name("Terminal"))),
    ])
    private let noKeys = Config(sites: [])

    private func status(
        paused: Bool = false,
        config: Config?,
        broken: Bool = false,
        tap: Bool = true,
        accessibility: Bool = true
    ) -> KeyStatus {
        KeyStatus.of(paused: paused, config: config, configBroken: broken, tapRunning: tap, accessibility: accessibility)
    }

    @Test func onCountsTheKeys() {
        #expect(status(config: twoKeys) == KeyStatus(title: "On: 2 keys on Caps Lock", active: true))
        let one = Config(sites: [], keys: [KeyBinding(key: "f", action: .window(.maximize))])
        #expect(status(config: one).title == "On: 1 key on Caps Lock")
    }

    @Test func noConfigIsNotSetUpAndAsksForTheNextStep() {
        #expect(status(config: nil, tap: false, accessibility: false)
            == KeyStatus(title: "Not set up yet", active: false, needsYou: true, nextStep: .allowAccessibility))
        #expect(status(config: nil, tap: false, accessibility: true)
            == KeyStatus(title: "Not set up yet", active: false, needsYou: true, nextStep: .chooseKeys))
        #expect(status(config: nil, tap: false).needsSetup)
    }

    @Test func pausedGivesCapsLockBackAndAsksNothing() {
        let paused = status(paused: true, config: twoKeys)
        #expect(paused == KeyStatus(title: "Paused; Caps Lock works as usual", active: false, nextStep: .resume))
        #expect(!paused.needsYou)
        #expect(!paused.needsSetup)
    }

    @Test func aFileWithNoKeysIsAChoice() {
        #expect(status(config: noKeys, tap: false, accessibility: false)
            == KeyStatus(title: "No keys; Caps Lock works as usual", active: false))
    }

    @Test func boundKeysWithoutTheTapWaitForAccessibility() {
        let waiting = status(config: twoKeys, tap: false, accessibility: false)
        #expect(waiting == KeyStatus(title: "Needs Accessibility; keys are off", active: false, needsYou: true, nextStep: .allowAccessibility))
        #expect(waiting.needsSetup)
    }

    @Test func aBrokenEditAddsALineKeepsTheKeysAndAsksForAFix() {
        let broken = status(config: twoKeys, broken: true)
        #expect(broken.active)
        #expect(broken.needsYou)
        #expect(broken.nextStep == .fixConfig)
        #expect(!broken.needsSetup)
        #expect(broken.problem == "The config has a problem; Check Config lists it")
        #expect(status(config: nil, broken: true, tap: false)
            == KeyStatus(title: "The config has a problem", active: false, needsYou: true, nextStep: .fixConfig))
    }
}
