// The key field: a key is set by clicking the field and pressing the key, alone or with
// Caps Lock held, the way it will be used. The field shows its key as a keycap; clicked, or
// pressed with Space or VoiceOver while focused, it listens ("Press a key"). Focus alone
// never starts it, so Tab through a form and a window opening with the field first are
// harmless. While it listens, every key pressed in its window comes to it before the
// window's own buttons (in Add Current Tab, Return is Add and Escape is Cancel), except
// the menu bar's ⌘ shortcuts, which keep working (⌘S saves), and Tab, which moves on and
// ends the listening; a ⌘ key no menu item takes is refused like any key held with a
// modifier. A key pressed with Caps Lock never reaches a window while keys are bound: the
// event tap hands it over instead of running it, through the KeyListening the app gives
// the views. What a key means is PressedKey's one decision: a key that can't be used, or
// that another row holds, is refused in a line under the field and the field keeps
// listening. Listening ends on a decision, when focus leaves, when the window stops being
// key or the view leaves it, and (by the keys themselves) when CapsJump stops being the
// active app. To VoiceOver the field is a button whose value is the key, and every result
// is announced.

import AppKit
import CapsJumpCore
import SwiftUI

/// How a key field asks the keys to hand it what is pressed with Caps Lock: one field
/// listens at a time, and only it can stop. Views read it from the environment; the app
/// gives the windows the keys' own, and without the keys it does nothing.
struct KeyListening: Sendable {
    let listen: @MainActor @Sendable (ObjectIdentifier, @escaping @MainActor @Sendable (KeyTrigger) -> Void) -> Void
    let stop: @MainActor @Sendable (ObjectIdentifier) -> Void

    static let none = KeyListening(listen: { _, _ in }, stop: { _ in })
}

private struct KeyListeningKey: EnvironmentKey {
    static let defaultValue = KeyListening.none
}

extension EnvironmentValues {
    var keyListening: KeyListening {
        get { self[KeyListeningKey.self] }
        set { self[KeyListeningKey.self] = newValue }
    }
}

/// "Caps Lock +" and the field, with a refusal or the row's problems under it.
struct KeyRecorder: View {
    let key: String?
    /// What the field shows with no key: "Choose a key", or "None" for a move turned off.
    let unset: String
    let decide: @MainActor (KeyTrigger, PressedKey.Modifiers, String?) -> PressedKey.Outcome
    let onUse: @MainActor (String) -> Void
    /// Turns the key off on Delete; nil where Delete doesn't clear.
    var onClear: (@MainActor () -> Void)?
    var problems: [String] = []
    @Environment(\.keyListening) private var keys
    @State private var listening = false
    @State private var refusal: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Caps Lock +") {
                face
                    .overlay {
                        RecorderControl(
                            value: key.map(EditorRows.spokenKey) ?? unset.lowercased(),
                            keys: keys,
                            decide: decide,
                            apply: apply,
                            onListening: { listening = $0 },
                            onRefusal: { refusal = $0 }
                        )
                    }
            }
            EditorNotes(note: nil, problems: (refusal.map { [$0] } ?? []) + problems)
        }
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        // One container, not a Group: a Group would give each branch its own overlay, and
        // the field's AppKit side would be made anew as it starts listening.
        return ZStack {
            if listening {
                Text("Press a key")
                    .foregroundStyle(Color.accentColor)
            } else if let key {
                Keycap(symbol: KeyNames.symbol(for: key))
            } else {
                Text(unset)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 112, minHeight: 28)
        .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(shape.strokeBorder(listening ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: listening ? 1.5 : 1))
        .accessibilityHidden(true)
    }

    private func apply(_ outcome: PressedKey.Outcome) {
        switch outcome {
        case let .use(name): onUse(name)
        case .clear: onClear?()
        case .same, .cancel, .refused: break
        }
    }
}

/// The field's AppKit side, laid over its face: focus, keys, clicks and VoiceOver.
private struct RecorderControl: NSViewRepresentable {
    let value: String
    let keys: KeyListening
    let decide: @MainActor (KeyTrigger, PressedKey.Modifiers, String?) -> PressedKey.Outcome
    let apply: @MainActor (PressedKey.Outcome) -> Void
    let onListening: @MainActor (Bool) -> Void
    let onRefusal: @MainActor (String?) -> Void

