// What a shortcut does: bring an app forward, jump to a site, snap the front window, or
// open a link. Also where an app named by name is looked for, and which of its name and
// its path to write for an app picked by path, as pure searches over an injected "does
// this path exist", so they are tested without a disk.

import Foundation

public struct KeyBinding: Sendable, Equatable {
    /// The key's name, as `KeyNames` knows it.
    public let key: String
    public let action: KeyAction

    public init(key: String, action: KeyAction) {
        self.key = key
        self.action = action
    }
}

public enum KeyAction: Sendable, Equatable, CustomStringConvertible {
    case app(AppTarget)
    case site(String)
    case window(WindowPosition)
    case url(URL)

    public var description: String {
        switch self {
        case let .app(target): "app \(target)"
        case let .site(name): "site \(name)"
        case let .window(position): "window \(position.rawValue)"
        case let .url(url): "url \(url.absoluteString)"
        }
    }
}

/// The moves, in the order the config window lists them. `maximize` fills the visible
/// screen in place; it is not macOS full screen, which gives the window a Space of its own.
public enum WindowPosition: String, Sendable, CaseIterable {
    case leftHalf = "left-half"
    case rightHalf = "right-half"
    case topHalf = "top-half"
    case bottomHalf = "bottom-half"
    case maximize

    /// The key a new file binds to the move and the window suggests for it: the arrows and
    /// F, as macOS's own tiling places these moves on Fn-Control.
    public var suggestedKey: String {
        switch self {
        case .leftHalf: "left"
        case .rightHalf: "right"
        case .topHalf: "up"
        case .bottomHalf: "down"
        case .maximize: "f"
        }
    }
}

public enum AppTarget: Sendable, Equatable, CustomStringConvertible {
    /// An app's name, without `.app`: `Slack`.
    case name(String)
    /// A path to an .app as written, absolute or starting with `~/`.
    case path(String)

    /// The folders a name is looked for in, in order.
    public static let searchFolders = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "~/Applications",
        "/System/Library/CoreServices",
    ]

    /// A name (`Slack`, `Slack.app`) or a path ending in .app that starts with `/` or `~/`;
    /// nil for anything else.
    public static func parse(_ raw: String) -> AppTarget? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.contains("/") {
            let path = value.hasSuffix("/") ? String(value.dropLast()) : value
            guard path.hasPrefix("/") || path.hasPrefix("~/"), path.hasSuffix(".app"), path.count > 5 else { return nil }
            return .path(path)
        }
        let name = value.hasSuffix(".app") ? String(value.dropLast(4)) : value
        return name.isEmpty ? nil : .name(name)
    }

    public var description: String {
        switch self {
        case let .name(name): name
        case let .path(path): path
        }
    }

    /// The paths this target may be at, `~/` expanded against `home`.
    public func candidates(home: String) -> [String] {
        switch self {
        case let .path(path):
            [Self.expand(path, home: home)]
        case let .name(name):
            Self.searchFolders.map { "\(Self.expand($0, home: home))/\(name).app" }
        }
    }

    /// The first candidate that exists, or nil.
    public func resolve(home: String, exists: (String) -> Bool) -> String? {
        candidates(home: home).first(where: exists)
    }

    /// What to write for the app at `path`: its name when looking that name up finds this
    /// same app, so the file reads `Slack`; otherwise its path, with the home folder as `~/`.
    public static func preferred(forPath path: String, home: String, exists: (String) -> Bool) -> AppTarget {
        let path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        let file = path.split(separator: "/").last.map(String.init) ?? path
        let name = file.hasSuffix(".app") ? String(file.dropLast(4)) : file
        if !name.isEmpty, AppTarget.name(name).resolve(home: home, exists: exists) == path {
            return .name(name)
        }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        return path.hasPrefix(base + "/") ? .path("~" + path.dropFirst(base.count)) : .path(path)
    }

    static func expand(_ path: String, home: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        let base = home.hasSuffix("/") ? String(home.dropLast()) : home
        return base + path.dropFirst()
    }
}
