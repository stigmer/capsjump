// The two permissions a jump needs, read and asked for on CapsJump's own behalf:
// Accessibility (window titles, raising a window) and Automation of Chrome (tabs).
// Accessibility is only ever read: since macOS 26 the read itself makes macOS show its own
// request whenever access is missing (measured on 26.2, once per launch), so CapsJump never
// asks a second time.

import AppKit
import ApplicationServices
import Carbon
import CapsJumpCore

public enum PermissionState: String, Sendable {
    case granted
    case denied = "not granted"
    case notAsked = "not asked yet"
    /// Automation can be read only while Chrome runs.
    case unknown = "unknown (Chrome is not running)"
}

public enum Permissions {
    /// Whether Accessibility is granted.
    @MainActor
    public static var accessibility: PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Whether CapsJump may send Chrome Apple Events; with `ask`, macOS shows its
    /// request without any command reaching Chrome. Blocks while the request is up, so it
    /// runs off the main thread.
    public static func automation(ask: Bool) async -> PermissionState {
        await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: Identity.chromeBundleID)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            switch status {
            case noErr: return PermissionState.granted
            case OSStatus(errAEEventNotPermitted): return .denied
            case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
            default: return .unknown
            }
        }.value
    }
}
