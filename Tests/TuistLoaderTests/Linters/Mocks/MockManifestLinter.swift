import Foundation
import ProjectDescription
import TuistCore
import TuistSupport
@testable import TuistLoader

class MockManifestLinter: ManifestLinting {
    var stubLintProject: [LintingIssue] = []
    var stubLintWorkspace: [LintingIssue] = []

    func lint(project _: ProjectDescription.Project) -> [LintingIssue] {
        stubLintProject
    }

    func lint(workspace _: ProjectDescription.Workspace) -> [TuistCore.LintingIssue] {
        stubLintWorkspace
    }
}
