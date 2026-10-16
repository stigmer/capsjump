// Snaps the front app's focused window through Accessibility: it reads the window's frame,
// lets `WindowLayout` pick the screen and the frame, then sets position, size and position
// again, because some apps clamp a new size against the old position.

import AppKit
import ApplicationServices
import CapsJumpCore

public enum WindowError: Error, Equatable, CustomStringConvertible {
    case accessibilityDenied
    case noFrontApp
    case noWindow(app: String)
    case cannotMove(app: String, code: Int32)

    public var description: String {
        switch self {
        case .accessibilityDenied:
            "CapsJump has no Accessibility permission, so it can't move windows; run `capsjump setup`"
        case .noFrontApp:
            "no app is in front to move a window of"
        case let .noWindow(app):
            "\(app) has no focused window to move"
        case let .cannotMove(app, code):
            "\(app) didn't let its window be moved (Accessibility error \(code))"
        }
    }
}

@MainActor
public enum WindowMover {
    public static func move(_ position: WindowPosition) throws(WindowError) {
        guard AXIsProcessTrusted() else { throw .accessibilityDenied }
        guard let front = NSWorkspace.shared.frontmostApplication else { throw .noFrontApp }
        let name = front.localizedName ?? front.bundleIdentifier ?? "the front app"
        let app = AXUIElementCreateApplication(front.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { throw .noWindow(app: name) }
        let window = value as! AXUIElement

        let screens = NSScreen.screens
        guard let primary = screens.first else { throw .noWindow(app: name) }
        let current = frame(of: window) ?? .zero
        let index = WindowLayout.screen(holding: current, screens: screens.map(\.frame), primaryHeight: primary.frame.height)
        let target = WindowLayout.frame(position, visible: screens[index].visibleFrame, primaryHeight: primary.frame.height)

        var origin = target.origin
        var size = target.size
        let point = AXValueCreate(.cgPoint, &origin)!
        let extent = AXValueCreate(.cgSize, &size)!
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, point)
        let sized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
        let placed = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, point)
        guard sized == .success, placed == .success else {
            throw .cannotMove(app: name, code: (sized == .success ? placed : sized).rawValue)
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
