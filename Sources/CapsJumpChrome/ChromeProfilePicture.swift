// A Chrome profile's Google picture, read from the file Chrome has already saved in the
// profile's folder (a 256-pixel PNG when written), made small enough for a list row and a
// menu. Nothing goes over the network: Local State also names the URL Chrome downloaded it
// from, and that is never read. The picture is decoded at its small size, never whole, and
// written back as a PNG, so what crosses to the window is bytes. A file that is missing or
// isn't an image is no picture; what's drawn then is Chrome's own outline, decided by the
// window.

import CapsJumpCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ChromeProfilePicture {
    public enum Missing: Error, Equatable, CustomStringConvertible {
        case noFile
        case notAnImage

        public var description: String {
            switch self {
            case .noFile: "the profile has no saved picture"
            case .notAnImage: "the profile's saved picture is not an image"
            }
        }
    }

    /// The largest side kept, in pixels: 16 points at twice the screen's scale, with room.
    public static let largest = 64

    /// The picture file of a Chrome profile folder such as `Profile 1`.
    public static func file(profile: String, name: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        Paths.chromeData(home: home).appendingPathComponent(profile).appendingPathComponent(name)
    }

    /// The picture as a PNG of at most `largest` pixels a side.
    public static func picture(in file: URL) -> Result<Data, Missing> {
        guard FileManager.default.fileExists(atPath: file.path) else { return .failure(.noFile) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: largest,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return .failure(.notAnImage) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return .failure(.notAnImage)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return .failure(.notAnImage) }
        return .success(data as Data)
    }
}
