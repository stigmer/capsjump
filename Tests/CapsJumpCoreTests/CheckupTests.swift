// What `capsjump check` reports for a missing file, a bad config, and good sites.

import Foundation
import Testing
@testable import CapsJumpCore

@Suite struct CheckupTests {
    private func run(_ config: String?, _ state: String? = localState) -> [Finding] {
        Checkup.run(configText: config, configPath: "~/.capsjump.yaml", localState: state.map { Data($0.utf8) }, localStatePath: "Local State")
    }

    @Test func missingFilesAreProblems() {
        #expect(run(nil).map(\.level) == [.problem])
        #expect(run(nil).first?.text.contains("capsjump init") == true)
        #expect(run("sites: []", nil).first?.text.contains("has Chrome been opened") == true)
        #expect(run("sites: []", "{}").first?.level == .problem)
        #expect(run("sites: []").map(\.level) == [.note])
    }

    @Test func configProblemsAreListedWithThePath() {
        let findings = run("sites:\n  - name: x\n")
        #expect(findings.allSatisfy { $0.level == .problem && $0.text.hasPrefix("~/.capsjump.yaml: ") })
        #expect(findings.count == 2)
    }

    @Test func eachSiteResolvesOrSaysWhy() {
        let findings = run("""
        sites:
          - name: github
            account: alex@globex.io
            open: https://github.com
          - name: shared
            account: globex.io
            open: https://x.com
        """)
        #expect(findings == [
            Finding(.ok, "github → Profile 15, windows labelled “Alex (globex.io)”"),
            Finding(.problem, "shared: `globex.io` matches the profiles `Profile 15` and `Profile 17`; name one with `profile:`"),
        ])
    }

    @Test func sharedLabelIsANote() {
        let state = #"{"profile": {"info_cache": {"A": {"name": "Work"}, "B": {"name": "Work"}}}}"#
        let findings = run("sites:\n  - name: a\n    profile: A\n    open: https://x.com\n", state)
        #expect(findings.map(\.level) == [.note])
        #expect(findings.first?.text.contains("always opens a new tab, because B carries the same label") == true)
    }
}
