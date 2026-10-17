// The Windows section: every move CapsJump can make, always all of them in the same order,
// each a line with its picture, its name and the keys that do it, or "Off" with the key it
// would take dimmed; beside it the picked move's editor. The editor draws the move from
// WindowLayout's own arithmetic, so the picture is the move, and sets its key from the keys
// no other row holds: None turns it off, and a move with none offers its usual key in one
// click while that key is free. A second key for one move, which only the file can write,
// is shown and kept as a second picker. A list line takes values, not the model.

import CapsJumpCore
import SwiftUI

struct WindowList: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let lines = model.windowLines
        List(selection: model.moveSelection) {
            ForEach(lines) { line in
                WindowLineView(line: line, problem: line.keys.contains { model.check.byKey[$0.row] != nil })
                    .equatable()
                    .tag(line.move)
            }
        }
        .overlay {
            if lines.isEmpty {
                EmptyNote(title: "No moves match “\(model.query)”", text: "Search looks at the move and its keys.")
            }
        }
    }
}

struct WindowLineView: View, Equatable {
    let line: EditorRows.WindowLine
    let problem: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: line.move.symbol)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(line.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if line.keys.isEmpty {
                Text("Off")
                    .foregroundStyle(.secondary)
                Keycap(symbol: KeyNames.symbol(for: line.suggested))
                    .opacity(0.4)
            } else {
                ForEach(line.keys, id: \.row) { Keycap(symbol: KeyNames.symbol(for: $0.key)) }
            }
            if problem {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken + (problem ? ", needs fixing" : ""))
    }
}

/// The picked move's editor. It takes the move as values and calls the model only to edit.
struct WindowEditor: View, Equatable {
    let form: EditorModel.WindowForm
    let model: EditorModel

    nonisolated static func == (a: WindowEditor, b: WindowEditor) -> Bool {
        a.form == b.form
    }

    var body: some View {
        let line = form.line
        let move = line.move
        Form {
            Section {
                HStack(spacing: 16) {
                    WindowPicture(move: move)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.title).font(.headline)
                        Text("Moves the front window within the screen it is on, below the menu bar and beside the Dock.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                ForEach(form.keys, id: \.row) { choice in
                    VStack(alignment: .leading, spacing: 4) {
                        MoveKeyPicker(
                            key: Binding(get: { choice.key }, set: { key in afterUpdate { model.setKey(move, row: choice.row, key) } }),
                            free: choice.free
                        )
                        EditorNotes(note: nil, problems: choice.problems)
                    }
                }
                if form.keys.isEmpty {
                    MoveKeyPicker(
                        key: Binding(get: { nil }, set: { key in afterUpdate { model.setKey(move, row: nil, key) } }),
                        free: form.free
                    )
                    let symbol = KeyNames.symbol(for: line.suggested)
                    if line.suggestedFree {
                        HStack {
                            Spacer()
                            Button("Use Caps Lock + \(symbol)") { model.setKey(move, row: nil, line.suggested) }
                        }
                    } else if let held = line.suggestedHeld {
                        EditorNotes(note: "Caps Lock + \(symbol) \(held), so pick another key or change that one in Keys.", problems: [])
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The free keys as their symbols, None first; None turns the key off.
private struct MoveKeyPicker: View {
    @Binding var key: String?
    let free: [String]

    var body: some View {
        Picker("Caps Lock +", selection: $key) {
            Text("None").tag(String?.none)
            ForEach(free, id: \.self) { name in
                Text(KeyNames.symbol(for: name)).tag(Optional(name))
            }
        }
    }
}

/// A small screen with the part the move gives the window, from the move's own frame on it.
private struct WindowPicture: View {
    let move: WindowPosition
    private static let screen = CGRect(x: 0, y: 0, width: 96, height: 60)

    var body: some View {
        let part = WindowLayout.frame(move, visible: Self.screen, primaryHeight: Self.screen.height)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor))
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: part.width - 6, height: part.height - 6)
                .offset(x: part.minX + 3, y: part.minY + 3)
        }
        .frame(width: Self.screen.width, height: Self.screen.height)
        .accessibilityHidden(true)
    }
}

extension WindowPosition {
    /// The SF Symbol drawn beside the move.
    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .maximize: "rectangle.inset.filled"
        }
    }
}
