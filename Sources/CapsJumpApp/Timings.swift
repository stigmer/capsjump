// How long the config window holds the main thread at the moments a user waits on it:
// opening, switching between Sites and Keys, selecting a row, a keystroke in a field, and
// opening the app chooser. Each is an OSSignposter interval that ends when the main run loop
// is next about to sleep, after Core Animation has committed the frame, so the time is what
// the user waited for the window to answer. Instruments shows the intervals on the
// os_signpost track; `log stream --level debug --predicate 'category == "editor"'` prints
// each in milliseconds.

import CapsJumpCore
import Foundation
import os

enum Timings {
    private static let signposter = OSSignposter(subsystem: Identity.bundleID, category: "editor")
    private static let logger = Logger(subsystem: Identity.bundleID, category: "editor")

    /// Starts `name` now and ends it when the main thread is next idle.
    @MainActor
    static func untilIdle(_ name: StaticString) {
        let state = signposter.beginInterval(name)
        let start = ContinuousClock.now
        // Ordered last among the before-waiting observers, so after Core Animation's commit.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max) { observer, _ in
            signposter.endInterval(name, state)
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            let elapsed = (ContinuousClock.now - start).components
            let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
            logger.debug("\(String(describing: name), privacy: .public) \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms")
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
