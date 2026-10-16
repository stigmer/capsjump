// The Sites section: the list of sites in the file's order, each a line with its name, its
// account, the page's host and the keys that jump to it, and beside it the picked site's
// editor: its name (which is also its capsjump:// link), the account picked from this Mac's
// Chrome profiles (typed when Chrome's list can't be read), the page it opens, the keys that
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
            List(selection: $model.selectedSite) {
                ForEach(lines) { line in
                    SiteLineView(line: line, problem: model.check.bySite[line.id] != nil)
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.name)
                    .lineLimit(1)
                Text([line.account, line.host].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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

struct SiteEditor: View {
    @ObservedObject var model: EditorModel
    let id: Int
    @State private var advanced = false

    var body: some View {
        if let site = model.draft.site(id)?.site {
            let name = site.name.flatMap { $0.isEmpty ? nil : $0 }
            Form {
                Section {
                    FieldRow(
                        label: "Name",
                        text: Binding(get: { site.name ?? "" }, set: { model.rename(id, $0) }),
                        prompt: "github",
                        problems: model.problems(site: id, .entry, .unknownKey, .name)
                    )
                    account(site)
                    FieldRow(
                        label: "Page",
                        text: Binding(get: { site.open ?? "" }, set: { value in model.update(id) { $0.open = value } }),
                        prompt: "https://github.com/",
                        problems: model.problems(site: id, .open)
                    )
                } footer: {
                    Text("Also the link capsjump://\(name ?? "<name>")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Keys") {
                    let keys = model.draft.keysUsing(id)
                    HStack(spacing: 6) {
                        if keys.isEmpty {
                            Text("No key jumps here yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Caps Lock +")
                            ForEach(keys, id: \.self) { Keycap(symbol: KeyNames.symbol(for: $0)) }
                        }
                        Spacer()
                        Button("Add Key for This Site") { model.addKey(forSite: id) }
                            .disabled(name == nil || model.draft.freeKeys().isEmpty)
                    }
                }
                Section {
                    DisclosureGroup("Advanced", isExpanded: $advanced) {
                        FieldRow(
                            label: "Counts as open",
                            text: Binding(get: { model.matchText(id) }, set: { model.setMatch(id, $0) }),
                            prompt: model.defaultMatch(id) ?? "github.com/",
                            note: model.draft.matchIsDefault(id)
                                ? "A tab whose address starts with \(model.defaultMatch(id) ?? "the page's host") counts as this site. Give prefixes, most specific first, to narrow it."
                                : "Prefixes without https://, most specific first, separated by commas.",
                            problems: model.problems(site: id, .match)
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
            .onAppear { advanced = !model.draft.matchIsDefault(id) }
            .onChange(of: id) { id in advanced = !model.draft.matchIsDefault(id) }
        }
    }

    @ViewBuilder
    private func account(_ site: SiteSource) -> some View {
        let problems = model.problems(site: id, .account, .profile, .accountOrProfile)
        VStack(alignment: .leading, spacing: 4) {
            if let catalog = model.catalog {
                Picker("Account", selection: Binding(get: { model.profile(of: id) }, set: { model.setProfile(id, $0) })) {
                    Text("Choose…").tag(String?.none)
                    ForEach(catalog.profiles, id: \.directory) { profile in
                        Text(AddTabView.label(profile)).tag(Optional(profile.directory))
                    }
                }
            } else {
                TextField("Account", text: Binding(get: { site.account ?? "" }, set: { value in model.update(id) { $0.account = value } }), prompt: Text("you@work.com"))
            }
            EditorNotes(note: model.landing(site: id).map { "Lands in \($0)" }, problems: problems)
        }
    }
}
