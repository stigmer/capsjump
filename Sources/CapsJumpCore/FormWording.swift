// How a window words a problem the rules found. The rules speak about the file (`open`,
// `sites[3]`, `keys:`); a form has fields called Page and Account, and pickers that
// can't hold an unknown key. Each message the form can meet gets a sentence of its
// own; any other keeps the rule's words, with `code` quoted as “code”.

import Foundation

public enum FormWording {
    public static func text(_ message: String) -> String {
        let values = quotedValues(message)
        let first = values.first ?? ""
        switch true {
        case message == "`name` is missing":
            return "Give it a name."
        case message.hasPrefix("name `") && message.contains("is already used by"):
            return "Another site is already called “\(first)”."
        case message.hasPrefix("give `account`"):
            return "Pick the account this site opens in."
        case message == "`open` is missing", message == "`open` must be a non-empty text":
            return "Give the page it opens."
        case message.hasPrefix("`open` must be an http or https URL"):
            return "The page must start with http:// or https://, not “\(values.last ?? "")”."
        case message.hasPrefix("`match` entry"):
            return "Leave out the scheme: write “\(values.last ?? "")”, not “\(values.dropFirst().first ?? "")”."
        case message.hasPrefix("give one of `app`"):
            return "Pick what it does."
        case message == "`app` must be a non-empty text":
            return "Pick an app."
        case message == "`site` must be a non-empty text":
            return "Pick a site, or give the one it jumps to a name."
        case message.hasPrefix("no site named"):
            return "No site is called “\(first)”."
        case message == "`url` must be a non-empty text":
            return "Give the link."
        case message.hasPrefix("`url` must be a link with a scheme"):
            return "The link needs a scheme, such as https:// or slack://, not “\(values.last ?? "")”."
        default:
            return quoted(message)
        }
    }

    /// `code` as “code”.
    static func quoted(_ message: String) -> String {
        var text = ""
        var opening = true
        for character in message {
            if character == "`" {
                text.append(opening ? "“" : "”")
                opening.toggle()
            } else {
                text.append(character)
            }
        }
        return text
    }

    /// The texts between backticks, in order.
    private static func quotedValues(_ message: String) -> [String] {
        message.split(separator: "`", omittingEmptySubsequences: false).enumerated()
            .filter { $0.offset % 2 == 1 }
            .map { String($0.element) }
    }
}
