// The system's key mapping that turns Caps Lock into F18, through the HID event system's
// public property (what `hidutil property --set` drives). Only CapsJump's own entry is
// ever added or removed, so a mapping someone else set survives. The mapping lasts until
// it is removed or the Mac restarts, so the app removes it whenever it quits.

import CapsJumpCore
import Foundation
import IOKit.hidsystem

public enum KeyMapping {
    private static let source = "HIDKeyboardModifierMappingSrc"
    private static let destination = "HIDKeyboardModifierMappingDst"

    /// Whether Caps Lock is mapped to F18 now.
    public static func isInPlace() -> Bool {
        entries(client()).contains(where: isOurs)
    }

    /// Maps Caps Lock to F18, or removes CapsJump's entry. False when the system refused
    /// the change.
    @discardableResult
    public static func apply(_ takeCapsLock: Bool) -> Bool {
        let client = client()
        let before = entries(client)
        var after = before.filter { !isOurs($0) }
        if takeCapsLock {
            after.append([source: NSNumber(value: CapsLock.usage), destination: NSNumber(value: CapsLock.targetUsage)])
        }
        guard (after as NSArray) != (before as NSArray) else { return true }
        return IOHIDEventSystemClientSetProperty(client, kIOHIDUserKeyUsageMapKey as CFString, after as CFArray)
    }

    private static func client() -> IOHIDEventSystemClient {
        IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    }

    private static func entries(_ client: IOHIDEventSystemClient) -> [[String: Any]] {
        IOHIDEventSystemClientCopyProperty(client, kIOHIDUserKeyUsageMapKey as CFString) as? [[String: Any]] ?? []
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let source = (entry[source] as? NSNumber)?.uint64Value,
              let destination = (entry[destination] as? NSNumber)?.uint64Value
        else { return false }
        return CapsLock.isMapping(source: source, destination: destination)
    }
}
