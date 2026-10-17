// What can go wrong talking to Chrome, each case worded for the person who has to fix it.
// Only the app talks to Chrome, so these reach people as its notifications; the two
// permission cases open the Welcome window when clicked.

import Foundation

public enum ChromeError: Error, Equatable, CustomStringConvertible {
    case notInstalled
    case automationDenied
    case accessibilityDenied
    case windowGone
    case script(code: Int, message: String)
    case accessibility(code: Int32)
    case launch(String)

    public var description: String {
        switch self {
        case .notInstalled:
            "Google Chrome is not installed"
        case .automationDenied:
            "CapsJump may not control Chrome; click to allow it, or turn on Google Chrome under CapsJump in System Settings › Privacy & Security › Automation"
        case .accessibilityDenied:
            "CapsJump has no Accessibility permission; click to finish setting up"
        case .windowGone:
            "Chrome, or the window, closed during the jump"
        case let .script(code, message):
            "Chrome refused a script command (\(code)): \(message)"
        case let .accessibility(code):
            "Accessibility could not read Chrome's windows (error \(code))"
        case let .launch(message):
            "could not open Chrome: \(message)"
        }
    }
}
