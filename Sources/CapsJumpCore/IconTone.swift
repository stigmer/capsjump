// Whether a site's icon is drawn in one light or one dark tone, so the window can set it on
// a plate where it would vanish against the list. Chrome saves a page's icon as the page
// served it, and some sites serve one per color scheme: GitHub's for a dark page is a white
// cat, invisible on a light list. Judged from the icon's pixels, each weighted by how
// opaque it is; an icon of several colors, or with little ink, is neither.

import Foundation

public enum IconTone: Sendable, Equatable {
    case light
    case dark
    case mixed

    /// The tone of an image given as RGBA bytes, 8 bits each, not premultiplied.
    public static func of(rgba: [UInt8]) -> IconTone {
        var ink = 0.0
        var lit = 0.0
        var pixel = 0
        while pixel + 3 < rgba.count {
            let alpha = Double(rgba[pixel + 3]) / 255
            let luminance = (0.2126 * Double(rgba[pixel]) + 0.7152 * Double(rgba[pixel + 1]) + 0.0722 * Double(rgba[pixel + 2])) / 255
            ink += alpha
            lit += alpha * luminance
            pixel += 4
        }
        // Less than a tenth of the pixels' worth of ink: too little to judge.
        guard ink * 4 >= Double(rgba.count) / 10 else { return .mixed }
        let mean = lit / ink
        if mean >= 0.8 { return .light }
        if mean <= 0.2 { return .dark }
        return .mixed
    }
}
