// An icon's tone from its pixels: one light tone, one dark tone, or neither, each pixel
// weighted by how opaque it is, and too little ink to judge counted as neither.

import Testing
@testable import CapsJumpCore

@Suite struct IconToneTests {
    /// `count` pixels of one RGBA color.
    private func pixels(_ count: Int, _ rgba: [UInt8]) -> [UInt8] {
        Array([[UInt8]](repeating: rgba, count: count).joined())
    }

    @Test func aWhiteMarkOnClearIsLight() {
        #expect(IconTone.of(rgba: pixels(100, [255, 255, 255, 255]) + pixels(156, [0, 0, 0, 0])) == .light)
    }

    @Test func aBlackMarkIsDark() {
        #expect(IconTone.of(rgba: pixels(100, [20, 20, 20, 255]) + pixels(156, [255, 255, 255, 0])) == .dark)
    }

    @Test func colorsAreNeither() {
        let gmail = pixels(30, [234, 67, 53, 255]) + pixels(30, [66, 133, 244, 255]) + pixels(30, [251, 188, 4, 255]) + pixels(30, [52, 168, 83, 255])
        #expect(IconTone.of(rgba: gmail + pixels(136, [0, 0, 0, 0])) == .mixed)
        #expect(IconTone.of(rgba: pixels(256, [217, 119, 87, 255])) == .mixed)
    }

    @Test func clearPixelsDoNotCountWhateverTheirColor() {
        #expect(IconTone.of(rgba: pixels(100, [255, 255, 255, 255]) + pixels(156, [0, 0, 0, 1])) == .light)
    }

    @Test func tooLittleInkIsNeither() {
        #expect(IconTone.of(rgba: pixels(10, [255, 255, 255, 255]) + pixels(246, [0, 0, 0, 0])) == .mixed)
        #expect(IconTone.of(rgba: []) == .mixed)
    }
}
