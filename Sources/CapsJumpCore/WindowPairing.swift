// Pairs Chrome's windows (from Apple Events: an id and a name, front to back) with the
// window titles Accessibility reports (front to back). Only the Accessibility title says
// which profile a window belongs to, and only Chrome's id lets a script pick its tabs, so
// a window can be focused only once the two are paired.
//
// Pairing is by title. Chrome shortens a long window name in the middle with "…", while
// the Accessibility title is whole: `<page title> - Google Chrome – <profile label>`. A
// Chrome window is compatible with a title that starts with its name's text before the
// "…", capped at 20 characters; a window with no name is compatible with none. Windows
// and titles that are compatible, directly or through each other, form a group, and each
// group is paired on its own:
//   - when it holds as many titles as windows and pairing them in front-to-back order is
//     compatible, that order decides (two windows on the same page);
//   - otherwise, when exactly one complete pairing exists, that one;
//   - otherwise nothing in the group is paired.
// A window Accessibility can't see (another Space, say) leaves only its own group
// unpaired; every other window still pairs.

import Foundation

public struct ChromeWindow: Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum WindowPairing {
    static let prefixCap = 20
    /// Groups larger than this skip the search for a single complete pairing.
    static let searchCap = 12

    /// The part of a Chrome window name every Accessibility title of that window starts with.
    public static func namePrefix(_ name: String) -> String {
        let head = name.split(separator: "\u{2026}", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return String(head.prefix(prefixCap))
    }

    /// The ending that marks a title as one of the profile's windows.
    public static func labelSuffix(_ label: String) -> String {
        "\u{2013} \(label)"
    }

    /// For each paired Chrome window id (Chrome reports ids as text), the index of its title in `titles`.
    public static func pair(chrome: [ChromeWindow], titles: [String]) -> [String: Int] {
        let prefixes = chrome.map { namePrefix($0.name) }
        // A window with no name (still loading, say) would be compatible with every title
        // and merge every group into one; it stays unpaired instead.
        let compatible: (Int, Int) -> Bool = { window, title in
            !prefixes[window].isEmpty && titles[title].hasPrefix(prefixes[window])
        }

        var groups = UnionFind(count: chrome.count + titles.count)
        for w in chrome.indices {
            for t in titles.indices where compatible(w, t) {
                groups.union(w, chrome.count + t)
            }
        }
        var members: [Int: (windows: [Int], titles: [Int])] = [:]
        for w in chrome.indices {
            members[groups.find(w), default: ([], [])].windows.append(w)
        }
        for t in titles.indices {
            members[groups.find(chrome.count + t), default: ([], [])].titles.append(t)
        }

        var result: [String: Int] = [:]
        for group in members.values where !group.windows.isEmpty && group.windows.count == group.titles.count {
            let pairs: [(Int, Int)]
            if zip(group.windows, group.titles).allSatisfy(compatible) {
                pairs = Array(zip(group.windows, group.titles))
            } else if group.windows.count <= searchCap, let only = onlyCompletePairing(group.windows, group.titles, compatible) {
                pairs = only
            } else {
                continue
            }
            for (w, t) in pairs {
                result[chrome[w].id] = t
            }
        }
        return result
    }

    /// The profile's paired windows, front to back, each with its title's index.
    public static func windows(labelled label: String, chrome: [ChromeWindow], titles: [String], pairing: [String: Int]) -> [(window: ChromeWindow, title: Int)] {
        let suffix = labelSuffix(label)
        return chrome.compactMap { window in
            guard let t = pairing[window.id], titles[t].hasSuffix(suffix) else { return nil }
            return (window, t)
        }
    }

    /// The complete pairing when there is exactly one, else nil.
    private static func onlyCompletePairing(_ windows: [Int], _ titles: [Int], _ compatible: (Int, Int) -> Bool) -> [(Int, Int)]? {
        var found: [(Int, Int)]?
        var count = 0
        var used = Set<Int>()
        var current: [(Int, Int)] = []

        func search(_ i: Int) {
            guard count < 2 else { return }
            guard i < windows.count else {
                count += 1
                found = current
                return
            }
            for t in titles where !used.contains(t) && compatible(windows[i], t) {
                used.insert(t)
                current.append((windows[i], t))
                search(i + 1)
                current.removeLast()
                used.remove(t)
            }
        }
        search(0)
        return count == 1 ? found : nil
    }
}

private struct UnionFind {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<count)
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var node = x
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        if ra != rb { parent[rb] = ra }
    }
}
