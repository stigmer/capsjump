// The Sites section: the list of sites in the file's order, each a line with the site's own
// icon as Chrome saved it for its account, its name, its account with the account's picture,
// the page's host and the keys that jump to it, and beside it the picked site's
// editor: its name (which is also its capsjump:// link), the account picked from this Mac's
// Chrome profiles, each with its picture (typed when Chrome's list can't be read), the page it opens, the keys that
// land on it, and under Advanced the URL prefixes that count as the site being open.
// Removing a site that keys jump to asks what to do with them.

import AppKit
import CapsJumpCore
import SwiftUI

struct SiteList: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let lines = model.siteLines
        VStack(spacing: 0) {
            List(selection: model.siteSelection) {
                ForEach(lines) { line in
                    SiteLineView(
                        line: line,
                        problem: model.check.bySite[line.id] != nil,
                        icon: model.iconKey(site: line.id),
                        picture: model.pictureKey(site: line.id)
                    )
                        .equatable()
                        .tag(line.id)
                }
            }
            .overlay {
                if lines.isEmpty {
                    if model.query.isEmpty {
                        EmptyNote(title: "No sites yet", text: "The quickest way to make one: open the page in Chrome, then Add Current Tab… in the menu bar.", button: "Add Site") { model.addSite() }
                    } else {
                        EmptyNote(title: "No sites match “\(model.query)”", text: "Search looks at the name, the account, the page and the keys.")
                    }
                }
            }
            if !model.draft.brokenLinks.isEmpty {
                Text("Saving retires \(model.draft.brokenLinks.map { "capsjump://\($0)" }.joined(separator: ", ")). Keys follow a renamed site by themselves; a launcher or script using the old link needs the new name.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
            }
        }
    }
}

struct SiteLineView: View, Equatable {
    let line: EditorRows.SiteLine
    let problem: Bool
    let icon: SiteIconKey?
    let picture: ProfilePictureKey?

    var body: some View {
        HStack(spacing: 10) {
            SiteIconView(key: icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.name)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let picture, line.account != nil {
                        ProfilePictureView(key: picture, size: 12)
                    }
                    Text([line.account, line.host].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            ForEach(line.keys, id: \.self) { Keycap(symbol: KeyNames.symbol(for: $0)) }
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

/// The picked site's editor. It takes the site as values and calls the model only to edit,
/// so an edit to anything else leaves it alone.
struct SiteEditor: View, Equatable {
    let form: EditorModel.SiteForm
    let model: EditorModel
    @State private var advanced = false

    nonisolated static func == (a: SiteEditor, b: SiteEditor) -> Bool {
        a.form == b.form
    }

    var body: some View {
        let id = form.id
        let site = form.site
        let name = site.name.flatMap { $0.isEmpty ? nil : $0 }
        Form {
            Section {
                FieldRow(
                    label: "Name",
                    text: Binding(get: { site.name ?? "" }, set: { model.rename(id, $0) }),
                    prompt: "github",
                    problems: form.nameProblems
                )
                account
                FieldRow(
                    label: "Page",
                    text: Binding(get: { site.open ?? "" }, set: { value in model.update(id) { $0.open = value } }),
                    prompt: "https://github.com/",
                    problems: form.pageProblems
                )
            } footer: {
                Text("Also the link capsjump://\(name ?? "<name>")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Keys") {
                HStack(spacing: 6) {
                    if form.keys.isEmpty {
                        Text("No key jumps here yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Caps Lock +")
                        ForEach(form.keys, id: \.self) { Keycap(symbol: KeyNames.symbol(for: $0)) }
                    }
                    Spacer()
                    Button("Add Key") { model.addKey(forSite: id) }
                        .help("Adds a key that jumps to this site, on the first free key")
                        .disabled(!form.canAddKey)
                }
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    FieldRow(
                        label: "Counts as open",
                        text: Binding(get: { form.matchText }, set: { model.setMatch(id, $0) }),
                        prompt: form.defaultMatch ?? "github.com/",
                        note: form.matchIsDefault
                            ? "A tab whose address starts with \(form.defaultMatch ?? "the page's host") counts as this site. Give prefixes, most specific first, to narrow it."
                            : "Prefixes without https://, most specific first, separated by commas.",
                        problems: form.matchProblems
                    )
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Remove Site…", role: .destructive) { model.remove(site: id, in: NSApp.keyWindow) }
                }
            }
        }
        .formStyle(.grouped)
        // One form serves every site, so a newly picked site opens Advanced only when it uses it.
        .onAppear { advanced = !form.matchIsDefault }
        .onChange(of: id) { _ in advanced = !form.matchIsDefault }
    }

    @ViewBuilder
    private var account: some View {
        let id = form.id
        VStack(alignment: .leading, spacing: 4) {
            if let profiles = form.profiles {
                AccountPicker(
                    selection: Binding(get: { form.profile }, set: { profile in afterUpdate { model.setProfile(id, profile) } }),
                    profiles: profiles
                )
            } else {
                TextField("Account", text: Binding(get: { form.site.account ?? "" }, set: { value in model.update(id) { $0.account = value } }), prompt: Text("you@work.com"))
            }
            EditorNotes(note: form.landing.map { "Lands in \($0)" }, problems: form.accountProblems)
        }
    }
}
