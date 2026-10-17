// The names CapsJump is known by to macOS and the paths it reads. The bundle
// identifier is what macOS records Accessibility and Automation grants against, so it
// was fixed at CapsJump's first release (0.2.0) and never changes after it.

import Foundation

public enum Identity {
    public static let bundleID = "ai.stigmer.capsjump"
    public static let scheme = "capsjump"
    public static let chromeBundleID = "com.google.Chrome"
}

public enum Paths {
    /// `~/.capsjump.yaml`: a dotfile in the home folder, so it travels with the others.
    public static func config(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".capsjump.yaml")
    }

    /// Chrome's own folder, which holds `Local State` and a folder per profile.
    public static func chromeData(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Google/Chrome")
    }

    /// Chrome's `Local State`, which maps each profile folder to its account.
    public static func chromeLocalState(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        chromeData(home: home).appendingPathComponent("Local State")
    }
}
