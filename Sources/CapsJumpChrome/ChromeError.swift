// What can go wrong talking to Chrome, each case worded for the person who has to fix it.

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
            "CapsJump may not control Chrome; allow it in System Settings › Privacy & Security › Automation, or run `capsjump setup`"
        case .accessibilityDenied:
            "CapsJump has no Accessibility permission; turn it on in System Settings › Privacy & Security › Accessibility, or run `capsjump setup`"
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
