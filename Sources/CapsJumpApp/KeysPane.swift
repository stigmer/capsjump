// The Keys section: the list of keys in the keyboard's order, each a line that reads like the
// key (a keycap, the action's icon, what it does), and beside it the picked key's editor.
// A key is picked from the keys no other row holds; what it does is an app (through the
// app chooser), one of the sites, or a link. Keys that move the window are in Windows; one
// naming a move CapsJump doesn't know stays here, with its problem and no kind picked. The editor says what the
// key will do on this Mac, or what's wrong under its field. A site key's line shows the
// site's icon and its account's picture. A list line takes values, not the model, so an
// edit redraws only the lines it changed.

import CapsJumpCore
import SwiftUI

struct KeyList: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let lines = model.keyLines
        List(selection: model.keySelection) {
            ForEach(lines) { line in
                let siteRow = line.kind == .site ? model.draft.key(line.id)?.siteRow : nil
                KeyLineView(
                    line: line,
                    problem: model.check.byKey[line.id] != nil,
                    appPath: line.app.flatMap(model.appPath),
                    siteIcon: siteRow.flatMap { model.iconKey(site: $0) },
                    picture: siteRow.flatMap { model.pictureKey(site: $0) }
                )
                    .equatable()
                    .tag(line.id)
            }
        }
        .overlay {
            if lines.isEmpty {
                if model.query.isEmpty {
                    EmptyNote(title: "No keys yet", text: "Caps Lock is left alone until a key has a job.", button: "Add Key") { model.addKey() }
                } else {
                    EmptyNote(title: "No keys match “\(model.query)”", text: "Search looks at the key, the app, the site and its account, and the link.")
                }
            }
        }
    }
}

struct KeyLineView: View, Equatable {
    let line: EditorRows.KeyLine
    let problem: Bool
    let appPath: String?
    let siteIcon: SiteIconKey?
    let picture: ProfilePictureKey?

    var body: some View {
        HStack(spacing: 10) {
            Keycap(symbol: line.symbol)
            icon
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.title)
                    .lineLimit(1)
                if let subtitle = line.subtitle {
                    HStack(spacing: 4) {
                        if let picture {
                            ProfilePictureView(key: picture, size: 12)
                        }
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 4)
            if problem {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken + (problem ? ", needs fixing" : ""))
    }

    @ViewBuilder
    private var icon: some View {
        switch line.kind {
        case .app?:
            AppIconView(path: appPath, size: 20)
        case .site?:
            SiteIconView(key: siteIcon)
        case .window?:
            symbol("macwindow")
        case .url?:
            symbol("link")
        case nil:
            symbol("circle.dashed")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
    }
}

/// A key drawn as a key, as on the website.
struct Keycap: View {
    let symbol: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Text(symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: .labelColor))
            .frame(minWidth: 22, minHeight: 20)
            .padding(.horizontal, symbol.count > 1 ? 4 : 0)
            .background(
                shape
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(shape.strokeBorder(Color(nsColor: .separatorColor)))
                    .background(shape.fill(Color(nsColor: .tertiaryLabelColor)).offset(y: 1.5))
            )
            .padding(.bottom, 1.5)
            .accessibilityHidden(true)
    }
}

/// The free keys, shown as their symbols; the Add window uses it too.
struct KeyPicker: View {
    @Binding var key: String?
    let free: [String]

    var body: some View {
        Picker("Caps Lock +", selection: $key) {
            if key == nil {
                Text("Choose…").tag(String?.none)
            }
            ForEach(free, id: \.self) { name in
                Text(KeyNames.symbol(for: name)).tag(Optional(name))
            }
        }
    }
}

/// The picked key's editor. It takes the key as values and calls the model only to edit,
/// so an edit to anything else leaves it alone.
struct KeyEditor: View, Equatable {
    let form: EditorModel.KeyForm
    let apps: [InstalledApp]?
    let model: EditorModel

    nonisolated static func == (a: KeyEditor, b: KeyEditor) -> Bool {
        a.form == b.form && a.apps == b.apps
    }

    var body: some View {
        let row = form.row
        let key = form.key
        Form {
            Section {
                KeyPicker(
                    key: Binding(get: { key.key }, set: { name in afterUpdate { if let name { model.setKey(row, name) } } }),
                    free: form.free
                )
                Picker("Does", selection: Binding(get: { key.action?.kind == .window ? nil : key.action?.kind }, set: { kind in afterUpdate { model.setKind(row, kind) } })) {
                    Text("App").tag(Optional(ActionSource.Kind.app))
                    Text("Site").tag(Optional(ActionSource.Kind.site))
                    Text("Link").tag(Optional(ActionSource.Kind.url))
                }
                .pickerStyle(.segmented)
                if let action = key.action {
                    value(action)
                }
                if !form.problems.isEmpty || form.note != nil {
                    EditorNotes(note: form.note, problems: form.problems)
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Remove Key", role: .destructive) { model.remove(key: row) }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func value(_ action: ActionSource) -> some View {
        let row = form.row
        let text = Binding(get: { action.value }, set: { model.setValue(row, $0) })
        let choice = Binding(get: { action.value }, set: { value in afterUpdate { model.setValue(row, value) } })
        switch action.kind {
        case .app:
            LabeledContent("App") {
                AppChooser(
                    value: action.value,
                    path: form.appPath,
                    apps: apps,
                    pick: { model.setApp(row, path: $0) },
                    other: { model.chooseOtherApp(row) }
                )
            }
        case .site:
            Picker("Site", selection: choice) {
                if !form.sites.contains(where: { $0.name == action.value }) {
                    Text(action.value.isEmpty ? "Choose…" : action.value).tag(action.value)
                }
                ForEach(form.sites, id: \.name) { site in
                    Text(site.label).tag(site.name)
                }
            }
        case .window:
            // Only a move CapsJump doesn't know is listed here; its problem says what to do.
            EmptyView()
        case .url:
            TextField("Link", text: text, prompt: Text("https://example.com or slack://open"))
        }
    }
}
