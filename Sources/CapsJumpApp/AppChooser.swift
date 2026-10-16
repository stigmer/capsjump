// Picking the app a key brings forward: one button with the app's icon and name, opening a
// popover that lists the apps found where an app named by name is looked for, with their
// icons and a search field; ↑ and ↓ move through them, Return picks, Escape closes.
// Applications come first; the helpers in /System/Library/CoreServices (Finder lives among
// them) come after, apart. Other… picks any .app. The apps are listed once per window and
// the icons read once per app, off the main thread, so neither the window nor the popover
// waits for the disk.

import AppKit
import CapsJumpCore
import SwiftUI

struct InstalledApp: Sendable, Equatable, Identifiable {
    let name: String
    let path: String
    /// In /System/Library/CoreServices.
    let system: Bool

    var id: String { path }

    /// Every .app in `AppTarget.searchFolders`, by name, the system's helpers after the rest.
    nonisolated static func scan(home: String) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for folder in AppTarget.searchFolders {
            let path = folder.hasPrefix("~/") ? home + folder.dropFirst() : folder
            let system = folder == "/System/Library/CoreServices"
            for file in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] where file.hasSuffix(".app") {
                apps.append(InstalledApp(name: String(file.dropLast(4)), path: "\(path)/\(file)", system: system))
            }
        }
        return apps.sorted { ($0.system ? 1 : 0, $0.name.lowercased()) < ($1.system ? 1 : 0, $1.name.lowercased()) }
    }
}

/// App icons by path, read once each, off the main thread.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func cached(_ path: String) -> NSImage? {
        cache[path]
    }

    static func icon(_ path: String) async -> NSImage {
        if let icon = cache[path] { return icon }
        let icon = await Task.detached(priority: .userInitiated) { Icon(image: NSWorkspace.shared.icon(forFile: path)) }.value.image
        cache[path] = icon
        return icon
    }

    /// An icon handed from the reading thread to the main one; nothing changes it after it
    /// is read. NSImage is Sendable only from macOS 14.
    private struct Icon: @unchecked Sendable {
        let image: NSImage
    }

    /// Where the app a key names is, as the keys would find it.
    static func path(for app: String, lookup: Lookup) -> String? {
        AppTarget.parse(app)?.resolve(home: lookup.home, exists: lookup.exists)
    }
}

/// An app's icon, or a plain app symbol until it is read or when the app isn't found.
struct AppIconView: View {
    let path: String?
    var size: CGFloat = 20
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary).padding(size / 8)
            }
        }
        .frame(width: size, height: size)
        .task(id: path) {
            guard let path else {
                icon = nil
                return
            }
            icon = AppIcons.cached(path)
            if icon == nil { icon = await AppIcons.icon(path) }
        }
        .accessibilityHidden(true)
    }
}

struct AppChooser: View {
    /// The app as written, and where the keys find it.
    let value: String
    let path: String?
    let apps: [InstalledApp]?
    let pick: @MainActor (_ path: String) -> Void
    let other: @MainActor () -> Void
    @State private var open = false

    var body: some View {
        HStack {
            Button {
                Timings.untilIdle("chooser")
                open = true
            } label: {
                HStack(spacing: 6) {
                    AppIconView(path: path, size: 16)
                    Text(value.isEmpty ? "Choose an App…" : value)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                AppList(
                    apps: apps,
                    picked: value,
                    pick: { app in
                        open = false
                        pick(app.path)
                    },
                    other: {
                        open = false
                        // After the popover has closed, so the panel isn't its child.
                        Task { @MainActor in other() }
                    },
                    close: { open = false }
                )
            }
            .accessibilityLabel("App")
            .accessibilityValue(value.isEmpty ? "none" : value)
        }
    }
}

/// The popover's list.
private struct AppList: View {
    let apps: [InstalledApp]?
    let picked: String
    let pick: (InstalledApp) -> Void
    let other: () -> Void
    let close: () -> Void
    @State private var search = ""
    @State private var highlighted: String?

    private var shown: [InstalledApp] {
        let words = search.split(whereSeparator: \.isWhitespace).map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        guard !words.isEmpty else { return apps ?? [] }
        return (apps ?? []).filter { app in
            let name = app.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return words.allSatisfy { name.contains($0) }
        }
    }

    var body: some View {
        let shown = shown
        VStack(spacing: 0) {
            ChooserField(
                text: $search,
                onMove: { move($0, in: shown) },
                onReturn: { if let app = shown.first(where: { $0.path == highlighted }) ?? shown.first { pick(app) } },
                onEscape: close
            )
            .padding(8)
            Divider()
            if apps == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty {
                Text("No app called “\(search)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A lazy stack builds only the rows in sight, where a List builds a table of all.
                ScrollViewReader { scroller in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                            group("Applications", shown.filter { !$0.system })
                            group("System", shown.filter(\.system))
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: highlighted) { id in
                        if let id { scroller.scrollTo(id) }
                    }
                }
            }
            Divider()
            HStack {
                Button("Other…", action: other)
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 320, height: 420)
        .onAppear { highlighted = apps?.first { $0.name == picked || $0.path == picked }?.path }
    }

    @ViewBuilder
    private func group(_ title: String, _ apps: [InstalledApp]) -> some View {
        if !apps.isEmpty {
            Section {
                ForEach(apps) { app in
                    HStack(spacing: 8) {
                        AppIconView(path: app.path, size: 18)
                        Text(app.name)
                            .foregroundStyle(app.path == highlighted ? Color.white : Color.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(app.path == highlighted ? Color.accentColor : Color.clear)
                    )
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { pick(app) }
                    .onHover { if $0 { highlighted = app.path } }
                    .id(app.path)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            } header: {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            }
        }
    }

    private func move(_ step: Int, in shown: [InstalledApp]) {
        guard !shown.isEmpty else { return }
        let index = shown.firstIndex { $0.path == highlighted }.map { $0 + step } ?? (step > 0 ? 0 : shown.count - 1)
        highlighted = shown[max(0, min(shown.count - 1, index))].path
    }
}

/// A search field that hands ↑, ↓, Return and Escape to the list beside it, which a SwiftUI
/// field on macOS 13 can't.
private struct ChooserField: NSViewRepresentable {
    @Binding var text: String
    let onMove: (Int) -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search apps"
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ChooserField

        init(parent: ChooserField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.onReturn()
            case #selector(NSResponder.cancelOperation(_:)):
                guard parent.text.isEmpty else { return false }
                parent.onEscape()
            default: return false
            }
            return true
        }
    }
}
