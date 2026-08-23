import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistGenerator

final class MockTestPlanLinter: TestPlanLinting {
    var issues: [LintingIssue] = []
    private(set) var lintedProjects: [Project] = []

    func lint(project: Project) -> [LintingIssue] {
        lintedProjects.append(project)
        return issues
    }
}
