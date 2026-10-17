// Failures reach the person as notifications, so a key press that did nothing says why.
// One that a missing permission caused says "click to finish setting up", and clicking it
// opens the Welcome window; any other click just brings the notification's app forward.
// While the Welcome window is open such a notification isn't sent: the window already
// shows that step, and two asks at once are one too many.
// Notifications need the app bundle; run unbundled (during development) they are skipped
// and the unified log still carries every failure.

import AppKit
import CapsJumpChrome
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Opens the Welcome window, and says whether it is open; the app sets both at launch.
    var openWelcome: (@MainActor () -> Void)?
    var welcomeIsOpen: (@MainActor () -> Bool)?
    nonisolated private static let opensWelcomeKey = "opensWelcome"

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

    /// `opensWelcome` makes a click open the Welcome window.
    func post(_ message: String, opensWelcome: Bool = false) {
        guard let center else { return }
        if opensWelcome, welcomeIsOpen?() == true { return }
        let content = UNMutableNotificationContent()
        content.title = "CapsJump"
        content.body = message
        if opensWelcome {
            content.userInfo = [Self.opensWelcomeKey: true]
        }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Shows notifications even while a CapsJump alert is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              response.notification.request.content.userInfo[Self.opensWelcomeKey] as? Bool == true
        else { return }
        await MainActor.run { openWelcome?() }
    }
}
