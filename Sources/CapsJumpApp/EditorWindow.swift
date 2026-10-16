// Edit Config…: one window, reused, with a Sites tab and a Keys tab over the config file.
// Save (⌘S) writes through ConfigFile, so the keys change at once, as saving the file does.
// Closing the window or CapsJump's own Quit asks about unsaved edits; a quit from outside
// (`capsjump quit`, Homebrew, logout) never waits on that question, because quitting is
// what gives Caps Lock back, and the edits are lost. A file changed elsewhere reloads
// quietly when there are no edits, and otherwise says so with Reload. A file CapsJump
// can't read opens on its problems.

import AppKit
import CapsJumpCore
import SwiftUI

@MainActor
final class Editor: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: EditorModel?

    func open() {
        if let window {
            AppWindows.show(window)
            return
        }
        let model = EditorModel()
        let view = EditorView(model: model) { [weak self] in
            if let window = self?.window { model.save(in: window) }
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "CapsJump Config"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 640))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        AppWindows.show(window)
    }

    /// Whether CapsJump may quit now, asking about unsaved edits first.
    func mayQuit() -> Bool {
        guard let window else { return true }
        return settleEdits(in: window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        settleEdits(in: sender)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        model?.close()
        model = nil
        self.window = nil
        AppWindows.closed(window)
    }

    /// Save, Don't Save or Cancel, when there is anything unsaved; true to go ahead.
    private func settleEdits(in window: NSWindow) -> Bool {
        guard let model, model.hasChanges else { return true }
        AppWindows.show(window)
        switch Alerts.ask(
            "Save your changes to the config?",
            "Close without saving and the keys stay as they were.",
            buttons: ["Save", "Cancel", "Don't Save"],
            in: window
        ) {
        case .alertFirstButtonReturn: return model.save(in: window) == .saved
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch model.state {
            case let .unreadable(problems):
                unreadable(problems)
            case .editing:
                if model.changedOutside {
                    banner("The file changed outside this window.", button: "Reload") { model.load() }
                }
                if !model.fileProblems.isEmpty {
                    banner(model.fileProblems.joined(separator: "\n"), button: nil) {}
                }
                TabView(selection: $model.tab) {
                    SitesTab(model: model).tabItem { Text("Sites (\(model.draft.sites.count))") }.tag(0)
                    KeysTab(model: model).tabItem { Text("Keys (\(model.draft.keys.count))") }.tag(1)
                }
                .padding([.top, .horizontal], 12)
                Divider()
                HStack {
                    Text(status).font(.callout).foregroundStyle(model.draft.issues.isEmpty ? Color.secondary : Color.red)
                    Spacer()
                    Button("Open Config File") { ConfigFileOpener.open() }
                    Button("Save", action: onSave)
                        .keyboardShortcut("s")
                        .disabled(!model.hasChanges || model.draft.config == nil)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var status: String {
        let count = model.draft.issues.count
        if count > 0 { return "\(count) \(count == 1 ? "thing" : "things") to fix before saving" }
        if model.expected == nil { return "No config file yet; Save writes one." }
        return model.hasChanges ? "Unsaved changes" : "Saved"
    }

    private func banner(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let button { Button(button, action: action) }
        }
        .padding(10)
        .background(Color.orange.opacity(0.15))
    }

    private func unreadable(_ problems: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CapsJump can't read its config").font(.headline)
            Text("Fix these in the file itself, then Reload. Until then the keys stay as they were.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(problems, id: \.self) { Text($0).font(.callout.monospaced()).textSelection(.enabled) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Open Config File") { ConfigFileOpener.open() }
                Button("Reload") { model.load() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
