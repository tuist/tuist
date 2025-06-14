import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistGenerator

class MockProjectLinter: ProjectLinting {
    func lint(_: Project) -> [LintingIssue] {
        []
    }
}
