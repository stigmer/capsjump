// Where a snapped window goes. Screens come from AppKit, whose origin is the primary
// screen's bottom-left corner with y growing up; Accessibility places windows from the
// primary screen's top-left corner with y growing down. The window stays on the screen it
// is mostly on and fills that screen's visible frame: below the menu bar, beside the Dock.

import CoreGraphics
import Foundation

public enum WindowLayout {
    /// The Accessibility frame for `position` on a screen whose AppKit visible frame is
    /// `visible`; `primaryHeight` is the primary screen's full height.
    public static func frame(_ position: WindowPosition, visible: CGRect, primaryHeight: CGFloat) -> CGRect {
        let left = (visible.width / 2).rounded(.down)
        let top = (visible.height / 2).rounded(.down)
        // AppKit's y grows up, so the top half is the upper part of the frame.
        let target: CGRect = switch position {
        case .leftHalf: CGRect(x: visible.minX, y: visible.minY, width: left, height: visible.height)
        case .rightHalf: CGRect(x: visible.minX + left, y: visible.minY, width: visible.width - left, height: visible.height)
        case .topHalf: CGRect(x: visible.minX, y: visible.maxY - top, width: visible.width, height: top)
        case .bottomHalf: CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height - top)
        case .maximize: visible
        }
        return flip(target, primaryHeight: primaryHeight)
    }

    /// The index of the screen (AppKit frames) that holds most of `window` (an
    /// Accessibility frame); the first screen when the window is on none of them.
    public static func screen(holding window: CGRect, screens: [CGRect], primaryHeight: CGFloat) -> Int {
        let appKitWindow = flip(window, primaryHeight: primaryHeight)
        var best = 0
        var bestArea: CGFloat = 0
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(appKitWindow)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                best = index
                bestArea = area
            }
        }
        return best
    }

    /// Converts between AppKit's and Accessibility's coordinates; the conversion is its own inverse.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
