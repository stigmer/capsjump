// The permissions CapsJump uses, read so the Welcome window can tick each the moment it is
// granted. Chrome's and the notifications' are asked on their own when the person presses
// their buttons, attributed to CapsJump itself; Chrome starts only for its button, since
// Automation can be asked for only while Chrome runs. Accessibility is never asked here:
// macOS shows its own request whenever CapsJump reads it without access (see Permissions),
// and that one request is the only ask. The login item is the Welcome window's switch.

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

    static var hasAccessibility: Bool {
        Permissions.accessibility == .granted
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
