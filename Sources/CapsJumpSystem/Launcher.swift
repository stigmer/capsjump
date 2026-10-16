// Brings an app forward, launching it when it isn't running and reopening a window when it
// has none, as `open -a` does; and opens a link the way a clicked one opens: a deep link in
// the app that owns its scheme, a web page in the default browser.

import AppKit
import CapsJumpCore

public enum LaunchError: Error, Equatable, CustomStringConvertible {
    case appNotFound(AppTarget)
    case appFailed(path: String, reason: String)
    case noHandler(URL)

    public var description: String {
        switch self {
        case let .appNotFound(.name(name)):
            "no \(name).app in \(AppTarget.searchFolders.joined(separator: ", ")); give its path in the config"
        case let .appNotFound(target):
            "nothing at \(target)"
        case let .appFailed(path, reason):
            "\(path) didn't open: \(reason)"
        case let .noHandler(url):
            "no app opens \(url.scheme ?? "these") links, so \(url.absoluteString) didn't open"
        }
    }
}

@MainActor
public enum Launcher {
    public static func open(_ target: AppTarget) async throws(LaunchError) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let path = target.resolve(home: home, exists: { FileManager.default.fileExists(atPath: $0) }) else {
            throw .appNotFound(target)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
        } catch {
            throw .appFailed(path: path, reason: error.localizedDescription)
        }
    }

    public static func open(_ url: URL) throws(LaunchError) {
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil, NSWorkspace.shared.open(url) else {
            throw .noHandler(url)
        }
    }
}
