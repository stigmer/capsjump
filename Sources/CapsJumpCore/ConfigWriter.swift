// Writes a config as the file CapsJump saves: a short header, `sites:` as a list with
// `match` left out while it is the default, then a blank line and `keys:` with one flow
// mapping per key. Yams writes every character below the header, so every value is quoted
// exactly when YAML needs it. A file is canonical when writing what it says gives it back
// unchanged, ignoring the header; only a file that isn't would lose something to a save
// (comments, its own layout), and that is what the window warns about.

import Foundation
import Yams

public enum ConfigWriter {
    /// The header's first line, which marks the block a canonical file may differ in.
    public static let marker = "# Written by CapsJump."

    static let header = """
    \(marker)
    # Hold Caps Lock and press a key. Each site is also a link, capsjump://<name>, that lands
    # on its tab in the right Chrome account; each key does one thing: an app, a site, a
    # window position (left-half, right-half, top-half, bottom-half, maximize) or a link.
    # `capsjump check` explains every line. CapsJump rewrites this file when it saves, so
    # comments added here don't survive that.


    """

    public static func render(_ config: Config) -> String {
        let sites = Node.Sequence(config.sites.map(node), Tag(.seq), config.sites.isEmpty ? .flow : .block)
        let keys = Node.Mapping(config.keys.map { (scalar($0.key), node($0.action)) }, Tag(.map), config.keys.isEmpty ? .flow : .block)
        return header
            + dump(Node.Mapping([(scalar("sites"), .sequence(sites))]))
            + "\n"
            + dump(Node.Mapping([(scalar("keys"), .mapping(keys))]))
    }

    /// Whether saving `text` would give back the same file, apart from CapsJump's header.
    public static func isCanonical(_ text: String) -> Bool {
        guard let config = try? ConfigParser.parse(text) else { return false }
        return body(of: text) == body(of: render(config))
    }

    /// The text after the leading comment block that opens with the marker line.
    static func body(of text: String) -> Substring {
        guard text.hasPrefix(marker + "\n") else { return Substring(text) }
        var rest = Substring(text)
        while rest.hasPrefix("#") {
            rest = rest[(rest.firstIndex(of: "\n").map(rest.index(after:)) ?? rest.endIndex)...]
        }
        return rest.hasPrefix("\n") ? rest.dropFirst() : rest
    }

    private static func node(_ site: Site) -> Node {
        var pairs: [(Node, Node)] = [(scalar("name"), value(site.name))]
        if let account = site.account { pairs.append((scalar("account"), value(account))) }
        if let profile = site.profile { pairs.append((scalar("profile"), value(profile))) }
        pairs.append((scalar("open"), value(site.open.absoluteString)))
        if site.match != [URLPrefix.defaultMatch(for: site.open)] {
            pairs.append((scalar("match"), .sequence(Node.Sequence(site.match.map(value), Tag(.seq), .flow))))
        }
        return .mapping(Node.Mapping(pairs, Tag(.map), .block))
    }

    private static func node(_ action: KeyAction) -> Node {
        let (kind, value): (ActionSource.Kind, String) = switch action {
        case let .app(target): (.app, target.description)
        case let .site(name): (.site, name)
        case let .window(position): (.window, position.rawValue)
        case let .url(url): (.url, url.absoluteString)
        }
        return .mapping(Node.Mapping([(scalar(kind.rawValue), Self.value(value))], Tag(.map), .flow))
    }

    private static func scalar(_ text: String) -> Node {
        .scalar(Node.Scalar(text, Tag(.str)))
    }

    /// A value, quoted when YAML would otherwise read it as something other than text
    /// (`yes`, `null`, `42`), so any YAML tool reads the file as CapsJump does.
    private static func value(_ text: String) -> Node {
        let style: Node.Scalar.Style = Yams.Resolver.default.resolveTag(of: Node.scalar(Node.Scalar(text))) == .str ? .any : .singleQuoted
        return .scalar(Node.Scalar(text, Tag(.str), style))
    }

    private static func dump(_ mapping: Node.Mapping) -> String {
        // Only an unrepresentable node throws, and these nodes are plain text.
        (try? Yams.serialize(node: .mapping(mapping), width: -1, allowUnicode: true)) ?? ""
    }
}
