// The CLI's helpers: which app receives capsjump:// links, whether the keys can work,
// the version of the bundle this binary ships in, and plain-text tables.

import AppKit
import ArgumentParser
import Foundation
import CapsJumpCore
import CapsJumpSystem

enum LinkHandler {
    /// The app macOS hands capsjump:// links to, or nil when none claims them.
    static var app: URL? {
        Link.url(forSite: "check").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    static func finding() -> Finding {
        guard let app else {
            return Finding(.problem, "no app receives \(Identity.scheme):// links; install CapsJump.app and open it once")
        }
        let id = Bundle(url: app)?.bundleIdentifier ?? "unknown"
        guard id == Identity.bundleID else {
            return Finding(.problem, "\(Identity.scheme):// links go to \(app.path) (\(id)), not CapsJump")
        }
        return Finding(.ok, "\(Identity.scheme):// links go to \(app.path)")
    }

    static func open(_ url: URL) throws {
        guard app != nil else {
            throw ValidationError("no app receives \(Identity.scheme):// links; install CapsJump.app and open it once")
        }
        guard NSWorkspace.shared.open(url) else {
            throw ValidationError("macOS did not open \(url.absoluteString)")
        }
    }
}

enum KeyState {
    /// Whether the app runs and Caps Lock is mapped, when the config binds keys.
    static func findings(config: Config?) -> [Finding] {
        let mapped = KeyMapping.isInPlace()
        guard config?.takesCapsLock == true else {
            return mapped ? [Finding(.note, "Caps Lock is still mapped though no key is bound; CapsJump gives it back when it next reads the config")] : []
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Identity.bundleID).isEmpty
        return [
            running
                ? Finding(.ok, "CapsJump.app is running")
                : Finding(.problem, "CapsJump.app is not running, so the keys do nothing; open it, or run `capsjump setup`"),
            mapped
                ? Finding(.ok, "Caps Lock is mapped for the keys")
                : Finding(.problem, "Caps Lock isn't mapped, so the keys do nothing; CapsJump needs Accessibility (`capsjump setup`)"),
        ]
    }
}

enum Version {
    /// The version in the Info.plist of the CapsJump.app this binary sits in
    /// (Contents/Helpers/capsjump), following Homebrew's symlink to it.
    static var current: String {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return "dev" }
        let plist = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOf: plist), let version = info["CFBundleShortVersionString"] as? String else {
            return "dev (not inside CapsJump.app)"
        }
        return version
    }
}

enum Table {
    static func render(header: [String], rows: [[String]]) -> String {
        let all = [header] + rows
        let widths = header.indices.map { column in all.map { $0[column].count }.max() ?? 0 }
        return all.map { row in
            row.enumerated().map { column, cell in
                column == row.count - 1 ? cell : cell.padding(toLength: widths[column] + 2, withPad: " ", startingAt: 0)
            }.joined()
        }.joined(separator: "\n")
    }
}

extension Lookup {
    /// This Mac's disk and link handlers.
    static var thisMac: Lookup {
        Lookup(
            home: FileManager.default.homeDirectoryForCurrentUser.path,
            exists: { FileManager.default.fileExists(atPath: $0) },
            linkHandler: { url in
                NSWorkspace.shared.urlForApplication(toOpen: url).map { $0.deletingPathExtension().lastPathComponent }
            }
        )
    }
}
