import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
import FileSystemTesting
import Testing
@testable import TuistGenerator
@testable import TuistTesting

struct TargetScriptLinterTests {
    let subject: TargetScriptLinter
    init() {
        subject = TargetScriptLinter()
    }

    @Test
    func test_lint_whenTheToolDoesntExist() async throws {
        let action = TargetScript(
            name: "name",
            order: .pre,
            script: .tool(path: "randomtool")
        )
        let got = try await subject.lint(action)

        let expected = LintingIssue(
            reason: "The script tool 'randomtool' was not found in the environment",
            severity: .error
        )
        #expect(got.contains(expected))
    }

    @Test(.inTemporaryDirectory)
    func test_lint_whenPathDoesntExist() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let action = TargetScript(
            name: "name",
            order: .pre,
            script: .scriptPath(path: temporaryPath.appending(component: "invalid.sh"))
        )
        let got = try await subject.lint(action)

        let expected = LintingIssue(
            reason: "The script path \(action.path!.pathString) doesn't exist",
            severity: .error
        )
        #expect(got.contains(expected))
    }

    @Test
    func test_lint_succeeds_when_embedded() async throws {
        let action = TargetScript(
            name: "name",
            order: .pre,
            script: .embedded("echo 'Hello World'")
        )

        let got = try await subject.lint(action)
        let expected = [LintingIssue]()
        #expect(got.elementsEqual(expected))
    }

    @Test
    func test_lint_warns_when_embedded_script_empty() async throws {
        let action = TargetScript(
            name: "name",
            order: .pre,
            script: .embedded("")
        )

        let got = try await subject.lint(action)
        let expected = LintingIssue(reason: "The embedded script is empty", severity: .warning)
        #expect(got.contains(expected))
    }
}
