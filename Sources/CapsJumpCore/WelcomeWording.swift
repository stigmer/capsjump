// What the Welcome window's "Try it" step says: that a key pressed while the window itself
// is in front was heard (a window move there would have nothing to move), and what the
// first key that ran elsewhere did, in the words the config window uses for the same moves.

import Foundation

public enum WelcomeWording {
    /// A key pressed with Caps Lock while the Welcome window is in front.
    public static func heard(_ trigger: KeyTrigger) -> String {
        let key = KeyNames.name(for: trigger).map { "Caps Lock + \(KeyNames.symbol(for: $0))" } ?? "Caps Lock"
        return "Heard \(key). Now click another window and press it again."
    }

    /// What a key did, once it ran without a failure; `frontApp` is the app whose window a
    /// move moved.
    public static func worked(_ action: KeyAction, frontApp: String?) -> String {
        switch action {
        case let .window(position):
            "\(frontApp.map { "\($0)'s window" } ?? "The window") moved to \(EditorRows.positionSpoken(position))."
        case let .app(target):
            switch target {
            case let .name(name): "\(name) came forward."
            case let .path(path): "\(EditorRows.appName(path)) came forward."
            }
        case let .site(name):
            "\(name) is in front, in its Chrome account."
        case .url:
            "The link opened."
        }
    }
}
