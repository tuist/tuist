import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
@testable import TuistGenerator

class MockProjectLinter: ProjectLinting {
    func lint(_: Project) -> [LintingIssue] {
        return []
    }
}
