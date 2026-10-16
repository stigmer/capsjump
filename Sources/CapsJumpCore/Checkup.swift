// What `capsjump check` reports about the config and Chrome's profiles: every problem,
// and for each site the profile and window label it resolves to.

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

public enum Checkup {
    /// `configText` and `localState` are nil when their files are missing.
    public static func run(configText: String?, configPath: String, localState: Data?, localStatePath: String) -> [Finding] {
        guard let configText else {
            return [Finding(.problem, "no config at \(configPath); run `capsjump init`")]
        }
        let config: Config
        do {
            config = try ConfigParser.parse(configText)
        } catch {
            return error.problems.map { Finding(.problem, "\(configPath): \($0)") }
        }
        guard let localState else {
            return [Finding(.problem, "Chrome's profile list is missing at \(localStatePath); has Chrome been opened on this Mac?")]
        }
        let catalog: ProfileCatalog
        do {
            catalog = try ProfileCatalog.parse(localState: localState)
        } catch {
            return [Finding(.problem, error.description)]
        }
        guard !config.sites.isEmpty else {
            return [Finding(.note, "\(configPath) has no sites yet")]
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
