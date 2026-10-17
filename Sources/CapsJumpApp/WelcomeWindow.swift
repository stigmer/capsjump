// The Welcome window: CapsJump's first run as one checklist that ticks itself. Three steps
// lead to a working key (let CapsJump hear Caps Lock, choose keys, try one), and three
// optional rows say what else it can use and why (Chrome accounts, notifications, starting
// at login). Accessibility is asked once, by macOS's own box, which macOS shows by itself
// while CapsJump lacks it; the first step says what that box wants instead of raising
// another. Chrome and notifications are asked when their buttons are pressed, never
// before. Each row reads its state again every second while the window is open, so a
// switch flipped in System Settings shows here at once. Nothing takes Caps Lock until the person turns keys
// on, next to the line that says Caps Lock stops typing capitals. While the window itself
// is in front, keys pressed with Caps Lock are heard rather than run (a window move would
// try to move this fixed-size window), and the step says so; the first key that runs
// elsewhere ticks it. The button of the step at hand is the prominent one, but no step's
// button answers Return: the window can come forward while someone is typing elsewhere,
// and a stray Return must never raise a macOS request. Done answers Return once all three
// steps are ticked, and Escape before that. The window opens by itself on a launch while CapsJump isn't set up,
// until the person has closed it once; after that only when asked: from the menu, by the
// app being opened again, by `capsjump setup`, by a key that failed for a permission, or by
// a click on a notification about one. The first time it opens on a CapsJump that isn't set
// up yet it turns Start at Login on, where its switch shows it and turns it off again; it
// never turns it on for someone already using CapsJump.

import AppKit
import CapsJumpChrome
import CapsJumpCore
import CapsJumpSystem
import ServiceManagement
import SwiftUI

/// What the Welcome window remembers across launches, beside the pause.
enum WelcomeMemory {
    private static let closedKey = "welcomeClosed"
    private static let loginKey = "welcomeTurnedOnLogin"

    /// Set once the person closes the window; from then on it opens only when asked.
    static var closedOnce: Bool {
        get { UserDefaults.standard.bool(forKey: closedKey) }
        set { UserDefaults.standard.set(newValue, forKey: closedKey) }
    }

    /// Set once the window has turned Start at Login on, so it never does again.
    static var turnedOnLogin: Bool {
        get { UserDefaults.standard.bool(forKey: loginKey) }
        set { UserDefaults.standard.set(newValue, forKey: loginKey) }
    }
}

@MainActor
final class WelcomeModel: ObservableObject {
    enum TryIt: Equatable {
        case waiting
        case heard(String)
        case worked(String)
    }

    /// What the window asks of the rest of the app.
    struct Actions {
        let editConfig: @MainActor (_ showingProblems: Bool) -> Void
        let resume: @MainActor () -> Void
        let close: @MainActor () -> Void
    }

    @Published private(set) var status: KeyStatus
    @Published private(set) var boundKeys: Int?
    @Published private(set) var accessibility: Bool
    @Published private(set) var chrome: PermissionState = .unknown
    @Published private(set) var chromeProblem: String?
    @Published private(set) var notifications: PermissionState = .unknown
    @Published private(set) var login: SMAppService.Status
    @Published private(set) var tryIt = TryIt.waiting
    @Published private(set) var keysProblem: String?
    /// Why the window was opened, when a key failed for want of a permission.
    @Published var notice: String?
    let chromeInstalled = Setup.chromeInstalled
    let actions: Actions
    private let keys: Keys
    private let notifier: Notifier
    private var askingChrome = false

    init(keys: Keys, notifier: Notifier, actions: Actions) {
        self.keys = keys
        self.notifier = notifier
        self.actions = actions
        status = keys.status
        boundKeys = keys.boundKeys
        accessibility = Setup.hasAccessibility
        login = SMAppService.mainApp.status
    }

    var keysChosen: Bool { (boundKeys ?? 0) > 0 }

    var triedIt: Bool {
        if case .worked = tryIt { true } else { false }
    }

    var allDone: Bool { accessibility && keysChosen && triedIt }

    /// Reads every row again; called every second while the window is open and whenever
    /// the keys change.
    func refresh() async {
        readKeys()
        accessibility = Setup.hasAccessibility
        login = SMAppService.mainApp.status
        notifications = await notifier.state
        if !askingChrome, chromeInstalled {
            let state = await Setup.chromeAccess()
            // Closed again after a grant, Chrome reads unknown; the grant still stands.
            if state != .unknown || chrome != .granted { chrome = state }
        }
    }

    func readKeys() {
        status = keys.status
        boundKeys = keys.boundKeys
    }

    /// Writes the starter file, unless one appeared since the window last looked.
    func turnOnStarterKeys() {
        do {
            try ConfigFile().write(StarterConfig.config(catalog: try? Inputs.profiles()), replacing: nil)
            keysProblem = nil
        } catch {
            if case .changedOnDisk = error {
                keysProblem = "~/.capsjump.yaml appeared meanwhile, so it was left as it is."
            } else {
                keysProblem = error.description
            }
        }
        keys.start()
        readKeys()
    }

