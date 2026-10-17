// The permissions CapsJump asks for, each asked on its own when the person presses its
// button in the Welcome window, attributed to CapsJump itself, and each read without asking
// so the window can tick it the moment it is granted. Nothing here runs by itself: Chrome
// starts only for the Chrome button, since Automation can be asked for only while Chrome
// runs, and the login item is the Welcome window's switch.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import ServiceManagement

@MainActor
enum Setup {
    /// The System Settings panes the window links to.
    enum Pane: String {
        case accessibility = "com.apple.preference.security?Privacy_Accessibility"
        case automation = "com.apple.preference.security?Privacy_Automation"
        case notifications = "com.apple.preference.notifications"
        case loginItems = "com.apple.LoginItems-Settings.extension"
    }

    /// macOS's own request, which also lists CapsJump under Accessibility and offers to
    /// open System Settings.
    static func askForAccessibility() {
        _ = Permissions.accessibility(prompt: true)
    }

    static var hasAccessibility: Bool {
        Permissions.accessibility(prompt: false) == .granted
    }

    static var chromeInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Identity.chromeBundleID) != nil
    }

    /// Automation of Chrome as it stands; unknown while Chrome is closed.
    static func chromeAccess() async -> PermissionState {
        guard ChromeLauncher.runningChrome != nil else { return .unknown }
        return await Permissions.automation(ask: false)
    }

    /// Starts Chrome when it is closed, then asks for Automation of it.
    static func askForChrome() async throws(ChromeError) -> PermissionState {
        _ = try await ChromeLauncher.start()
        return await Permissions.automation(ask: true)
    }

    static func open(_ pane: Pane) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane.rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }
}
