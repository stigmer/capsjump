// Asks for all three permissions at once, attributed to CapsJump itself, then shows
// one alert with each permission's state. Automation can be asked for only while Chrome
// runs, so setup starts Chrome first when it is closed.

import AppKit
import CapsJumpChrome
import CapsJumpCore

@MainActor
enum Setup {
    /// True when a permission is known to be missing. Automation reads as unknown while
    /// Chrome is closed and does not count.
    static func somethingMissing(notifier: Notifier) async -> Bool {
        if Permissions.accessibility(prompt: false) != .granted { return true }
        if [.denied, .notAsked].contains(await Permissions.automation(ask: false)) { return true }
        return await notifier.state == .notAsked
    }

    static func run(notifier: Notifier) async {
        let accessibility = Permissions.accessibility(prompt: true)
        var automation = PermissionState.unknown
        var chromeProblem: String?
        do {
            _ = try await ChromeLauncher.start()
            automation = await Permissions.automation(ask: true)
        } catch {
            chromeProblem = error.description
        }
        let notifications = await notifier.request()
        show(accessibility: accessibility, automation: automation, chromeProblem: chromeProblem, notifications: notifications)
    }

    private static func show(accessibility: PermissionState, automation: PermissionState, chromeProblem: String?, notifications: PermissionState) {
        let alert = NSAlert()
        let ready = accessibility == .granted && automation == .granted
        alert.messageText = ready ? "CapsJump is ready" : "CapsJump needs a permission"
        var lines = [
            "Accessibility: \(accessibility.rawValue)",
            "Automation of Chrome: \(chromeProblem ?? automation.rawValue)",
            "Notifications: \(notifications.rawValue)",
        ]
        if accessibility != .granted {
            lines.append("\nTurn CapsJump on under Privacy & Security › Accessibility.")
        }
        if automation == .denied {
            lines.append("\nTurn on Google Chrome under CapsJump in Privacy & Security › Automation.")
        }
        if !ready {
            lines.append("\nThen run `capsjump setup` again to confirm.")
        }
        alert.informativeText = lines.joined(separator: "\n")

        var settings: [String] = []
        if accessibility != .granted {
            alert.addButton(withTitle: "Open Accessibility Settings")
            settings.append("Privacy_Accessibility")
        }
        if automation == .denied {
            alert.addButton(withTitle: "Open Automation Settings")
            settings.append("Privacy_Automation")
        }
        alert.addButton(withTitle: "Done")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if settings.indices.contains(response),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settings[response])") {
            NSWorkspace.shared.open(url)
        }
    }
}