    func allowChrome() async {
        askingChrome = true
        defer { askingChrome = false }
        do {
            chrome = try await Setup.askForChrome()
            chromeProblem = nil
        } catch {
            chromeProblem = error.description
        }
    }

    func allowNotifications() async {
        notifications = await notifier.request()
    }

    func setLogin(_ on: Bool) {
        LoginItem.set(on)
        login = SMAppService.mainApp.status
    }

    /// A key pressed in the window itself; once a key has worked, the step stays ticked.
    func heard(_ trigger: KeyTrigger) {
        if case .worked = tryIt { return }
        tryIt = .heard(WelcomeWording.heard(trigger))
    }

    /// The first key that ran elsewhere ticks the step.
    func worked(_ text: String) {
        if case .worked = tryIt { return }
        tryIt = .worked(text)
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let notice = model.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            VStack(alignment: .leading, spacing: 18) {
                accessibilityStep
                keysStep
                tryItStep
            }
            .padding(.horizontal, 24)
            Divider().padding(.vertical, 16)
            VStack(alignment: .leading, spacing: 12) {
                Text("Also, if you like").font(.subheadline).foregroundStyle(.secondary)
                if model.chromeInstalled { chromeRow }
                notificationsRow
                loginRow
            }
            .padding(.horizontal, 24)
            Divider().padding(.top, 16)
            footer
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to CapsJump").font(.title2.weight(.semibold))
                Text("Hold Caps Lock and press a key to bring an app forward, land on a site in the right Chrome account, or snap a window.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
    }

    // MARK: The three steps

    private var accessibilityStep: some View {
        Step(number: 1, title: "Let CapsJump hear Caps Lock", done: model.accessibility) {
            if model.accessibility {
                Text("Allowed.").foregroundStyle(.secondary)
            } else {
                Text("macOS asks with its own box before any app can see keys or move windows. Click Open System Settings there and turn CapsJump on; this ticks by itself.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility Settings") { Setup.open(.accessibility) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var keysStep: some View {
        Step(number: 2, title: "Choose your keys", done: model.keysChosen) {
            switch model.boundKeys {
            case let count? where count > 0:
                HStack(spacing: 12) {
                    Text("\(count) \(count == 1 ? "key" : "keys") from ~/.capsjump.yaml.").foregroundStyle(.secondary)
                    Button("Edit Keys…") { model.actions.editConfig(false) }.buttonStyle(.link)
                }
            case .some:
                Text("~/.capsjump.yaml has no keys yet, so Caps Lock works as usual.").foregroundStyle(.secondary)
                Button("Set Up My Keys…") { model.actions.editConfig(false) }
            case nil where model.status.nextStep == .fixConfig:
                Text("~/.capsjump.yaml has a problem, so its keys can't be read.").foregroundStyle(.secondary)
                Button("Show the Problem…") { model.actions.editConfig(true) }
            case nil:
                Text("Start with these, and change or add keys any time:").foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(WindowPosition.allCases, id: \.self) { move in
                        Keycap(symbol: KeyNames.symbol(for: move.suggestedKey))
                    }
                    Text("snap the front window to a half, or fill the screen")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                HStack(spacing: 12) {
                    Button("Turn On Starter Keys") { model.turnOnStarterKeys() }
                        .prominent(model.accessibility)
                        .disabled(!model.accessibility)
                    Button("Set Up My Own…") { model.actions.editConfig(false) }
                        .disabled(!model.accessibility)
                }
            }
            if let problem = model.keysProblem {
                Text(problem).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if !model.keysChosen {
                Text("While CapsJump has keys, Caps Lock no longer types capitals. Hold Shift for capitals; pause any time from the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tryItStep: some View {
        Step(number: 3, title: "Try it", done: model.triedIt) {
            if model.status.nextStep == .resume {
                Text("Your keys are paused.").foregroundStyle(.secondary)
                Button("Resume Keys") { model.actions.resume() }
            } else if !model.status.active {
                Text("Once your keys are on: click any window, then hold Caps Lock and press ←.").foregroundStyle(.secondary)
            } else {
                switch model.tryIt {
                case .waiting:
                    Text("Click any window, then hold Caps Lock and press ←.").foregroundStyle(.secondary)
                case let .heard(text):
                    Text(text).foregroundStyle(.secondary)
                case let .worked(text):
                    Text("That worked. \(text)").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Optional rows

    private var chromeRow: some View {
        OptionRow(
            title: "Chrome accounts",
            why: "So a key can land on a site in the right Chrome account.",
            done: model.chrome == .granted
        ) {
            switch model.chrome {
            case .granted:
                EmptyView()
            case .denied:
                Button("Open Automation Settings") { Setup.open(.automation) }
            default:
                Button("Allow…") { Task { await model.allowChrome() } }
            }
        } footnote: {
            if let problem = model.chromeProblem {
                Text(problem).foregroundStyle(.red)
            } else if model.chrome != .granted && model.chrome != .denied {
                Text("Chrome opens if it's closed; macOS asks only while it runs.")
            }
        }
    }

    private var notificationsRow: some View {
        OptionRow(
            title: "Notifications",
            why: "So a key that can't do its job tells you why.",
            done: model.notifications == .granted
        ) {
            switch model.notifications {
            case .granted:
                EmptyView()
            case .denied:
                Button("Open Notification Settings") { Setup.open(.notifications) }
            default:
                Button("Allow…") { Task { await model.allowNotifications() } }
            }
        } footnote: {
            EmptyView()
        }
    }

    private var loginRow: some View {
        OptionRow(
            title: "Start at login",
            why: "So your keys are there from the moment the Mac starts.",
            done: model.login == .enabled
        ) {
            Toggle("Start at login", isOn: Binding(
                get: { model.login == .enabled || model.login == .requiresApproval },
                set: { on in model.setLogin(on) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        } footnote: {
            if model.login == .requiresApproval {
                HStack(spacing: 8) {
                    Text("Waiting for your approval in Login Items.")
                    Button("Open Login Items") { Setup.open(.loginItems) }.buttonStyle(.link)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let mark = StatusMenu.mark {
                Image(nsImage: mark).accessibilityHidden(true)
            }
            Text("CapsJump lives in the menu bar.")
                .foregroundStyle(.secondary)
            Spacer()
            Text("Version \(AppVersion.current)")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Button("Done") { model.actions.close() }
                .keyboardShortcut(model.allDone ? .defaultAction : .cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

extension View {
    /// The prominent style for the button of the step at hand, the plain one otherwise, so
    /// only one button in the window stands out.
    @ViewBuilder
    fileprivate func prominent(_ isCurrent: Bool) -> some View {
        if isCurrent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

/// One numbered step: a tick once done, its title, and what it needs below.
private struct Step<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.secondary)
                .accessibilityLabel(done ? "Done" : "Step \(number)")
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// An optional row: a tick or an open circle, the title and why it helps, and its control.
private struct OptionRow<Control: View, Footnote: View>: View {
    let title: String
    let why: String
    let done: Bool
    @ViewBuilder let control: Control
    @ViewBuilder let footnote: Footnote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .accessibilityLabel(done ? "On" : "Off")
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(why).font(.callout).foregroundStyle(.secondary)
                footnote.font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
        .accessibilityElement(children: .contain)
    }
}

/// Opens the Welcome window, keeps its rows current while it is open, and lets it hear the
/// keys while it is in front.
@MainActor
final class Welcome: NSObject, NSWindowDelegate {
    private let keys: Keys
    private let notifier: Notifier
    private let editConfig: @MainActor (_ showingProblems: Bool) -> Void
    private var window: NSWindow?
    private var model: WelcomeModel?
    private var polling: Task<Void, Never>?

    init(keys: Keys, notifier: Notifier, editConfig: @escaping @MainActor (_ showingProblems: Bool) -> Void) {
        self.keys = keys
        self.notifier = notifier
        self.editConfig = editConfig
    }

    /// Opens the window, or brings it forward; `notice` says which key needed what.
    func open(notice: String? = nil) {
        if !WelcomeMemory.turnedOnLogin && keys.status.needsSetup {
            WelcomeMemory.turnedOnLogin = true
            LoginItem.set(true)
        }
        if let window, let model {
            if let notice { model.notice = notice }
            AppWindows.show(window)
            return
        }
        let model = WelcomeModel(keys: keys, notifier: notifier, actions: WelcomeModel.Actions(
            editConfig: editConfig,
            resume: { [weak self] in self?.keys.resume() },
            close: { [weak self] in self?.window?.performClose(nil) }
        ))
        model.notice = notice
        let window = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView(model: model)))
        window.title = "Welcome to CapsJump"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        polling = Task { [weak model] in
            while !Task.isCancelled, let model {
                await model.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        AppWindows.show(window)
    }

    var isOpen: Bool { window != nil }

    /// The keys changed: their row and the try-it step follow at once.
    func keysChanged() {
        model?.readKeys()
    }

    /// A key ran without a failure.
    func keyWorked(_ text: String) {
        model?.worked(text)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let model else { return }
        keys.listening.listen(ObjectIdentifier(self)) { [weak model] trigger in model?.heard(trigger) }
    }

    func windowDidResignKey(_ notification: Notification) {
        keys.listening.stop(ObjectIdentifier(self))
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        keys.listening.stop(ObjectIdentifier(self))
        polling?.cancel()
        polling = nil
        WelcomeMemory.closedOnce = true
        self.window = nil
        model = nil
        AppWindows.closed(window)
    }
}
