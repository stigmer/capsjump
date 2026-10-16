// Saving the config on a real disk, in a temporary folder: a new file, a file that
// changed since it was read, a symlinked file (relative and absolute), its permissions, a
// read-only file, and that nothing is left behind.

import Foundation
import Testing
@testable import CapsJumpCore
@testable import CapsJumpSystem

@Suite final class ConfigFileTests {
    let folder: URL
    let config = Config(
        sites: [Site(name: "github", account: "alex@acme.dev", profile: nil, open: URL(string: "https://github.com/")!, match: ["github.com/"])],
        keys: [KeyBinding(key: "g", action: .site("github"))]
    )

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("capsjump-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func text(_ name: String) -> String? {
        try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    private func entries() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    @Test func createsTheFileOnlyWhenThereIsNone() throws {
        let file = ConfigFile(url: folder.appendingPathComponent(".capsjump.yaml"))
        let written = try file.write(config, replacing: nil)
        #expect(text(".capsjump.yaml") == written)
        #expect(throws: ConfigFile.Failure.changedOnDisk(path: file.url.path)) {
            try file.write(config, replacing: nil)
        }
        #expect(entries() == [".capsjump.yaml"])
    }

    @Test func replacesOnlyWhatItStartedFrom() throws {
        let url = folder.appendingPathComponent(".capsjump.yaml")
        try "keys:\n  f: { window: maximize }\n".write(to: url, atomically: false, encoding: .utf8)
        let file = ConfigFile(url: url)
        #expect(throws: ConfigFile.Failure.changedOnDisk(path: url.path)) {
            try file.write(config, replacing: "keys:\n  g: { window: maximize }\n")
        }
        #expect(text(".capsjump.yaml") == "keys:\n  f: { window: maximize }\n")
        #expect(throws: ConfigFile.Failure.changedOnDisk(path: url.path)) {
            try file.write(config, replacing: nil)
        }
        let written = try file.write(config, replacing: "keys:\n  f: { window: maximize }\n")
        #expect(text(".capsjump.yaml") == written)
        #expect(try ConfigParser.parse(written) == config)
        #expect(entries() == [".capsjump.yaml"])
    }

    @Test func writesThroughARelativeSymlink() throws {
        let dotfiles = folder.appendingPathComponent("dotfiles")
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try "sites: []\n".write(to: dotfiles.appendingPathComponent("capsjump.yaml"), atomically: false, encoding: .utf8)
        let link = folder.appendingPathComponent(".capsjump.yaml")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "dotfiles/capsjump.yaml")

        let written = try ConfigFile(url: link).write(config, replacing: "sites: []\n")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "dotfiles/capsjump.yaml")
        #expect(text("dotfiles/capsjump.yaml") == written)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: dotfiles.path)) == ["capsjump.yaml"])
    }

    @Test func writesThroughAChainOfAbsoluteSymlinks() throws {
        let target = folder.appendingPathComponent("real.yaml")
        try "sites: []\n".write(to: target, atomically: false, encoding: .utf8)
        let middle = folder.appendingPathComponent("middle.yaml")
        try FileManager.default.createSymbolicLink(atPath: middle.path, withDestinationPath: target.path)
        let link = folder.appendingPathComponent(".capsjump.yaml")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: middle.path)

        let written = try ConfigFile(url: link).write(config, replacing: "sites: []\n")
        #expect(text("real.yaml") == written)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == middle.path)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: middle.path) == target.path)
    }

    @Test func keepsTheFilesPermissions() throws {
        let url = folder.appendingPathComponent(".capsjump.yaml")
        try "sites: []\n".write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try ConfigFile(url: url).write(config, replacing: "sites: []\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func leavesAReadOnlyFileAlone() throws {
        let url = folder.appendingPathComponent(".capsjump.yaml")
        try "sites: []\n".write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        #expect(throws: ConfigFile.Failure.readOnly(path: url.path)) {
            try ConfigFile(url: url).write(config, replacing: "sites: []\n")
        }
        #expect(text(".capsjump.yaml") == "sites: []\n")
        #expect(entries() == [".capsjump.yaml"])
    }

    @Test func refusesWhatItCouldNotReadBack() throws {
        let url = folder.appendingPathComponent(".capsjump.yaml")
        let broken = Config(sites: [], keys: [KeyBinding(key: "G", action: .window(.maximize))])
        #expect {
            try ConfigFile(url: url).write(broken, replacing: nil)
        } throws: { error in
            guard case let .refused(problems) = error as? ConfigFile.Failure else { return false }
            return problems.description.contains("unknown key name `G`")
        }
        #expect(entries().isEmpty)
    }

    @Test func readsNothingABrokenFileOrAConfig() throws {
        let url = folder.appendingPathComponent(".capsjump.yaml")
        let file = ConfigFile(url: url)
        #expect(try file.read() == nil)

        try "keys:\n  G: { window: maximize }\n".write(to: url, atomically: false, encoding: .utf8)
        let broken = try #require(try file.read())
        #expect(broken.text == "keys:\n  G: { window: maximize }\n")
        guard case let .failure(error) = broken.result else {
            Issue.record("a broken file read as a config")
            return
        }
        #expect(error.problems == ["line 2: keys.G: unknown key name `G` (key names: a–z, 0–9, f1–f12, left, right, up, down)"])

        let written = try file.write(config, replacing: broken.text)
        #expect(try file.read() == ConfigFile.Contents(text: written, result: .success(config)))
    }
}
