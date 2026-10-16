// What `capsjump check` reports about the config and Chrome's profiles: every problem,
// for each site the profile and window label it resolves to, and for each key what it
// does: the app it finds, the site, the window position, or the app that opens its link.
// The disk and the link handlers are injected, so every line is tested.

import Foundation

public struct Finding: Sendable, Equatable {
    public enum Level: String, Sendable {
        case ok
        case note
        case problem
    }

    public let level: Level
    public let text: String

    public init(_ level: Level, _ text: String) {
        self.level = level
        self.text = text
    }
}

/// What the checkup may ask of this Mac.
public struct Lookup: Sendable {
    public let home: String
    public let exists: @Sendable (String) -> Bool
    /// The name of the app that opens a link, or nil when none does.
    public let linkHandler: @Sendable (URL) -> String?

    public init(home: String, exists: @escaping @Sendable (String) -> Bool, linkHandler: @escaping @Sendable (URL) -> String?) {
        self.home = home
        self.exists = exists
        self.linkHandler = linkHandler
    }
}

public enum Checkup {
    /// `configText` and `localState` are nil when their files are missing.
    public static func run(configText: String?, configPath: String, localState: Data?, localStatePath: String, lookup: Lookup) -> [Finding] {
        guard let configText else {
            return [Finding(.problem, "no config at \(configPath); run `capsjump init`")]
        }
        let config: Config
        do {
            config = try ConfigParser.parse(configText)
        } catch {
            return error.problems.map { Finding(.problem, "\(configPath): \($0)") }
        }
        if config.sites.isEmpty && config.keys.isEmpty {
            return [Finding(.note, "\(configPath) has no sites or keys yet")]
        }
        return sites(config, localState: localState, localStatePath: localStatePath) + keys(config, lookup: lookup)
    }

    private static func keys(_ config: Config, lookup: Lookup) -> [Finding] {
        guard config.takesCapsLock else {
            return [Finding(.ok, "no keys, so Caps Lock is left alone")]
        }
        return config.keys.map { binding in
            let line = "`\(binding.key)` → \(binding.action)"
            switch binding.action {
            case .site, .window:
                return Finding(.ok, line)
            case let .app(target):
                if let path = target.resolve(home: lookup.home, exists: lookup.exists) {
                    return Finding(.ok, "`\(binding.key)` → app \(path)")
                }
                switch target {
                case let .name(name):
                    let folders = AppTarget.searchFolders.joined(separator: ", ")
                    return Finding(.problem, "\(line): no \(name).app in \(folders); give its path instead")
                case .path:
                    return Finding(.problem, "\(line): nothing at \(target.candidates(home: lookup.home)[0])")
                }
            case let .url(url):
                guard let app = lookup.linkHandler(url) else {
                    return Finding(.note, "\(line): no installed app opens \(url.scheme ?? "these") links")
                }
                return Finding(.ok, "\(line) (opens in \(app))")
            }
        }
    }

    private static func sites(_ config: Config, localState: Data?, localStatePath: String) -> [Finding] {
        guard !config.sites.isEmpty else { return [] }
        guard let localState else {
            return [Finding(.problem, "Chrome's profile list is missing at \(localStatePath); has Chrome been opened on this Mac?")]
        }
        let catalog: ProfileCatalog
        do {
            catalog = try ProfileCatalog.parse(localState: localState)
        } catch {
            return [Finding(.problem, error.description)]
        }

        return config.sites.map { site in
            do {
                let target = try Resolver.resolve(site, in: catalog)
                let line = "\(site.name) → \(target.profile.directory), windows labelled “\(target.label)”"
                guard target.canFocus else {
                    let others = target.sharedLabelWith.map(\.directory).joined(separator: ", ")
                    return Finding(.note, "\(line); always opens a new tab, because \(others) carries the same label")
                }
                return Finding(.ok, line)
            } catch {
                return Finding(.problem, "\(site.name): \(error)")
            }
        }
    }
}
