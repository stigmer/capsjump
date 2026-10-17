// The capsjump command: writes and checks the config, lists Chrome's profiles, and
// hands links to CapsJump.app. It never talks to Chrome itself: the app holds the
// permissions, so `jump` and `setup` go through macOS's link handling to it. `check` also
// reads whether the app runs and whether Caps Lock is mapped, the two things the keys need;
// `pause` and `resume` reach the running app by link, and `quit` asks it to quit.

import AppKit
import ArgumentParser
import Foundation
import CapsJumpChrome
import CapsJumpCore
import CapsJumpSystem

@main
struct CapsJump: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capsjump",
        abstract: "Shortcuts built around Caps Lock: apps, Chrome sites in the right account, windows and links.",
        discussion: "Keys and sites live in ~/.capsjump.yaml. Hold Caps Lock and press a key; each site is also the link capsjump://<name>.",
        version: Version.current,
        subcommands: [Init.self, Profiles.self, Check.self, Jump.self, Setup.self, PauseCommand.self, ResumeCommand.self, QuitCommand.self, Logs.self, VersionCommand.self]
    )
}

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Write a starter ~/.capsjump.yaml: the window keys, and an example site in this Mac's first Chrome account.")

    func run() throws {
        let path = Paths.config()
        guard !FileManager.default.fileExists(atPath: path.path) else {
            throw ValidationError("\(path.path) already exists; it was left as it is")
        }
        let catalog = try? Inputs.profiles()
        try ConfigFile(url: path).write(StarterConfig.config(catalog: catalog), replacing: nil)
        print("wrote \(path.path)")
        if catalog == nil {
            print("note: Chrome's profiles could not be read, so the file has the window keys and no example site; `capsjump profiles` lists the accounts once Chrome has run")
        }
        print("next: edit it, then run `capsjump check`")
    }
}

struct Profiles: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List Chrome's profiles: folder, account and window label.")

    func run() throws {
        let catalog = try Inputs.profiles()
        let rows = catalog.profiles.map { profile in
            [profile.directory, profile.email.isEmpty ? "(not signed in)" : profile.email, profile.name,
             profile.windowLabel + (catalog.sharingLabel(with: profile).isEmpty ? "" : "  *")]
        }
        print(Table.render(header: ["FOLDER", "ACCOUNT", "NAME", "WINDOW LABEL"], rows: rows))
        if catalog.profiles.contains(where: { !catalog.sharingLabel(with: $0).isEmpty }) {
            print("\n* shared by two profiles: their windows can't be told apart, so their sites always open a new tab")
        }
    }
}

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Validate the config, resolve every site and key, and confirm CapsJump.app runs them.")

    func run() throws {
        let configPath = Paths.config()
        let statePath = Paths.chromeLocalState()
        var findings = Checkup.run(
            configText: try? String(contentsOf: configPath, encoding: .utf8),
            configPath: configPath.path,
            localState: FileManager.default.contents(atPath: statePath.path),
            localStatePath: statePath.path,
            lookup: Lookup.thisMac
        )
        findings.append(LinkHandler.finding())
        findings += KeyState.findings(config: try? Inputs.config(), running: KeyState.appIsRunning)
        for finding in findings {
            print("\(finding.level.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0))\(finding.text)")
        }
        if findings.contains(where: { $0.level == .problem }) {
            throw ExitCode.failure
        }
    }
}

struct Jump: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Jump to a site, exactly as its link does.")

    @Argument(help: "The site's name in ~/.capsjump.yaml.")
    var site: String

    func run() throws {
        let config = try Inputs.config()
        guard config.site(named: site) != nil else {
            throw JumpError.unknownSite(site, known: config.sites.map(\.name))
        }
        guard let url = Link.url(forSite: site) else {
            throw ValidationError("`\(site)` is not a valid site name")
        }
        try LinkHandler.open(url)
    }
}

struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open CapsJump's Welcome window, which asks for its permissions one at a time and turns on its first keys.")

    func run() throws {
        try LinkHandler.open(Link.setupURL)
        print("CapsJump's Welcome window is open; each step there ticks itself when it's done.")
    }
}

struct PauseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pause", abstract: "Pause the keys and give Caps Lock back, until `capsjump resume`.")

    func run() throws {
        try RunningApp.open(Link.pauseURL)
        print("paused; Caps Lock works as usual until `capsjump resume`")
    }
}

struct ResumeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "resume", abstract: "Turn the keys back on after `capsjump pause`.")

    func run() throws {
        try RunningApp.open(Link.resumeURL)
        print("resumed; hold Caps Lock and press a key")
    }
}

struct QuitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "quit", abstract: "Quit CapsJump.app, giving Caps Lock back. It starts again at the next login.")

    func run() throws {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Identity.bundleID)
        guard !apps.isEmpty else {
            print("CapsJump.app isn't running")
            return
        }
        for app in apps { app.terminate() }
        print("CapsJump.app is quitting; Caps Lock works as usual")
    }
}

struct NotRunning: Error, CustomStringConvertible {
    var description: String { "CapsJump.app isn't running; open it, or run `capsjump setup`" }
}

/// The app, reached by link only while it runs, so pausing never starts it.
enum RunningApp {
    static func open(_ url: URL) throws {
        guard KeyState.appIsRunning else {
            throw NotRunning()
        }
        try LinkHandler.open(url)
    }
}

struct Logs: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show CapsJump's recent log: every jump and every failure.")

    @Option(name: .long, help: "How far back to read, as `log show --last` takes it: 30m, 2h, 1d.")
    var last = "1h"

    func run() throws {
        let log = Process()
        log.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        log.arguments = ["show", "--last", last, "--style", "compact", "--predicate", "subsystem == \"\(Identity.bundleID)\""]
        try log.run()
        log.waitUntilExit()
        if log.terminationStatus != 0 {
            throw ExitCode(log.terminationStatus)
        }
    }
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "version", abstract: "Print CapsJump's version.")

    func run() {
        print(Version.current)
    }
}
