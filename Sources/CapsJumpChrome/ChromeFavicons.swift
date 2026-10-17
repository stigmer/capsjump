// A site's icon, read from what Chrome has already saved on this Mac: each profile keeps
// the icons of the pages it has shown in a SQLite file, `Favicons`, beside its other data.
// Nothing goes over the network. Chrome holds that file locked while it runs, so it is
// opened read-only and immutable: no lock is taken, so reading can never block or slow
// Chrome, at the price that a read racing one of Chrome's writes may see a torn page,
// which surfaces as a SQLite error or bytes that aren't an image and counts as no icon
// this time. Only the rows asked for are read, by the index on the page's URL (a prefix
// as a range, which searches the index where LIKE would scan it), never a list of pages.
// Each read opens its own connection and closes it, so reads on several threads share
// nothing. The format isn't Chrome's promise; it was schema version 9 when written, and a
// change shows as no icon rather than a failure.

import CapsJumpCore
import Foundation
import SQLite3

public enum ChromeFavicons {
    public enum Missing: Error, Equatable, CustomStringConvertible {
        case noFile
        case unreadable(String)
        case noIcon
        case notAnImage

        public var description: String {
            switch self {
            case .noFile: "the profile has no Favicons file"
            case let .unreadable(reason): "Favicons could not be read: \(reason)"
            case .noIcon: "Chrome has no icon for the site's pages"
            case .notAnImage: "the stored icon is not a PNG"
            }
        }
    }

    /// The largest icon kept, in pixels; Chrome keeps 16 and 32 for a page's favicon.
    static let largest = 64

    /// The `Favicons` file of a Chrome profile folder such as `Profile 1`.
    public static func file(profile: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        Paths.chromeData(home: home).appendingPathComponent(profile).appendingPathComponent("Favicons")
    }

    /// The PNG Chrome keeps for the lookup's page, else the one most pages under its
    /// prefixes share: the largest of at most 64 pixels.
    public static func icon(for lookup: SiteIcon.Lookup, in file: URL) -> Result<Data, Missing> {
        guard FileManager.default.fileExists(atPath: file.path) else { return .failure(.noFile) }
        var db: OpaquePointer?
        let uri = file.absoluteString + "?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            let reason = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(db)
            return .failure(.unreadable(reason))
        }
        defer { sqlite3_close(db) }

        let bitmap = "SELECT image_data FROM favicon_bitmaps WHERE icon_id = (%@) AND width <= \(largest) ORDER BY width DESC LIMIT 1"
        let exact = "SELECT icon_id FROM icon_mapping WHERE page_url = ?1 LIMIT 1"
        let ranges = lookup.prefixes.indices.map { "(page_url >= ?\(2 * $0 + 1) AND page_url < ?\(2 * $0 + 2))" }
        let shared = "SELECT icon_id FROM icon_mapping WHERE \(ranges.joined(separator: " OR ")) GROUP BY icon_id ORDER BY COUNT(*) DESC, icon_id LIMIT 1"

        var asks: [(String, [[UInt8]])] = [(bitmap.replacingOccurrences(of: "%@", with: exact), [Array(lookup.page.utf8)])]
        if !ranges.isEmpty {
            let bounds = lookup.prefixes.flatMap { [Array($0.utf8), upperBound($0)] }
            asks.append((bitmap.replacingOccurrences(of: "%@", with: shared), bounds))
        }
        for (sql, values) in asks {
            switch blob(db, sql, values) {
            case let .success(data?):
                return isPNG(data) ? .success(data) : .failure(.notAnImage)
            case .success(nil):
                continue
            case let .failure(missing):
                return .failure(missing)
            }
        }
        return .failure(.noIcon)
    }

    /// The first row's first column as bytes, nil when there is no row.
    private static func blob(_ db: OpaquePointer, _ sql: String, _ values: [[UInt8]]) -> Result<Data?, Missing> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return .failure(.unreadable(String(cString: sqlite3_errmsg(db))))
        }
        defer { sqlite3_finalize(statement) }
        for (index, bytes) in values.enumerated() {
            // Bound as bytes, which SQLite compares text by: a raised last byte need not be UTF-8.
            sqlite3_bind_text(statement, Int32(index + 1), bytes.map { CChar(bitPattern: $0) }, Int32(bytes.count), transient)
        }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let pointer = sqlite3_column_blob(statement, 0) else { return .success(Data()) }
            return .success(Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, 0))))
        case SQLITE_DONE:
            return .success(nil)
        default:
            return .failure(.unreadable(String(cString: sqlite3_errmsg(db))))
        }
    }

    /// The first text after every text starting with `prefix`, compared byte by byte as
    /// SQLite compares text: the prefix with its last byte raised. A last byte of UTF-8 is
    /// never 0xFF, so raising it never carries.
    static func upperBound(_ prefix: String) -> [UInt8] {
        var bytes = Array(prefix.utf8)
        guard let last = bytes.popLast() else { return bytes }
        bytes.append(last + 1)
        return bytes
    }

    static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    /// SQLite copies a bound value before the call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
