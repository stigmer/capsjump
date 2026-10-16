// The Keys tab: one row per key, in the file's order. The key is picked from the keys no
// other row holds; what it does is an app (from the apps found where CapsJump looks, or
// any .app through Choose…), one of the sites, a window position, or a link. Each row
// says what the key will do on this Mac, or what's wrong.

import CapsJumpCore
import SwiftUI

struct KeysTab: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.draft.keys.isEmpty {
                    Text("No keys yet, so Caps Lock is left alone. Add one and Caps Lock gets a job.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.draft.keys) { row in
                    KeyCard(model: model, row: row.id)
                }
                Button("Add Key") { model.addKey() }
                    .disabled(model.draft.freeKeys().isEmpty)
            }
            .padding(16)
        }
    }
}

private struct KeyCard: View {
    @ObservedObject var model: EditorModel
    let row: Int

    private var key: KeySource? { model.draft.key(row)?.key }

    var body: some View {
        if let key {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Caps Lock +") {
                        HStack {
                            Picker("Key", selection: Binding(get: { key.key }, set: { model.setKey(row, $0) })) {
                                ForEach(model.draft.freeKeys(for: row), id: \.self) { name in
                                    Text(KeyNames.symbol(for: name)).tag(name)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 80)
                            Picker("Does", selection: Binding(get: { key.action?.kind }, set: { model.setKind(row, $0) })) {
                                Text("Choose…").tag(ActionSource.Kind?.none)
                                Text("Brings an app forward").tag(Optional(ActionSource.Kind.app))
                                Text("Jumps to a site").tag(Optional(ActionSource.Kind.site))
                                Text("Moves the front window").tag(Optional(ActionSource.Kind.window))
                                Text("Opens a link").tag(Optional(ActionSource.Kind.url))
                            }
                            .labelsHidden()
                            .frame(width: 220)
                            Spacer()
                            Button("Remove", role: .destructive) { model.remove(key: row) }
                        }
                    }
                    if let action = key.action {
                        LabeledContent(label(action.kind)) {
                            VStack(alignment: .leading, spacing: 4) {
                                value(action)
                                // Only an app (the one found) and a link (the app that opens it) say more than their picker.
                                let finding = [.app, .url].contains(action.kind) ? model.finding(key: row) : nil
                                let missing = finding.flatMap { $0.level == .problem ? Self.describe($0) : nil }
                                EditorNotes(note: finding.flatMap { $0.level == .problem ? nil : Self.describe($0) }, problems: model.problems(key: row) + (missing.map { [$0] } ?? []))
                            }
                        }
                    } else {
                        LabeledContent("") {
                            EditorNotes(note: nil, problems: model.problems(key: row))
                        }
                    }
                }
                .labeledContentStyle(FieldLabelStyle())
                .padding(6)
            }
        }
    }

    private func label(_ kind: ActionSource.Kind) -> String {
        switch kind {
        case .app: "App"
        case .site: "Site"
        case .window: "Position"
        case .url: "Link"
        }
    }

    @ViewBuilder
    private func value(_ action: ActionSource) -> some View {
        let text = Binding(get: { action.value }, set: { model.setValue(row, $0) })
        switch action.kind {
        case .app:
            HStack {
                Picker("App", selection: text) {
                    if !model.apps.contains(action.value) {
                        Text(action.value.isEmpty ? "Choose…" : action.value).tag(action.value)
                    }
                    ForEach(model.apps, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button("Choose…") { model.chooseApp(row) }
            }
        case .site:
            Picker("Site", selection: text) {
                let names = model.draft.sites.compactMap(\.site.name).filter { !$0.isEmpty }
                if !names.contains(action.value) {
                    Text(action.value.isEmpty ? "Choose…" : action.value).tag(action.value)
                }
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        case .window:
            Picker("Position", selection: text) {
                Text("Left half").tag(WindowPosition.leftHalf.rawValue)
                Text("Right half").tag(WindowPosition.rightHalf.rawValue)
                Text("Whole screen").tag(WindowPosition.maximize.rawValue)
            }
            .labelsHidden()
        case .url:
            TextField("Link", text: text, prompt: Text("https://example.com or slack://open"))
                .labelsHidden()
        }
    }

    /// A checkup line without the key it starts with: "app /Applications/iTerm.app".
    private static func describe(_ finding: Finding) -> String {
        finding.text.components(separatedBy: " → ").dropFirst().joined(separator: " → ")
    }
}
