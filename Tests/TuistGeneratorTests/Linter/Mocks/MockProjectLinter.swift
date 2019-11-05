import Foundation
import TuistSupport
@testable import TuistGenerator

class MockProjectLinter: ProjectLinting {
    func lint(_: Project) -> [LintingIssue] {
        return []
    }
}
