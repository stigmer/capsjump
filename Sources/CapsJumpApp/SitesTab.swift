// The Sites tab: one card per site, with its name (which is also its capsjump:// link),
// the account picked from this Mac's Chrome profiles (typed when Chrome's list can't be
// read), the page it opens, and under Advanced the URL prefixes that count as the site
// being open. Each card says where the site lands, or what's wrong under the field.
// Removing a site that keys jump to asks what to do with them.

import AppKit
import CapsJumpCore
import SwiftUI

struct SitesTab: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.draft.sites.isEmpty {
                    Text("No sites yet. The quickest way to make one: open the page in Chrome, then Add Current Tab… in the menu bar.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(model.draft.sites) { row in
                    SiteCard(model: model, id: row.id)
                }
                if !model.draft.brokenLinks.isEmpty {
                    Text("Saving retires \(model.draft.brokenLinks.map { "capsjump://\($0)" }.joined(separator: ", ")). Keys follow a renamed site by themselves; a launcher or script using the old link needs the new name.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Add Site") { model.addSite() }
            }
            .padding(16)
        }
    }
}

private struct SiteCard: View {
    @ObservedObject var model: EditorModel
    let id: Int
    @State private var advanced = false

    private var site: SiteSource? { model.draft.site(id)?.site }

    var body: some View {
        if let site {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Name") {
                        EditorField(
                            text: Binding(get: { site.name ?? "" }, set: { model.rename(id, $0) }),
                            prompt: "github",
                            note: "Also the link capsjump://\(site.name.flatMap { $0.isEmpty ? nil : $0 } ?? "<name>")",
                            problems: model.problems(site: id, .entry, .unknownKey, .name)
                        )
                    }
                    LabeledContent("Account") {
                        VStack(alignment: .leading, spacing: 4) {
                            if let catalog = model.catalog {
                                Picker("Account", selection: Binding(get: { model.profile(of: id) }, set: { model.setProfile(id, $0) })) {
                                    Text("Choose…").tag(String?.none)
                                    ForEach(catalog.profiles, id: \.directory) { profile in
                                        Text(AddTabView.label(profile)).tag(Optional(profile.directory))
                                    }
                                }
                                .labelsHidden()
                            } else {
                                TextField("Account", text: Binding(get: { site.account ?? "" }, set: { value in model.update(id) { $0.account = value } }), prompt: Text("you@work.com"))
                                    .labelsHidden()
                            }
                            EditorNotes(note: model.landing(site: id), problems: model.problems(site: id, .account, .profile, .accountOrProfile))
                        }
                    }
                    LabeledContent("Page") {
                        EditorField(
                            text: Binding(get: { site.open ?? "" }, set: { value in model.update(id) { $0.open = value } }),
                            prompt: "https://github.com/",
                            note: nil,
                            problems: model.problems(site: id, .open)
                        )
                    }
                    DisclosureGroup("Advanced", isExpanded: $advanced) {
                        LabeledContent("Counts as open") {
                            EditorField(
                                text: Binding(get: { model.matchText(id) }, set: { model.setMatch(id, $0) }),
                                prompt: model.defaultMatch(id) ?? "github.com/",
                                note: model.draft.matchIsDefault(id)
                                    ? "A tab whose address starts with \(model.defaultMatch(id) ?? "the page's host") counts as this site. Give prefixes, most specific first, to narrow it."
                                    : "Prefixes without https://, most specific first, separated by commas.",
                                problems: model.problems(site: id, .match)
                            )
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Remove Site", role: .destructive) { remove() }
                    }
                }
                .labeledContentStyle(FieldLabelStyle())
                .padding(6)
            }
            .onAppear { advanced = !model.draft.matchIsDefault(id) }
        }
    }

    private func remove() {
        let keys = model.draft.keysUsing(id)
        guard !keys.isEmpty else {
            model.remove(site: id, keys: false)
            return
        }
        let name = site?.name ?? "this site"
        let symbols = keys.map { "Caps Lock + \(KeyNames.symbol(for: $0))" }.joined(separator: " and ")
        switch Alerts.ask(
            "Remove \(name)?",
            "\(symbols) \(keys.count == 1 ? "jumps" : "jump") to it.",
            buttons: ["Remove Site and Keys", "Cancel", "Remove Site Only"],
            in: NSApp.keyWindow
        ) {
        case .alertFirstButtonReturn: model.remove(site: id, keys: true)
        case .alertThirdButtonReturn: model.remove(site: id, keys: false)
        default: break
        }
    }
}

/// Labels in a fixed-width column, so every card's fields line up.
struct FieldLabelStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.label
                .frame(width: 110, alignment: .trailing)
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A text field with its note, or its problems in red, beneath it.
struct EditorField: View {
    @Binding var text: String
    let prompt: String
    let note: String?
    let problems: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: $text, prompt: Text(prompt))
                .labelsHidden()
            EditorNotes(note: note, problems: problems)
        }
    }
}

struct EditorNotes: View {
    let note: String?
    let problems: [String]

    var body: some View {
        if problems.isEmpty, let note {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(problems, id: \.self) { problem in
            Text(problem)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
