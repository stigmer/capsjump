// CapsJump.app's entry point: a background app with no Dock icon or menu (LSUIElement)
// that owns capsjump:// links. It stays running after its first link, so later jumps
// pay no launch.

import AppKit

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
