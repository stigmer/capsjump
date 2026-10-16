// Chrome's profiles as its `Local State` file lists them, and the lookup from a site's
// account to one profile folder. Chrome's scripting interface never says which profile a
// window belongs to; the window title does, ending in the profile's label, so each
// profile's label is derived here the way Chrome writes it: `<given name> (<profile
// name>)` for a signed-in account, the bare profile name otherwise.

import Foundation

public struct ChromeProfile: Sendable, Equatable {
    /// The folder under Chrome's data directory: `Default`, `Profile 26`.
    public let directory: String
    /// The profile's name as shown in Chrome's profile menu.
    public let name: String
    /// The signed-in account's email, or empty when no account is signed in.
    public let email: String
    /// The signed-in account's given name, or empty.
    public let givenName: String

    public init(directory: String, name: String, email: String, givenName: String) {
        self.directory = directory
        self.name = name
        self.email = email
        self.givenName = givenName
    }

    /// The text every one of this profile's window titles ends with, after `– `.
    public var windowLabel: String {
        email.isEmpty || givenName.isEmpty ? name : "\(givenName) (\(name))"
    }
}

public struct ProfileCatalog: Sendable, Equatable {
    /// In Chrome's own order (its profile menu), or by folder when Chrome records none.
    public let profiles: [ChromeProfile]

    public init(profiles: [ChromeProfile]) {
        self.profiles = profiles
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case notJSON
        case noProfiles

        public var description: String {
            switch self {
            case .notJSON: "Chrome's Local State is not readable JSON"
            case .noProfiles: "Chrome's Local State lists no profiles"
            }
        }
    }

    /// Parses Chrome's `Local State` (JSON); only `profile.info_cache` and
    /// `profile.profiles_order` are read.
    public static func parse(localState data: Data) throws(ParseError) -> ProfileCatalog {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .notJSON
        }
        guard let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]], !cache.isEmpty
        else { throw .noProfiles }

        var profiles = cache.map { directory, info in
            ChromeProfile(
                directory: directory,
                name: info["name"] as? String ?? directory,
                email: info["user_name"] as? String ?? "",
                givenName: info["gaia_given_name"] as? String ?? ""
            )
        }
        let order = profile["profiles_order"] as? [String] ?? []
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        profiles.sort { a, b in
            switch (rank[a.directory], rank[b.directory]) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.directory.localizedStandardCompare(b.directory) == .orderedAscending
            }
        }
        return ProfileCatalog(profiles: profiles)
    }

    public func profile(directory: String) -> ChromeProfile? {
        profiles.first { $0.directory == directory }
    }

    /// The profiles other than `profile` whose windows carry the same label, so no
    /// window title can tell them apart.
    public func sharingLabel(with profile: ChromeProfile) -> [ChromeProfile] {
        profiles.filter { $0.directory != profile.directory && $0.windowLabel == profile.windowLabel }
    }

    public enum LookupError: Error, Equatable, CustomStringConvertible {
        case notFound(account: String, known: [String])
        case ambiguous(account: String, directories: [String])

        public var description: String {
            switch self {
            case let .notFound(account, known):
                "no Chrome profile has the account `\(account)`; this Mac has: \(known.joined(separator: ", "))"
            case let .ambiguous(account, directories):
                "`\(account)` matches the profiles \(directories.map { "`\($0)`" }.joined(separator: " and ")); name one with `profile:`"
            }
        }
    }

    /// The one profile for an account: by signed-in email first, then by profile name,
    /// ignoring case. Profiles signed out of Chrome keep their email only in the name.
    public func profile(account: String) throws(LookupError) -> ChromeProfile {
        let wanted = account.lowercased()
        let byEmail = profiles.filter { !$0.email.isEmpty && $0.email.lowercased() == wanted }
        let byName = profiles.filter { $0.name.lowercased() == wanted }
        for candidates in [byEmail, byName] where !candidates.isEmpty {
            guard candidates.count == 1 else {
                throw .ambiguous(account: account, directories: candidates.map(\.directory))
            }
            return candidates[0]
        }
        throw .notFound(account: account, known: profiles.map { $0.email.isEmpty ? $0.name : $0.email })
    }
}
