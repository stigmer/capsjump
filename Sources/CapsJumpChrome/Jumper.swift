// One jump, live: read the config and Chrome's profiles afresh (so edits need no reload),
// gather Chrome's windows and titles, let Core decide, and carry the decision out.

import AppKit
import CapsJumpCore

public enum Outcome: Sendable, Equatable, CustomStringConvertible {
    case focused(site: String, windowID: String, tabIndex: Int)
    case opened(site: String, profileDirectory: String, reason: OpenReason)

    public var description: String {
        switch self {
        case let .focused(site, windowID, tabIndex):
            "\(site): focused tab \(tabIndex) of window \(windowID)"
        case let .opened(site, profileDirectory, reason):
            "\(site): opened in \(profileDirectory) (\(reason.rawValue))"
        }
    }
}

public enum JumpError: LocalizedError, Equatable, CustomStringConvertible {
    case noConfig(path: String)
    case unreadable(path: String, reason: String)
    case config(ConfigError)
    case unknownSite(String, known: [String])
    case profiles(String)
    case resolve(site: String, ResolveError)
    case chrome(site: String, ChromeError)

    public var description: String {
        switch self {
        case let .noConfig(path):
            "no config at \(path); run `capsjump init`"
        case let .unreadable(path, reason):
            "could not read \(path): \(reason)"
        case let .config(error):
            "the config has problems (`capsjump check` lists them):\n\(error)"
        case let .unknownSite(name, known):
            "no site `\(name)` in the config" + (known.isEmpty ? "" : "; it has: \(known.joined(separator: ", "))")
        case let .profiles(reason):
            reason
        case let .resolve(site, error):
            "\(site): \(error)"
        case let .chrome(site, error):
            "\(site): \(error)"
        }
    }

    public var errorDescription: String? { description }
}

/// Reads the two files every jump and check starts from.
public enum Inputs {
    public static func config(at url: URL = Paths.config()) throws(JumpError) -> Config {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw .noConfig(path: url.path)
        } catch {
            throw .unreadable(path: url.path, reason: error.localizedDescription)
        }
        do {
            return try ConfigParser.parse(text)
        } catch {
            throw .config(error)
        }
    }

    public static func profiles(at url: URL = Paths.chromeLocalState()) throws(JumpError) -> ProfileCatalog {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw .profiles("Chrome's profile list is missing at \(url.path); has Chrome been opened on this Mac?")
        }
        do {
            return try ProfileCatalog.parse(localState: data)
        } catch {
            throw .profiles(error.description)
        }
    }
}

@MainActor
public final class Jumper {
    private var scripting: ChromeScripting?

    public init() {}

    public func jump(to name: String) async throws(JumpError) -> Outcome {
        let config = try Inputs.config()
        guard let site = config.site(named: name) else {
            throw .unknownSite(name, known: config.sites.map(\.name))
        }
        let catalog = try Inputs.profiles()
        let target: Target
        do {
            target = try Resolver.resolve(site, in: catalog)
        } catch {
            throw .resolve(site: name, error)
        }
        do {
            return try await perform(target)
        } catch {
            throw .chrome(site: name, error)
        }
    }

    private func perform(_ target: Target) async throws(ChromeError) -> Outcome {
        let chrome = ChromeLauncher.runningChrome
        var windows: [ChromeWindow] = []
        var axWindows: [AXWindow] = []
        var scripting: ChromeScripting?
        if let chrome, target.canFocus {
            axWindows = try ChromeAccessibility.windows(of: chrome)
            if self.scripting == nil {
                self.scripting = try ChromeScripting()
            }
            scripting = self.scripting
            windows = try scripting?.windows() ?? []
        }

        let action = try Jump.decide(
            target: target,
            chromeRunning: chrome != nil,
            windows: windows,
            titles: axWindows.map(\.title)
        ) { (id: String) throws(ChromeError) -> WindowTabs in
            guard let scripting else { throw .windowGone }
            return try scripting.tabs(windowID: id)
        }

        switch action {
        case let .focus(windowID, tabIndex, titleIndex):
            guard let scripting, let chrome else { throw .windowGone }
            try scripting.focus(windowID: windowID, tabIndex: tabIndex)
            chrome.activate()
            ChromeAccessibility.raise(axWindows[titleIndex].element)
            return .focused(site: target.site.name, windowID: windowID, tabIndex: tabIndex)
        case let .open(profileDirectory, url, reason):
            try await ChromeLauncher.open(url, profileDirectory: profileDirectory)
            return .opened(site: target.site.name, profileDirectory: profileDirectory, reason: reason)
        }
    }
}
