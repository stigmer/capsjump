// The capsjump command: writes and checks the config, lists Chrome's profiles, and
// hands links to CapsJump.app. It never talks to Chrome itself: the app holds the
// permissions, so `jump` and `setup` go through macOS's link handling to it.

import AppKit
import ArgumentParser
import Foundation
import CapsJumpChrome
import CapsJumpCore

@main
struct CapsJump: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capsjump",
        abstract: "Bring a site's tab forward in the right Chrome account, or open it there.",
        discussion: "Sites live in ~/.capsjump.yaml; each is the link capsjump://<name>.",
        version: Version.current,
        subcommands: [Init.self, Profiles.self, Check.self, Jump.self, Setup.self, Logs.self, VersionCommand.self]
    )
}

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Write a starter ~/.capsjump.yaml listing this Mac's Chrome accounts.")

    func run() throws {
        let path = Paths.config()
        guard !FileManager.default.fileExists(atPath: path.path) else {
            throw ValidationError("\(path.path) already exists; it was left as it is")
        }
        let catalog = try? Inputs.profiles()
        try StarterConfig.render(catalog: catalog).write(to: path, atomically: true, encoding: .utf8)
        print("wrote \(path.path)")
        if catalog == nil {
            print("note: Chrome's profiles could not be read, so none are listed; `capsjump profiles` lists them once Chrome has run")
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
    static let configuration = CommandConfiguration(abstract: "Validate the config, resolve every site, and confirm CapsJump.app receives the links.")

    func run() throws {
        let configPath = Paths.config()
        let statePath = Paths.chromeLocalState()
        var findings = Checkup.run(
            configText: try? String(contentsOf: configPath, encoding: .utf8),
            configPath: configPath.path,
            localState: FileManager.default.contents(atPath: statePath.path),
            localStatePath: statePath.path
        )
        findings.append(LinkHandler.finding())
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
    static let configuration = CommandConfiguration(abstract: "Ask macOS for CapsJump's permissions (Accessibility, Automation of Chrome, notifications).")

    func run() throws {
        try LinkHandler.open(Link.setupURL)
        print("CapsJump is asking for its permissions; its alert lists each one's state.")
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
