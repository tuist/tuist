import Foundation
import ProjectDescription
import TuistCore
import TuistSupport
@testable import TuistLoader

class MockManifestLinter: ManifestLinting {
    var stubLintProject: [LintingIssue] = []
    func lint(project _: ProjectDescription.Project) -> [LintingIssue] {
        stubLintProject
    }
}
