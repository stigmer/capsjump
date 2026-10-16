// Opens a URL in one Chrome profile, the way `open -na "Google Chrome" --args
// --profile-directory=<dir> <url>` does: a new Chrome instance is asked for, which hands
// the URL to the running Chrome (a new tab in that profile's window, or a new window) or
// starts Chrome when none runs. Done through NSWorkspace, so no process is spawned.

import AppKit
import CapsJumpCore

@MainActor
public enum ChromeLauncher {
    public static var runningChrome: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Identity.chromeBundleID).first { !$0.isTerminated }
    }

    public static func open(_ url: URL, profileDirectory: String) async throws(ChromeError) {
        try await launch(arguments: ["--profile-directory=\(profileDirectory)", url.absoluteString], activates: true, newInstance: true)
    }

    /// Starts Chrome without asking it for any page, and waits until it runs.
    public static func start(timeout: Duration = .seconds(20)) async throws(ChromeError) -> NSRunningApplication {
        if let running = runningChrome { return running }
        try await launch(arguments: [], activates: false, newInstance: false)
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let running = runningChrome, running.isFinishedLaunching { return running }
            try? await Task.sleep(for: .milliseconds(200))
        }
        throw .launch("Chrome did not finish starting within \(timeout)")
    }

    private static func launch(arguments: [String], activates: Bool, newInstance: Bool) async throws(ChromeError) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Identity.chromeBundleID) else {
            throw .notInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = activates
        configuration.createsNewApplicationInstance = newInstance
        do {
            _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        } catch {
            throw .launch(error.localizedDescription)
        }
    }
}
