// Failures reach the person as notifications, so a key press that did nothing says why.
// Notifications need the app bundle; run unbundled (during development) they are skipped
// and the unified log still carries every failure.

import AppKit
import CapsJumpChrome
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func install() {
        center?.delegate = self
    }

    var state: PermissionState {
        get async {
            guard let center else { return .unknown }
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional: return .granted
            case .denied: return .denied
            case .notDetermined: return .notAsked
            @unknown default: return .unknown
            }
        }
    }

    func request() async -> PermissionState {
        guard let center else { return .unknown }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await state
    }

    func post(_ message: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "CapsJump"
        content.body = message
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Shows notifications even while a CapsJump alert is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
