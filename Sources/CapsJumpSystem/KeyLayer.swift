// The event tap: one active tap on the session, at the head, for key-downs, key-ups and
// the top row's media events. It turns each event into a `KeyEvent` and lets
// `KeyRules` decide, so the rules live in Core. The tap's run-loop source sits on the main
// run loop, which is the only reason the C callback may assume the main actor. Whether
// Caps Lock is held is asked of the system on every event. When macOS switches the tap off
// (a slow callback, or secure input), it is switched straight back on. A key the rules hand
// to a listening key field reaches it on the main actor's next turn, never inside the
// callback, so the tap never waits on a view.

import AppKit
import CapsJumpCore
import CoreGraphics

@MainActor
public final class KeyLayer {
    private var rules = KeyRules()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onAction: @MainActor (KeyAction) -> Void
    private var onHeard: (@MainActor (KeyTrigger) -> Void)?

    /// NX_SYSDEFINED and its media-key subtype.
    private static let systemDefined = CGEventType(rawValue: 14)!
    private static let mediaKeySubtype: Int16 = 8

    public init(onAction: @escaping @MainActor (KeyAction) -> Void) {
        self.onAction = onAction
    }

    public var isRunning: Bool { tap != nil }

    public func update(_ bindings: [KeyTrigger: KeyAction]) {
        rules.bindings = bindings
    }

    /// Hands each key pressed with Caps Lock to `heard` instead of running it, until
    /// `owner` stops; another owner listening before is replaced.
    public func listen(_ owner: ObjectIdentifier, _ heard: @escaping @MainActor (KeyTrigger) -> Void) {
        rules.listen(owner)
        onHeard = heard
    }

    /// Ends `owner`'s listening, or anyone's when nil; a replaced owner changes nothing.
    public func stopListening(_ owner: ObjectIdentifier? = nil) {
        rules.stopListening(owner)
        if !rules.isListening { onHeard = nil }
    }

    /// Starts the tap; false when macOS refuses it, as it does without Accessibility.
    public func start() -> Bool {
        if tap != nil { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << Self.systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyLayerCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    public func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
    }

    /// True when the event is swallowed.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard let keyEvent = Self.keyEvent(type, event) else { return false }
        switch rules.decide(keyEvent) {
        case .pass:
            return false
        case .swallow:
            return true
        case let .run(action):
            onAction(action)
            return true
        case let .heard(trigger):
            if let onHeard {
                Task { @MainActor in onHeard(trigger) }
            }
            return true
        }
    }

    private static func keyEvent(_ type: CGEventType, _ event: CGEvent) -> KeyEvent? {
        let held = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(CapsLock.keyCode))
        switch type {
        case .keyDown, .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            return KeyEvent(.key(code), type == .keyDown ? .down : .up, isRepeat: isRepeat, capsHeld: held)
        case systemDefined:
            // data1 holds the NX key type in its high 16 bits, then the key state (0xA down,
            // 0xB up) and a repeat bit.
            guard let media = NSEvent(cgEvent: event), media.subtype.rawValue == mediaKeySubtype else { return nil }
            let data = media.data1
            let state = (data & 0xFF00) >> 8
            guard state == 0xA || state == 0xB else { return nil }
            return KeyEvent(.media((data & 0xFFFF_0000) >> 16), state == 0xA ? .down : .up, isRepeat: data & 0x1 != 0, capsHeld: held)
        default:
            return nil
        }
    }
}

private func keyLayerCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    // The run-loop source is on the main run loop, so this runs on the main thread and the
    // event and the layer never leave it.
    nonisolated(unsafe) let layer = refcon
    nonisolated(unsafe) let mainEvent = event
    let swallow = MainActor.assumeIsolated {
        Unmanaged<KeyLayer>.fromOpaque(layer).takeUnretainedValue().handle(type, mainEvent)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
