// Each Chrome account's picture in the config window, the round face or letter Chrome shows
// in its own profile menu, drawn beside the account's text wherever the text is. The Google
// picture Chrome saved is read off the main thread and kept for as long as the window is
// open, then forgotten as site icons are (a line already drawn keeps its picture until it
// redraws, stigmer/capsjump#24). Until it is read, and when
// there is none, Chrome's own stand-in: a person's outline on a disc in the profile's
// colours (system greys when Chrome records none), so a row never shows an empty slot. The
// picture crosses from the reading thread as bytes and becomes an image on the main one.
// Why a picture is missing is never shown; the first reason in each opening of the window
// is logged, without the path. Rows draw a view; a menu draws an image, so the same circle
// is made as an image for the Account menus.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import OSLog
import SwiftUI

/// What an account's picture is drawn from: the profile folder and what Chrome would draw.
struct ProfilePictureKey: Hashable, Sendable {
    let profile: String
    let picture: ProfilePicture

    init(_ profile: ChromeProfile) {
        self.profile = profile.directory
        picture = profile.picture
    }
}

@MainActor
enum ProfilePictures {
    /// Each Google picture read, nil when there is none or it didn't load.
    private static var cache: [ProfilePictureKey: NSImage?] = [:]
    private static var logged = false
    private static let logger = Logger(subsystem: Identity.bundleID, category: "editor")

    /// Forgets every picture read, for the window opened again.
    static func forget() {
        cache = [:]
        logged = false
    }

    static func cached(_ key: ProfilePictureKey) -> NSImage?? {
        key.picture.file == nil ? .some(nil) : cache[key]
    }

    /// The account's Google picture, nil when Chrome would draw the stand-in.
    static func picture(_ key: ProfilePictureKey) async -> NSImage? {
        if let known = cached(key) { return known }
        guard let name = key.picture.file else { return nil }
        let file = ChromeProfilePicture.file(profile: key.profile, name: name)
        let result = await Task.detached(priority: .userInitiated) { ChromeProfilePicture.picture(in: file) }.value
        var image: NSImage?
        switch result {
        case let .success(data):
            image = NSImage(data: data)
            if image == nil { note(.notAnImage) }
        case let .failure(missing):
            note(missing)
        }
        cache[key] = image
        return image
    }

    /// The account's circle as an image `size` points across, for a menu item.
    static func menuImage(_ key: ProfilePictureKey, size: CGFloat) async -> NSImage {
        if let picture = await picture(key) {
            return circle(size) { rect in
                NSBezierPath(ovalIn: rect).addClip()
                picture.draw(in: rect)
            }
        }
        return standIn(key.picture, size: size)
    }

    /// Chrome's stand-in as an image, drawn at once.
    static func standIn(_ picture: ProfilePicture, size: CGFloat) -> NSImage {
        let colours = StandInColours(picture)
        return circle(size) { rect in
            colours.fill.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.6, weight: .regular)
                .applying(.init(paletteColors: [colours.outline]))
            guard let symbol = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { return }
            let fit = symbol.size
            symbol.draw(in: NSRect(
                x: rect.midX - fit.width / 2, y: rect.midY - fit.height / 2 - size * 0.04,
                width: fit.width, height: fit.height
            ))
        }
    }

    private static func circle(_ size: CGFloat, draw: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(rect)
            return true
        }
    }

    private static func note(_ missing: ChromeProfilePicture.Missing) {
        guard !logged else { return }
        logged = true
        logger.info("an account has no picture: \(missing.description, privacy: .public)")
    }
}

/// The stand-in's colours: the profile's own, else system greys that follow the look.
struct StandInColours {
    let fill: NSColor
    let outline: NSColor

    init(_ picture: ProfilePicture) {
        fill = picture.fill.map(Self.color) ?? .quaternaryLabelColor
        outline = picture.outline.map(Self.color) ?? .secondaryLabelColor
    }

    private static func color(_ argb: UInt32) -> NSColor {
        func channel(_ shift: UInt32) -> CGFloat { CGFloat((argb >> shift) & 0xFF) / 255 }
        return NSColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: channel(24))
    }
}

/// An account's picture, round, `size` points across: the Google picture once read,
/// Chrome's stand-in until then and when there is none.
struct ProfilePictureView: View {
    let key: ProfilePictureKey
    let size: CGFloat
    @State private var picture: NSImage?

    var body: some View {
        Group {
            if let picture {
                Image(nsImage: picture)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(Circle())
            } else {
                let colours = StandInColours(key.picture)
                Circle()
                    .fill(Color(nsColor: colours.fill))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.6))
                            .foregroundStyle(Color(nsColor: colours.outline))
                            .offset(y: size * 0.04)
                    }
            }
        }
        .frame(width: size, height: size)
        .task(id: key) {
            if let known = ProfilePictures.cached(key) {
                picture = known
            } else {
                picture = nil
                let found = await ProfilePictures.picture(key)
                // Another account asks again; a read it overtook doesn't land.
                if !Task.isCancelled { picture = found }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A site's account picked from this Mac's Chrome profiles, each with its picture; the
/// config window's site editor and Add Current Tab share it.
struct AccountPicker: View {
    let selection: Binding<String?>
    let profiles: [ChromeProfile]
    @State private var images: [String: NSImage] = [:]

    private static let side: CGFloat = 16

    var body: some View {
        Picker("Account", selection: selection) {
            Text("Choose…").tag(String?.none)
            ForEach(profiles, id: \.directory) { profile in
                Label {
                    Text(Self.label(profile))
                } icon: {
                    Image(nsImage: images[profile.directory] ?? ProfilePictures.standIn(profile.picture, size: Self.side))
                }
                .tag(Optional(profile.directory))
            }
        }
        // A menu draws images, not views, so every picture is read before it opens.
        .task(id: profiles.map(ProfilePictureKey.init)) {
            var read: [String: NSImage] = [:]
            for profile in profiles {
                read[profile.directory] = await ProfilePictures.menuImage(ProfilePictureKey(profile), size: Self.side)
            }
            if !Task.isCancelled { images = read }
        }
    }

    static func label(_ profile: ChromeProfile) -> String {
        profile.email.isEmpty ? profile.name : "\(profile.windowLabel) · \(profile.email)"
    }
}
