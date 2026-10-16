// From a site in the config to the Chrome profile it lives in and the label that profile's
// window titles end with.

import Foundation

public struct Target: Sendable, Equatable {
    public let site: Site
    public let profile: ChromeProfile
    /// Other profiles whose windows carry the same label. While any exist, no window can be
    /// told apart from theirs, so the site is always opened rather than focused.
    public let sharedLabelWith: [ChromeProfile]

    public var label: String { profile.windowLabel }
    public var canFocus: Bool { sharedLabelWith.isEmpty }
}

public enum ResolveError: Error, Equatable, CustomStringConvertible {
    case account(ProfileCatalog.LookupError)
    case unknownProfile(directory: String, known: [String])
    case accountMismatch(account: String, directory: String)

    public var description: String {
        switch self {
        case let .account(error):
            error.description
        case let .unknownProfile(directory, known):
            "no Chrome profile folder `\(directory)`; this Mac has: \(known.joined(separator: ", "))"
        case let .accountMismatch(account, directory):
            "`\(directory)` is not the account `\(account)`; fix one of them"
        }
    }
}

public enum Resolver {
    /// `profile:` wins when given, and must then agree with `account:` if that is given too;
    /// otherwise the account picks the profile.
    public static func resolve(_ site: Site, in catalog: ProfileCatalog) throws(ResolveError) -> Target {
        let profile: ChromeProfile
        if let directory = site.profile {
            guard let found = catalog.profile(directory: directory) else {
                throw .unknownProfile(directory: directory, known: catalog.profiles.map(\.directory))
            }
            if let account = site.account?.lowercased(),
               found.email.lowercased() != account, found.name.lowercased() != account {
                throw .accountMismatch(account: site.account ?? "", directory: directory)
            }
            profile = found
        } else {
            do {
                profile = try catalog.profile(account: site.account ?? "")
            } catch {
                throw .account(error)
            }
        }
        return Target(site: site, profile: profile, sharedLabelWith: catalog.sharingLabel(with: profile))
    }
}
