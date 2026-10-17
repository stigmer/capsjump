// Reading a profile's saved picture from a profile folder built here: a 256-pixel PNG comes
// back as a PNG of 64, a smaller one as it is, and a missing file or one that isn't an
// image is no picture. No Chrome needed.

import CapsJumpCore
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CapsJumpChrome

@Suite struct ChromeProfilePictureTests {
    /// A home with a Chrome profile folder `Profile 1`.
    private static func home() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("picture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: ChromeProfilePicture.file(profile: "Profile 1", name: "x", home: home).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return home
    }

    /// A PNG of one colour, `side` pixels square, without alpha, as Chrome saves them.
    private static func png(side: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func side(of png: Data) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    @Test func aLargePictureComesBackSmall() throws {
        let file = ChromeProfilePicture.file(profile: "Profile 1", name: "Google Profile Picture.png", home: try Self.home())
        try Self.png(side: 256).write(to: file)
        let data = try ChromeProfilePicture.picture(in: file).get()
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(try Self.side(of: data) == (64, 64))
    }

    @Test func aSmallPictureKeepsItsSize() throws {
        let file = ChromeProfilePicture.file(profile: "Profile 1", name: "p.png", home: try Self.home())
        try Self.png(side: 32).write(to: file)
        #expect(try Self.side(of: ChromeProfilePicture.picture(in: file).get()) == (32, 32))
    }

    @Test func everyWayThereIsNoPicture() throws {
        let home = try Self.home()
        let missing = ChromeProfilePicture.file(profile: "Profile 1", name: "none.png", home: home)
        #expect(ChromeProfilePicture.picture(in: missing) == .failure(.noFile))
        let text = ChromeProfilePicture.file(profile: "Profile 1", name: "text.png", home: home)
        try Data("not a picture".utf8).write(to: text)
        #expect(ChromeProfilePicture.picture(in: text) == .failure(.notAnImage))
        let empty = ChromeProfilePicture.file(profile: "Profile 1", name: "empty.png", home: home)
        try Data().write(to: empty)
        #expect(ChromeProfilePicture.picture(in: empty) == .failure(.notAnImage))
    }
}
