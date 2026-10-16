// Chrome's windows through Accessibility: the whole window titles, which end in the
// profile's label, and raising one exact window. Read straight from Chrome's process, so
// no second Automation grant (for System Events) is needed.

import AppKit
import ApplicationServices

public struct AXWindow {
    public let title: String
    public let element: AXUIElement
}

@MainActor
public enum ChromeAccessibility {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Chrome's standard windows (minimized ones included), front to back.
    public static func windows(of app: NSRunningApplication) throws(ChromeError) -> [AXWindow] {
        guard isTrusted else { throw .accessibilityDenied }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        switch status {
        case .success: break
        case .apiDisabled: throw .accessibilityDenied
        case .noValue: return []
        default: throw .accessibility(code: status.rawValue)
        }
        let windows = value as? [AXUIElement] ?? []
        return windows.compactMap { window in
            guard string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { return nil }
            return AXWindow(title: string(window, kAXTitleAttribute) ?? "", element: window)
        }
    }

    /// Un-minimizes the window and raises it above Chrome's others.
    public static func raise(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
