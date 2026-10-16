// Asks for all three permissions at once, attributed to CapsJump itself, registers the
// app to start at login so the keys are there from the moment the Mac starts, then shows
// one alert with each one's state. Automation can be asked for only while Chrome runs, so
// setup starts Chrome first when it is closed.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import ServiceManagement

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
        let login = startAtLogin()
        show(accessibility: accessibility, automation: automation, chromeProblem: chromeProblem, notifications: notifications, login: login)
    }

    /// Registers the app as a login item; turned off again in System Settings › General ›
    /// Login Items & Extensions.
    private static func startAtLogin() -> SMAppService.Status {
        let service = SMAppService.mainApp
        if service.status != .enabled {
            try? service.register()
        }
        return service.status
    }

    private static func show(
        accessibility: PermissionState,
        automation: PermissionState,
        chromeProblem: String?,
        notifications: PermissionState,
        login: SMAppService.Status
    ) {
        let alert = NSAlert()
        let ready = accessibility == .granted && automation == .granted
        alert.messageText = ready ? "CapsJump is ready" : "CapsJump needs a permission"
        var lines = [
            "Accessibility: \(accessibility.rawValue)",
            "Automation of Chrome: \(chromeProblem ?? automation.rawValue)",
            "Notifications: \(notifications.rawValue)",
            "Starts at login: \(login == .enabled ? "yes" : login == .requiresApproval ? "waiting for approval" : "no")",
        ]
        if accessibility != .granted {
            lines.append("\nTurn CapsJump on under Privacy & Security › Accessibility.")
        }
        if automation == .denied {
            lines.append("\nTurn on Google Chrome under CapsJump in Privacy & Security › Automation.")
        }
        if login == .requiresApproval {
            lines.append("\nTurn CapsJump on under General › Login Items & Extensions.")
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
