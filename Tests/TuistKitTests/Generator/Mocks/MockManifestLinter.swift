
import Foundation
import ProjectDescription
import TuistCore
@testable import TuistKit

class MockManifestLinter: ManifestLinting {
    var stubLintProject: [LintingIssue] = []
    func lint(project _: Project) -> [LintingIssue] {
        return stubLintProject
    }
}
