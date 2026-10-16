// The one way CapsJump reads and saves ~/.capsjump.yaml. A save refuses when the file no
// longer holds what the window started from, so an edit made elsewhere is never silently
// overwritten; it writes through a symlink to the file it points to, as dotfile managers
// expect, by moving a finished copy over that file in one rename, keeping its permissions;
// and it parses what it is about to write first, so it never writes a file CapsJump itself
// would refuse. The check and the rename are two steps: a write landing between them is
// lost, and the watcher then just reloads.

import Darwin
import Foundation
import CapsJumpCore

public struct ConfigFile: Sendable {
    public let url: URL

    public init(url: URL = Paths.config()) {
        self.url = url
    }

    public struct Contents: Sendable, Equatable {
        public let text: String
        /// The config, or every problem in it.
        public let result: Result<Config, ConfigError>
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// The file isn't what the save started from.
        case changedOnDisk(path: String)
        case readOnly(path: String)
        /// What would have been written doesn't parse; nothing was written.
        case refused(ConfigError)
        case failed(path: String, reason: String)

        public var description: String {
            switch self {
            case let .changedOnDisk(path): "\(path) changed since it was opened, so it was left as it is; reload it and try again"
            case let .readOnly(path): "\(path) is read-only, so it was left as it is"
            case let .refused(error): "CapsJump couldn't read back what it was about to save, so nothing was saved: \(error)"
            case let .failed(path, reason): "couldn't save \(path): \(reason)"
            }
        }
    }

    /// The file's text and what it says, or nil when there is no file.
    public func read() throws(Failure) -> Contents? {
        guard let text = try current(at: url) else { return nil }
        return Contents(text: text, result: Result { () throws(ConfigError) in try ConfigParser.parse(text) })
    }

    /// Saves `config` as CapsJump writes it, replacing a file that holds exactly `expected`,
    /// or creating one when `expected` is nil; returns the text written.
    @discardableResult
    public func write(_ config: Config, replacing expected: String?) throws(Failure) -> String {
        let text = ConfigWriter.render(config)
        do {
            _ = try ConfigParser.parse(text)
        } catch {
            throw .refused(error)
        }
        let target = Self.followingLinks(url)
        guard try current(at: target) == expected else {
            throw .changedOnDisk(path: url.path)
        }
        let manager = FileManager.default
        var attributes: [FileAttributeKey: Any] = [:]
        if expected != nil {
            guard manager.isWritableFile(atPath: target.path) else { throw .readOnly(path: url.path) }
            if let permissions = try? manager.attributesOfItem(atPath: target.path)[.posixPermissions] {
                attributes[.posixPermissions] = permissions
            }
        }

        let folder = target.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString)")
        guard manager.createFile(atPath: temporary.path, contents: Data(text.utf8), attributes: attributes) else {
            throw .failed(path: url.path, reason: "can't write in \(folder.path)")
        }
        guard rename(temporary.path, target.path) == 0 else {
            let reason = String(cString: strerror(errno))
            unlink(temporary.path)
            throw .failed(path: url.path, reason: reason)
        }
        return text
    }

    /// The text at `file`, or nil when nothing is there.
    private func current(at file: URL) throws(Failure) -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw .failed(path: url.path, reason: error.localizedDescription)
        }
    }

    /// The file a chain of symlinks ends at, or `file` itself.
    static func followingLinks(_ file: URL) -> URL {
        var current = file
        for _ in 0 ..< 32 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else { break }
            current = URL(fileURLWithPath: destination, relativeTo: current.deletingLastPathComponent()).standardizedFileURL
        }
        return current
    }
}
