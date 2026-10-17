// Reading a site's icon from a Favicons file built here with the tables Chrome's schema
// version 9 has: the exact page first, then the icon most pages under the prefixes share,
// the largest bitmap of at most 64 pixels, and every way there is no icon. No Chrome needed.

import CapsJumpCore
import Foundation
import SQLite3
import Testing
@testable import CapsJumpChrome

@Suite struct ChromeFaviconsTests {
    /// A PNG signature and a byte saying which bitmap it is; the reader checks only the signature.
    private static func png(_ tag: UInt8) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, tag])
    }

    /// A Favicons file with these icons (id, bitmaps by width) and pages (url, icon id).
    private static func file(icons: [(Int, [(Int, Data)])], pages: [(String, Int)], schema: Bool = true) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("favicons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Favicons")
        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        func run(_ sql: String) throws {
            try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "\(String(cString: sqlite3_errmsg(db)))")
        }
        guard schema else {
            try run("CREATE TABLE other(id INTEGER)")
            return url
        }
        try run("""
        CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR);
        CREATE TABLE icon_mapping(id INTEGER PRIMARY KEY,page_url LONGVARCHAR NOT NULL,icon_id INTEGER,page_url_type INTEGER DEFAULT 0);
        CREATE TABLE favicons(id INTEGER PRIMARY KEY,url LONGVARCHAR NOT NULL,icon_type INTEGER DEFAULT 1);
        CREATE TABLE favicon_bitmaps(id INTEGER PRIMARY KEY,icon_id INTEGER NOT NULL,last_updated INTEGER DEFAULT 0,image_data BLOB,width INTEGER DEFAULT 0,height INTEGER DEFAULT 0,last_requested INTEGER DEFAULT 0);
        CREATE INDEX icon_mapping_page_url_idx ON icon_mapping(page_url);
        CREATE INDEX icon_mapping_icon_id_idx ON icon_mapping(icon_id);
        CREATE INDEX favicons_url ON favicons(url);
        CREATE INDEX favicon_bitmaps_icon_id ON favicon_bitmaps(icon_id);
        INSERT INTO meta VALUES ('version', '9'), ('last_compatible_version', '9');
        """)
        for (id, bitmaps) in icons {
            try run("INSERT INTO favicons(id, url) VALUES (\(id), 'https://example.com/icon-\(id).ico')")
            for (width, data) in bitmaps {
                let hex = data.map { String(format: "%02X", $0) }.joined()
                try run("INSERT INTO favicon_bitmaps(icon_id, image_data, width, height) VALUES (\(id), X'\(hex)', \(width), \(width))")
            }
        }
        for (page, icon) in pages {
            try run("INSERT INTO icon_mapping(page_url, icon_id) VALUES ('\(page)', \(icon))")
        }
        return url
    }

    private static let github = SiteIcon.lookup(open: "https://github.com/stigmer/stigmer/pulls", match: nil)!

    @Test func theExactPageComesFirstAtItsLargestSmallSize() throws {
        let url = try Self.file(
            icons: [(1, [(16, Self.png(1)), (32, Self.png(2)), (180, Self.png(3))]), (2, [(32, Self.png(4))])],
            pages: [("https://github.com/stigmer/stigmer/pulls", 1), ("https://github.com/a", 2), ("https://github.com/b", 2)]
        )
        #expect(ChromeFavicons.icon(for: Self.github, in: url) == .success(Self.png(2)))
    }

    @Test func withoutThePageTheIconMostPagesShareWins() throws {
        let url = try Self.file(
            icons: [(1, [(16, Self.png(1))]), (2, [(16, Self.png(2))]), (3, [(16, Self.png(3))])],
            pages: [
                ("https://github.com/pull/1", 1),
                ("https://github.com/a", 2), ("https://www.github.com/b", 2), ("http://github.com/c", 2),
                ("https://gitlab.com/x", 3), ("https://gitlab.com/y", 3), ("https://gitlab.com/z", 3), ("https://gitlab.com/w", 3),
            ]
        )
        #expect(ChromeFavicons.icon(for: Self.github, in: url) == .success(Self.png(2)))
    }

    @Test func aPrefixCountsOnlyThePagesUnderIt() throws {
        let url = try Self.file(
            icons: [(1, [(16, Self.png(1))]), (2, [(16, Self.png(2))])],
            pages: [("https://github.com/pulls", 1), ("https://github.community/a", 2), ("https://github.com0/b", 2), ("https://github.com.evil/c", 2)]
        )
        let lookup = SiteIcon.lookup(open: "https://github.com/x", match: ["github.com/"])!
        #expect(ChromeFavicons.icon(for: lookup, in: url) == .success(Self.png(1)))
    }

    @Test func everyWayThereIsNoIcon() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)/Favicons")
        #expect(ChromeFavicons.icon(for: Self.github, in: missing) == .failure(.noFile))

        let empty = try Self.file(icons: [(1, [(16, Self.png(1))])], pages: [("https://gitlab.com/", 1)])
        #expect(ChromeFavicons.icon(for: Self.github, in: empty) == .failure(.noIcon))

        let onlyLarge = try Self.file(icons: [(1, [(180, Self.png(1))])], pages: [("https://github.com/stigmer/stigmer/pulls", 1)])
        #expect(ChromeFavicons.icon(for: Self.github, in: onlyLarge) == .failure(.noIcon))

        let notImage = try Self.file(icons: [(1, [(16, Data("<svg/>".utf8))])], pages: [("https://github.com/stigmer/stigmer/pulls", 1)])
        #expect(ChromeFavicons.icon(for: Self.github, in: notImage) == .failure(.notAnImage))

        let otherSchema = try Self.file(icons: [], pages: [], schema: false)
        guard case .failure(.unreadable) = ChromeFavicons.icon(for: Self.github, in: otherSchema) else {
            Issue.record("a file without Chrome's tables should be unreadable")
            return
        }
    }

    @Test func aFolderWithSpacesIsReadThroughItsURI() throws {
        let url = try Self.file(icons: [(1, [(16, Self.png(1))])], pages: [("https://github.com/stigmer/stigmer/pulls", 1)])
        let spaced = url.deletingLastPathComponent().appendingPathComponent("Profile 1")
        try FileManager.default.createDirectory(at: spaced, withIntermediateDirectories: true)
        let moved = spaced.appendingPathComponent("Favicons")
        try FileManager.default.moveItem(at: url, to: moved)
        #expect(ChromeFavicons.icon(for: Self.github, in: moved) == .success(Self.png(1)))
    }

    @Test func theUpperBoundIsTheFirstTextAfterThePrefix() {
        #expect(ChromeFavicons.upperBound("https://github.com/") == Array("https://github.com0".utf8))
        #expect(ChromeFavicons.upperBound("é") == [0xC3, 0xAA])
        #expect(ChromeFavicons.upperBound("") == [])
    }

    @Test func theFileIsBesideTheProfilesOtherData() {
        let home = URL(fileURLWithPath: "/Users/alex")
        #expect(ChromeFavicons.file(profile: "Profile 1", home: home).path == "/Users/alex/Library/Application Support/Google/Chrome/Profile 1/Favicons")
    }
}