    func makeNSView(context: Context) -> RecorderView {
        RecorderView()
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.value = value
        view.keys = keys
        view.decide = decide
        view.apply = apply
        view.onListening = onListening
        view.onRefusal = onRefusal
    }
}

final class RecorderView: NSView {
    var value = ""
    var keys = KeyListening.none
    var decide: (@MainActor (KeyTrigger, PressedKey.Modifiers, String?) -> PressedKey.Outcome)?
    var apply: (@MainActor (PressedKey.Outcome) -> Void)?
    var onListening: (@MainActor (Bool) -> Void)?
    var onRefusal: (@MainActor (String?) -> Void)?
    private(set) var isListening = false
    private var monitor: Any?
    private var resignKey: NSObjectProtocol?
    private weak var observed: NSWindow?
    /// The window the field listens in.
    private weak var listeningIn: NSWindow?

    private static let space: UInt16 = 0x31

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func mouseDown(with event: NSEvent) {
        start()
    }

    override func keyDown(with event: NSEvent) {
        if !isListening, event.keyCode == Self.space, Self.modifiers(event).isEmpty {
            start()
        } else {
            super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        stop()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if observed !== window {
            if let resignKey { NotificationCenter.default.removeObserver(resignKey) }
            observed = window
            resignKey = window.map { window in
                NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stop() }
                }
            }
        }
        // A field taken out of its window takes its face with it, so the face isn't told.
        if isListening, window !== listeningIn { stop(quietly: window == nil) }
    }

    // MARK: Listening

    private func start() {
        guard let window else { return }
        if window.firstResponder !== self { window.makeFirstResponder(self) }
        guard !isListening else { return }
        isListening = true
        listeningIn = window
        keys.listen(ObjectIdentifier(self)) { [weak self] trigger in self?.take(trigger, [], typed: nil) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // A local monitor runs on the main thread, as the event is dispatched.
            nonisolated(unsafe) let event = event
            let passes = MainActor.assumeIsolated { self?.passes(event) ?? true }
            return passes ? event : nil
        }
        tell(listening: true, refusal: nil)
        announce("Press a key. Escape cancels.")
    }

    private func stop(quietly: Bool = false) {
        guard isListening else { return }
        isListening = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        keys.stop(ObjectIdentifier(self))
        if !quietly { tell(listening: false, refusal: nil) }
    }

    /// Whether a key-down in the app goes on to its window; one in the field's window is the
    /// field's, but for the menu bar's ⌘ shortcuts and Tab.
    private func passes(_ event: NSEvent) -> Bool {
        guard isListening, event.window === window else { return true }
        let modifiers = Self.modifiers(event)
        if modifiers.contains(.command), NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return false }
        if Int64(event.keyCode) == PressedKey.tab {
            stop()
            return true
        }
        // Caps Lock as F18, which arrives only while no key is bound, and repeats say nothing.
        if Int64(event.keyCode) == CapsLock.keyCode || event.isARepeat { return false }
        take(.key(Int64(event.keyCode)), modifiers, typed: event.charactersIgnoringModifiers)
        return false
    }

    private func take(_ trigger: KeyTrigger, _ modifiers: PressedKey.Modifiers, typed: String?) {
        guard isListening, let decide else { return }
        let outcome = decide(trigger, modifiers, typed)
        if case let .refused(why) = outcome {
            tell(listening: true, refusal: why)
        } else {
            stop()
            apply?(outcome)
        }
        announce(outcome.spoken)
    }

    private func tell(listening: Bool, refusal: String?) {
        onListening?(listening)
        onRefusal?(refusal)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    /// The modifiers a key field cares about; Caps Lock, fn and the arrows' keypad flag aren't.
    private static func modifiers(_ event: NSEvent) -> PressedKey.Modifiers {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: PressedKey.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }

    // MARK: VoiceOver

    private func announce(_ text: String) {
        NSAccessibility.post(element: window ?? NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Caps Lock plus" }
    override func accessibilityValue() -> Any? { isListening ? "press a key" : value }
    override func accessibilityHelp() -> String? { "Press to record a new key" }

    override func accessibilityPerformPress() -> Bool {
        start()
        return true
    }
}
